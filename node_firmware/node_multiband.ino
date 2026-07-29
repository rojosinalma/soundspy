/*
  Sound Monitor Node — ESP32 + I2S mic (INMP441 or ICS-43434)
  VERSION: 0.5

  Multi-band frequency analysis version.

  Reads audio via I2S, computes:
    - overall_dbfs : RMS level of the full captured band
    - Multiple frequency bands using cascaded biquad bandpass filters:
        * sub_bass:  20-60 Hz   (wall resonance band)
        * bass:      60-250 Hz  (bass guitar fundamentals)
        * low_mid:   250-500 Hz (lower mids)
        * mid:       500-2k Hz  (presence, vocals)
        * high_mid:  2k-4k Hz   (clarity)
        * high:      4k-8k Hz   (air, cymbals)

  Publishes all bands over MQTT once per second.

  Wiring (same for INMP441 and ICS-43434 — pin-compatible):
    VDD  -> 3.3V
    GND  -> GND
    SD   -> GPIO32   (I2S data in)
    WS   -> GPIO25   (I2S word select / LR clock)
    SCK  -> GPIO33   (I2S bit clock)
    L/R  -> GND      (selects left channel)

  IMPORTANT: set NODE_ID, WIFI_SSID, WIFI_PASS, MQTT_HOST below per-device
*/

#include <WiFi.h>
#include <PubSubClient.h>
#include <driver/i2s.h>
#include <math.h>

// ---------- PER-NODE CONFIG (edit NODE_ID for each board) ----------
const char* NODE_ID    = "wall1";              // wall1, wall2, wall3, etc.
const char* WIFI_SSID  = "rojo_IoT";
const char* WIFI_PASS  = "19032000";
const char* MQTT_HOST  = "10.10.10.20";        // silver server IP
const int   MQTT_PORT  = 1883;
// -------------------------------------------------------------------

// I2S pins
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

// 2nd-order biquad filter (direct form II transposed)
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

// Define frequency bands
// Each band uses 2x cascaded biquad bandpass filters for steeper rolloff
struct FreqBand {
  const char* name;
  Biquad bp1, bp2;
  double sumSquares = 0;
};

FreqBand bands[] = {
  {"sub_bass"},  // 20-60 Hz
  {"bass"},      // 60-250 Hz
  {"low_mid"},   // 250-500 Hz
  {"mid"},       // 500-2000 Hz
  {"high_mid"},  // 2000-4000 Hz
  {"high"}       // 4000-8000 Hz
};

const int NUM_BANDS = sizeof(bands) / sizeof(bands[0]);

// Overall level accumulators
double sumSquaresOverall = 0;
uint32_t sampleCount = 0;
unsigned long lastPublish = 0;
uint32_t messageSeq = 0;  // Sequence counter for message correlation

void configureBands() {
  // Butterworth bandpass coefficients for fs=44100Hz
  // Generated using standard biquad formulas: https://www.w3.org/TR/audio-eq-cookbook/

  // Sub-bass: 20-60 Hz (critical for wall resonance)
  bands[0].bp1 = {0.000108f, 0.0f, -0.000108f, -1.9994f, 0.9998f};
  bands[0].bp2 = {0.000108f, 0.0f, -0.000108f, -1.9994f, 0.9998f};

  // Bass: 60-250 Hz
  bands[1].bp1 = {0.00128f, 0.0f, -0.00128f, -1.9948f, 0.9974f};
  bands[1].bp2 = {0.00128f, 0.0f, -0.00128f, -1.9948f, 0.9974f};

  // Low-mid: 250-500 Hz
  bands[2].bp1 = {0.00285f, 0.0f, -0.00285f, -1.9828f, 0.9943f};
  bands[2].bp2 = {0.00285f, 0.0f, -0.00285f, -1.9828f, 0.9943f};

  // Mid: 500-2000 Hz
  bands[3].bp1 = {0.0170f, 0.0f, -0.0170f, -1.8851f, 0.9660f};
  bands[3].bp2 = {0.0170f, 0.0f, -0.0170f, -1.8851f, 0.9660f};

  // High-mid: 2000-4000 Hz
  bands[4].bp1 = {0.0556f, 0.0f, -0.0556f, -1.4142f, 0.8889f};
  bands[4].bp2 = {0.0556f, 0.0f, -0.0556f, -1.4142f, 0.8889f};

  // High: 4000-8000 Hz
  bands[5].bp1 = {0.1340f, 0.0f, -0.1340f, -0.5412f, 0.7321f};
  bands[5].bp2 = {0.1340f, 0.0f, -0.1340f, -0.5412f, 0.7321f};
}

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
  configureBands();
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
    // INMP441/ICS-43434: 24-bit left-justified in 32-bit word
    int32_t raw = i2s_read_buf[i] >> 8;
    float sample = (float)raw / 8388608.0f;  // normalize to [-1.0, 1.0]

    sumSquaresOverall += (double)(sample * sample);

    // Process through all frequency bands
    for (int b = 0; b < NUM_BANDS; b++) {
      float filtered = bands[b].bp1.process(sample);
      filtered = bands[b].bp2.process(filtered);
      bands[b].sumSquares += (double)(filtered * filtered);
    }

    sampleCount++;
  }

  if (millis() - lastPublish >= PUBLISH_INTERVAL_MS && sampleCount > 0) {
    float rmsOverall = sqrt(sumSquaresOverall / sampleCount);
    float dbfsOverall = 20.0f * log10f(rmsOverall + 1e-9f);

    // Build JSON payload with all bands
    char payload[512];
    unsigned long timestamp_ms = millis();
    int len = snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"seq\":%u,\"ts\":%lu,\"overall_dbfs\":%.1f,\"bands\":{",
      NODE_ID, messageSeq++, timestamp_ms, dbfsOverall);

    for (int b = 0; b < NUM_BANDS; b++) {
      float rmsBand = sqrt(bands[b].sumSquares / sampleCount);
      float dbfsBand = 20.0f * log10f(rmsBand + 1e-9f);

      len += snprintf(payload + len, sizeof(payload) - len,
        "\"%s\":%.1f", bands[b].name, dbfsBand);

      if (b < NUM_BANDS - 1) {
        len += snprintf(payload + len, sizeof(payload) - len, ",");
      }

      bands[b].sumSquares = 0;  // reset for next interval
    }

    len += snprintf(payload + len, sizeof(payload) - len, "}}");

    String topic = String("soundspy/") + NODE_ID + "/data";
    mqtt.publish(topic.c_str(), payload);

    Serial.println(payload);

    sumSquaresOverall = 0;
    sampleCount = 0;
    lastPublish = millis();
  }
}
