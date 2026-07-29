/*
  Sound Monitor Node with Audio Streaming — ESP32 + I2S mic
  VERSION: 0.8.3

  Multi-band frequency analysis + real-time audio streaming to web dashboard.

  See CHANGELOG.md for version history.

  IMPORTANT:
  - When using build_firmware.sh: values are injected from .env file
  - When using Arduino IDE directly: edit config values below manually
*/

#include <WiFi.h>
#include <PubSubClient.h>
#include <WebSocketsClient.h>
#include <HTTPUpdate.h>
#include <HTTPClient.h>
#include <driver/i2s.h>
#include <math.h>
#include <base64.h>
#include <ArduinoJson.h>

// ---------- PER-NODE CONFIG ----------
// NOTE: These values are injected by build_firmware.sh from .env file
// When building manually in Arduino IDE, edit these directly
// When using build_firmware.sh, values come from .env
const char* FIRMWARE_VERSION = "0.8.3";
const char* NODE_ID    = "node1";              // node1, node2, node3, etc.
const char* WIFI_SSID  = "rojo_IoT";
const char* WIFI_PASS  = "19032000";
const char* MQTT_HOST  = "10.10.10.20";        // silver server IP
const int   MQTT_PORT  = 1883;
const char* WS_HOST    = "10.10.10.20";        // WebSocket server (same as MQTT)
const int   WS_PORT    = 8091;
// ---------------------------------------

// I2S pins
#define I2S_WS   25
#define I2S_SD   32
#define I2S_SCK  33
#define I2S_PORT I2S_NUM_0

// Audio config
#define SAMPLE_RATE     44100
#define SAMPLES_PER_READ 1024
#define PUBLISH_INTERVAL_MS 20  // 50Hz update rate

// Audio streaming config - NO DOWNSAMPLING for now
#define STREAM_SAMPLE_RATE 44100  // Full sample rate
#define STREAM_CHUNK_SIZE 4410    // 100ms chunks at 44.1kHz

int32_t i2s_read_buf[SAMPLES_PER_READ];
int16_t audioStreamBuffer[STREAM_CHUNK_SIZE];
int audioStreamIndex = 0;

// Remote-controllable gain
float audioGain = 4.0f;  // Default gain (12dB)

WiFiClient espClient;
PubSubClient mqtt(espClient);
WebSocketsClient webSocket;

// 2nd-order biquad filter
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

double sumSquaresOverall = 0;
uint32_t sampleCount = 0;
unsigned long lastPublish = 0;
uint32_t messageSeq = 0;

void configureBands() {
  bands[0].bp1 = {0.000108f, 0.0f, -0.000108f, -1.9994f, 0.9998f};
  bands[0].bp2 = {0.000108f, 0.0f, -0.000108f, -1.9994f, 0.9998f};
  bands[1].bp1 = {0.00128f, 0.0f, -0.00128f, -1.9948f, 0.9974f};
  bands[1].bp2 = {0.00128f, 0.0f, -0.00128f, -1.9948f, 0.9974f};
  bands[2].bp1 = {0.00285f, 0.0f, -0.00285f, -1.9828f, 0.9943f};
  bands[2].bp2 = {0.00285f, 0.0f, -0.00285f, -1.9828f, 0.9943f};
  bands[3].bp1 = {0.0170f, 0.0f, -0.0170f, -1.8851f, 0.9660f};
  bands[3].bp2 = {0.0170f, 0.0f, -0.0170f, -1.8851f, 0.9660f};
  bands[4].bp1 = {0.0556f, 0.0f, -0.0556f, -1.4142f, 0.8889f};
  bands[4].bp2 = {0.0556f, 0.0f, -0.0556f, -1.4142f, 0.8889f};
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
  Serial.print("[IMPORTANT] Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(" connected");
}

void performOTA(const char* firmwareUrl) {
  Serial.println("[IMPORTANT] Starting OTA update...");
  Serial.print("[IMPORTANT] Firmware URL: ");
  Serial.println(firmwareUrl);

  WiFiClient client;
  // Don't use LED_BUILTIN as it may not be defined on all boards
  // httpUpdate.setLedPin(LED_BUILTIN, LOW);

  httpUpdate.onStart([]() {
    Serial.println("[IMPORTANT] OTA started - downloading firmware");
  });

  httpUpdate.onEnd([]() {
    Serial.println("[IMPORTANT] OTA finished successfully");
  });

  httpUpdate.onProgress([](int current, int total) {
    static int lastPercent = -1;
    int percent = (current * 100) / total;
    // Only log every 10%
    if (percent >= lastPercent + 10) {
      Serial.printf("[IMPORTANT] OTA Progress: %d%%\n", percent);
      lastPercent = percent;
    }
  });

  httpUpdate.onError([](int error) {
    Serial.printf("[IMPORTANT] OTA Error[%d]: ", error);
    Serial.println(httpUpdate.getLastErrorString());
  });

  t_httpUpdate_return ret = httpUpdate.update(client, firmwareUrl);

  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("[IMPORTANT] OTA failed: %s\n", httpUpdate.getLastErrorString().c_str());
      break;
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("[IMPORTANT] No updates available");
      break;
    case HTTP_UPDATE_OK:
      Serial.println("[IMPORTANT] Update successful, rebooting...");
      ESP.restart();
      break;
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Parse control messages
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, payload, length);

  if (error) {
    Serial.print("JSON parse error: ");
    Serial.println(error.c_str());
    return;
  }

  // Handle OTA update
  if (doc.containsKey("ota_url")) {
    const char* firmwareUrl = doc["ota_url"];
    Serial.println("[IMPORTANT] OTA update requested");
    performOTA(firmwareUrl);
    return;  // Function will reboot after update
  }

  // Handle gain control
  if (doc.containsKey("gain")) {
    float newGain = doc["gain"];
    if (newGain >= 0.0f && newGain <= 20.0f) {  // Safety limits (allow 0 now)
      audioGain = newGain;
      Serial.print("[IMPORTANT] Gain updated to: ");
      Serial.println(audioGain);
    }
  }
}

void connectMQTT() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);

  while (!mqtt.connected()) {
    Serial.print("[IMPORTANT] Connecting to MQTT...");
    String clientId = String("esp32-") + NODE_ID;
    if (mqtt.connect(clientId.c_str())) {
      Serial.println(" connected");

      // Subscribe to control topic
      String controlTopic = String("soundspy/") + NODE_ID + "/control";
      mqtt.subscribe(controlTopic.c_str());
      Serial.print("[IMPORTANT] Subscribed to: ");
      Serial.println(controlTopic);

      // Publish version info on connect
      String versionTopic = String("soundspy/") + NODE_ID + "/version";
      String versionPayload = String("{\"node\":\"") + NODE_ID + "\",\"firmware\":\"" + FIRMWARE_VERSION + "\"}";
      mqtt.publish(versionTopic.c_str(), versionPayload.c_str());
      Serial.print("[IMPORTANT] Published firmware version: ");
      Serial.println(FIRMWARE_VERSION);
    } else {
      Serial.print("[IMPORTANT] failed, rc=");
      Serial.print(mqtt.state());
      Serial.println(" retrying in 2s");
      delay(2000);
    }
  }
}

void webSocketEvent(WStype_t type, uint8_t * payload, size_t length) {
  switch(type) {
    case WStype_DISCONNECTED:
      Serial.println("[IMPORTANT] WebSocket disconnected");
      break;
    case WStype_CONNECTED:
      Serial.println("[IMPORTANT] WebSocket connected");
      break;
  }
}

void connectWebSocket() {
  webSocket.begin(WS_HOST, WS_PORT, "/ws/audio");
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);
}

void sendAudioChunk() {
  // Base64 encode the audio buffer
  String encoded = base64::encode((uint8_t*)audioStreamBuffer, audioStreamIndex * 2);

  // Send via WebSocket as JSON
  String payload = "{\"node_id\":\"" + String(NODE_ID) + "\",\"audio\":\"" + encoded + "\"}";
  webSocket.sendTXT(payload);

  audioStreamIndex = 0;
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n\n[IMPORTANT] ========================================");
  Serial.print("[IMPORTANT] soundspy node starting - Firmware v");
  Serial.println(FIRMWARE_VERSION);
  Serial.print("[IMPORTANT] Node ID: ");
  Serial.println(NODE_ID);
  Serial.println("[IMPORTANT] ========================================\n");

  configureBands();
  setupI2S();
  connectWiFi();
  connectMQTT();
  connectWebSocket();
  lastPublish = millis();

  Serial.println("[IMPORTANT] Initialization complete, starting main loop\n");
}

void loop() {
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();
  webSocket.loop();

  size_t bytesRead = 0;
  i2s_read(I2S_PORT, i2s_read_buf, sizeof(i2s_read_buf), &bytesRead, portMAX_DELAY);
  int samplesRead = bytesRead / sizeof(int32_t);

  for (int i = 0; i < samplesRead; i++) {
    int32_t raw = i2s_read_buf[i] >> 8;
    float sample = (float)raw / 8388608.0f;

    // Apply mic gain FIRST - affects everything downstream
    sample *= audioGain;
    sample = constrain(sample, -1.0f, 1.0f);  // Clamp to prevent overflow

    sumSquaresOverall += (double)(sample * sample);

    for (int b = 0; b < NUM_BANDS; b++) {
      float filtered = bands[b].bp1.process(sample);
      filtered = bands[b].bp2.process(filtered);
      bands[b].sumSquares += (double)(filtered * filtered);
    }

    sampleCount++;

    // Convert to 16-bit PCM for streaming (already has gain applied)
    int16_t pcm16 = (int16_t)(sample * 32767.0f);
    audioStreamBuffer[audioStreamIndex++] = pcm16;

    // Send chunk when full (100ms worth)
    if (audioStreamIndex >= STREAM_CHUNK_SIZE) {
      sendAudioChunk();
    }
  }

  // Publish frequency analysis data once per second
  if (millis() - lastPublish >= PUBLISH_INTERVAL_MS && sampleCount > 0) {
    float rmsOverall = sqrt(sumSquaresOverall / sampleCount);
    float dbfsOverall = 20.0f * log10f(rmsOverall + 1e-9f);

    char payload[512];
    unsigned long timestamp_ms = millis();
    int len = snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"seq\":%u,\"ts\":%lu,\"firmware\":\"%s\",\"overall_dbfs\":%.1f,\"bands\":{",
      NODE_ID, messageSeq++, timestamp_ms, FIRMWARE_VERSION, dbfsOverall);

    for (int b = 0; b < NUM_BANDS; b++) {
      float rmsBand = sqrt(bands[b].sumSquares / sampleCount);
      float dbfsBand = 20.0f * log10f(rmsBand + 1e-9f);

      len += snprintf(payload + len, sizeof(payload) - len,
        "\"%s\":%.1f", bands[b].name, dbfsBand);

      if (b < NUM_BANDS - 1) {
        len += snprintf(payload + len, sizeof(payload) - len, ",");
      }

      bands[b].sumSquares = 0;
    }

    len += snprintf(payload + len, sizeof(payload) - len, "}}");

    String topic = String("soundspy/") + NODE_ID + "/data";
    mqtt.publish(topic.c_str(), payload);

    // Don't spam serial with every message (50Hz = too much)
    // Only log important events in other functions

    sumSquaresOverall = 0;
    sampleCount = 0;
    lastPublish = millis();
  }
}
