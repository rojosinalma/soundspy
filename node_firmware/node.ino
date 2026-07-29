/*
  Bass Monitor Node — ESP32 + I2S mic (INMP441 or ICS-43434)

  Reads audio via I2S, computes:
    - overall_dbfs : RMS level of the full captured band (relative dBFS, not calibrated SPL)
    - bass_dbfs    : RMS level after a ~150Hz lowpass (isolates the bass/low-freq band)
  and publishes both over MQTT once per second.

  Wiring (same for INMP441 and ICS-43434 — pin-compatible):
    VDD  -> 3.3V
    GND  -> GND
    SD   -> GPIO32   (I2S data in)
    WS   -> GPIO25   (I2S word select / LR clock)
    SCK  -> GPIO33   (I2S bit clock)
    L/R  -> GND      (selects left channel; tie to 3.3V for right if ever needed)

  IMPORTANT: set NODE_ID, WIFI_SSID, WIFI_PASS, MQTT_HOST below per-device
  before flashing each of the 3 boards.
*/

#include <WiFi.h>
#include <PubSubClient.h>
#include <driver/i2s.h>
#include <math.h>

// ---------- PER-NODE CONFIG (edit NODE_ID for each of the 3 boards) ----------
const char* NODE_ID    = "wall1";              // wall1, wall2, wall3
const char* WIFI_SSID  = "rojo_IoT";
const char* WIFI_PASS  = "19032000";
const char* MQTT_HOST  = "10.10.10.20";        // silver server IP
const int   MQTT_PORT  = 1883;
// -----------------------------------------------------------------------------

// I2S pins (identical across all 3 nodes)
#define I2S_WS   25
#define I2S_SD   32
#define I2S_SCK  33
#define I2S_PORT I2S_NUM_0

// Audio config
#define SAMPLE_RATE     44100
#define SAMPLES_PER_READ 1024
#define PUBLISH_INTERVAL_MS 1000

int32_t i2s_read_buf[SAMPLES_PER_READ];

WiFiClient espClient;
PubSubClient mqtt(espClient);

// --- simple 2nd-order Butterworth lowpass biquad, cascaded x2 (~150Hz @ 44.1kHz) ---
// Coefficients precomputed for fc=150Hz, fs=44100Hz, Q=0.707
struct Biquad {
  float b0, b1, b2, a1, a2;
  float z1 = 0, z2 = 0;
  float process(float in) {
    float out = b0 * in + z1;
    z1 = b1 * in + z2 - a1 * out;
    z2 = b2 * in - a2 * out;
    return out;
  }
};

Biquad lp1, lp2;

void configureLowpass() {
  // fc=150Hz, fs=44100Hz Butterworth LPF coefficients (Q=0.7071)
  float b0 = 0.0000453f, b1 = 0.0000906f, b2 = 0.0000453f;
  float a1 = -1.9772f,  a2 = 0.9776f;
  lp1 = {b0, b1, b2, a1, a2};
  lp2 = {b0, b1, b2, a1, a2};
}

// accumulators for 1-second aggregation
double sumSquaresOverall = 0;
double sumSquaresBass = 0;
uint32_t sampleCount = 0;
unsigned long lastPublish = 0;

void setupI2S() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 8,
    .dma_buf_len = SAMPLES_PER_READ,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_PORT, &pin_config);
}

void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(" connected");
}

void connectMQTT() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()) {
    Serial.print("Connecting to MQTT...");
    String clientId = String("esp32-") + NODE_ID;
    if (mqtt.connect(clientId.c_str())) {
      Serial.println(" connected");
    } else {
      Serial.print("failed, rc=");
      Serial.print(mqtt.state());
      Serial.println(" retrying in 2s");
      delay(2000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  configureLowpass();
  setupI2S();
  connectWiFi();
  connectMQTT();
  lastPublish = millis();
}

void loop() {
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  size_t bytesRead = 0;
  i2s_read(I2S_PORT, i2s_read_buf, sizeof(i2s_read_buf), &bytesRead, portMAX_DELAY);
  int samplesRead = bytesRead / sizeof(int32_t);

  for (int i = 0; i < samplesRead; i++) {
    // INMP441/ICS-43434 output 24-bit data left-justified in the 32-bit word
    int32_t raw = i2s_read_buf[i] >> 8;          // shift down to 24-bit signed value
    float sample = (float)raw / 8388608.0f;      // normalize to [-1.0, 1.0] (2^23)

    sumSquaresOverall += (double)(sample * sample);

    float bass = lp1.process(sample);
    bass = lp2.process(bass);
    sumSquaresBass += (double)(bass * bass);

    sampleCount++;
  }

  if (millis() - lastPublish >= PUBLISH_INTERVAL_MS && sampleCount > 0) {
    float rmsOverall = sqrt(sumSquaresOverall / sampleCount);
    float rmsBass = sqrt(sumSquaresBass / sampleCount);

    // relative dBFS (0 dBFS = full-scale digital signal). NOT calibrated SPL —
    // calibrate empirically by noting readings during known-loud reference events.
    float dbfsOverall = 20.0f * log10f(rmsOverall + 1e-9f);
    float dbfsBass = 20.0f * log10f(rmsBass + 1e-9f);

    char payload[160];
    snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"overall_dbfs\":%.1f,\"bass_dbfs\":%.1f}",
      NODE_ID, dbfsOverall, dbfsBass);

    String topic = String("bassmonitor/") + NODE_ID + "/data";
    mqtt.publish(topic.c_str(), payload);

    Serial.println(payload);

    sumSquaresOverall = 0;
    sumSquaresBass = 0;
    sampleCount = 0;
    lastPublish = millis();
  }
}

