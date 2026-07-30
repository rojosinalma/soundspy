// soundspy node firmware — ESP32 + ICS-43434 I2S MEMS mic

#include <WiFi.h>
#include <PubSubClient.h>
#include <WebSocketsClient.h>
#include <HTTPUpdate.h>
#include <HTTPClient.h>
#include <esp_ota_ops.h>
#include <driver/i2s.h>
#include <math.h>
#include <base64.h>
#include <ArduinoJson.h>

const char* FIRMWARE_VERSION = "1.3.1";

const char* WIFI_SSID  = "PLACEHOLDER_WIFI_SSID";
const char* WIFI_PASS  = "PLACEHOLDER_WIFI_PASS";
const char* MQTT_HOST  = "PLACEHOLDER_MQTT_HOST";
const int   MQTT_PORT  = PLACEHOLDER_MQTT_PORT;
const char* WS_HOST    = "PLACEHOLDER_WS_HOST";
const int   WS_PORT    = PLACEHOLDER_WS_PORT;

// Node ID derived from chip's unique ID (lower 4 bytes of MAC)
char NODE_ID[9];

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

void remoteLog(const char* level, const char* msg) {
  Serial.printf("[%s] %s\n", level, msg);
  if (mqtt.connected()) {
    char payload[384];
    snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"level\":\"%s\",\"msg\":\"%s\",\"uptime_ms\":%lu,\"firmware\":\"%s\"}",
      NODE_ID, level, msg, millis(), FIRMWARE_VERSION);
    String topic = String("soundspy/") + NODE_ID + "/log";
    mqtt.publish(topic.c_str(), payload);
  }
}

void publishBootReport() {
  const esp_partition_t* running = esp_ota_get_running_partition();
  char payload[384];
  snprintf(payload, sizeof(payload),
    "{\"node\":\"%s\",\"firmware\":\"%s\",\"reset_reason\":%d,\"partition\":\"%s\",\"free_heap\":%u,\"ip\":\"%s\"}",
    NODE_ID, FIRMWARE_VERSION, (int)esp_reset_reason(),
    running ? running->label : "unknown",
    ESP.getFreeHeap(),
    WiFi.localIP().toString().c_str());
  String topic = String("soundspy/") + NODE_ID + "/boot";
  mqtt.publish(topic.c_str(), payload);
}

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
  {"sub_bass"},  // 50-120 Hz
  {"bass"},      // 120-250 Hz
  {"low_mid"},   // 250-500 Hz
  {"mid"},       // 500-2000 Hz
  {"high_mid"},  // 2000-6000 Hz
  {"high"}       // 6000-20000 Hz
};

const int NUM_BANDS = sizeof(bands) / sizeof(bands[0]);

double sumSquaresOverall = 0;
uint32_t sampleCount = 0;
unsigned long lastPublish = 0;
uint32_t messageSeq = 0;

// I2S watchdog — detect bus lockup (sustained -180 dBFS)
#define I2S_WATCHDOG_THRESHOLD 150  // ~3 seconds at 50Hz before reinit
#define I2S_WATCHDOG_DBFS_FLOOR -170.0f
#define I2S_STARTUP_GRACE_MS 5000   // ignore dead reads for 5s after boot
int i2sLockupCount = 0;
unsigned long bootTime = 0;

int i2sReinitCount = 0;

void reinitI2S() {
  remoteLog("warn", "I2S watchdog: reinitializing bus");
  i2s_driver_uninstall(I2S_PORT);
  delay(200);
  setupI2S();
  size_t discard;
  for (int i = 0; i < 4; i++) {
    i2s_read(I2S_PORT, i2s_read_buf, sizeof(i2s_read_buf), &discard, 100);
  }
  i2sReinitCount++;
}

void configureBands() {
  // Bands aligned to ICS-43434 usable range (50 Hz - 20 kHz)
  bands[0].bp1 = {0.004962f, 0.0f, -0.004962f, -1.9900f, 0.9901f};
  bands[0].bp2 = {0.004962f, 0.0f, -0.004962f, -1.9900f, 0.9901f};
  bands[1].bp1 = {0.009175f, 0.0f, -0.009175f, -1.9810f, 0.9816f};
  bands[1].bp2 = {0.009175f, 0.0f, -0.009175f, -1.9810f, 0.9816f};
  bands[2].bp1 = {0.017491f, 0.0f, -0.017491f, -1.9625f, 0.9650f};
  bands[2].bp2 = {0.017491f, 0.0f, -0.017491f, -1.9625f, 0.9650f};
  bands[3].bp1 = {0.096246f, 0.0f, -0.096246f, -1.7892f, 0.8075f};
  bands[3].bp2 = {0.096246f, 0.0f, -0.096246f, -1.7892f, 0.8075f};
  bands[4].bp1 = {0.214777f, 0.0f, -0.214777f, -1.3830f, 0.5704f};
  bands[4].bp2 = {0.214777f, 0.0f, -0.214777f, -1.3830f, 0.5704f};
  bands[5].bp1 = {0.389863f, 0.0f, -0.389863f, -0.0123f, 0.2203f};
  bands[5].bp2 = {0.389863f, 0.0f, -0.389863f, -0.0123f, 0.2203f};
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

  // Handle reboot command
  if (doc.containsKey("reboot") && doc["reboot"] == true) {
    remoteLog("info", "Reboot requested");
    delay(200);
    ESP.restart();
  }

  // Handle deep sleep (power off) — only wakes on physical reset
  if (doc.containsKey("sleep") && doc["sleep"] == true) {
    remoteLog("info", "Entering deep sleep (power off)");
    mqtt.loop();
    delay(200);
    esp_deep_sleep_start();
  }

  // Handle gain control
  if (doc.containsKey("gain")) {
    float newGain = doc["gain"];
    if (newGain >= 0.0f && newGain <= 10.0f) {  // Safety limits for INMP441
      audioGain = newGain;
      Serial.print("[IMPORTANT] Gain updated to: ");
      Serial.println(audioGain);
    }
  }
}

void connectMQTT() {
  mqtt.setBufferSize(512);
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

  // Derive node ID from chip's unique fuse MAC (deterministic, no config needed)
  uint64_t mac = ESP.getEfuseMac();
  snprintf(NODE_ID, sizeof(NODE_ID), "%02x%02x%02x%02x",
    (uint8_t)(mac), (uint8_t)(mac >> 8), (uint8_t)(mac >> 16), (uint8_t)(mac >> 24));

  Serial.println("\n\n[IMPORTANT] ========================================");
  Serial.print("[IMPORTANT] soundspy node starting - Firmware v");
  Serial.println(FIRMWARE_VERSION);
  Serial.print("[IMPORTANT] Node ID: ");
  Serial.println(NODE_ID);
  Serial.println("[IMPORTANT] ========================================\n");

  connectWiFi();
  connectMQTT();

  // Confirm OTA partition is valid — if this never runs, bootloader rolls back
  esp_ota_mark_app_valid_cancel_rollback();
  publishBootReport();
  remoteLog("boot", "Stage 1 OK: WiFi + MQTT connected");
  mqtt.loop();

  configureBands();
  setupI2S();
  connectWebSocket();
  lastPublish = millis();
  bootTime = millis();

  remoteLog("boot", "Stage 2 OK: I2S + WebSocket initialized");
  mqtt.loop();
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

    // I2S watchdog: detect sustained silence (bus lockup)
    // Skip during startup grace period
    if (dbfsOverall < I2S_WATCHDOG_DBFS_FLOOR && millis() - bootTime > I2S_STARTUP_GRACE_MS) {
      i2sLockupCount++;
      if (i2sReinitCount >= 3) {
        // Don't reboot — stay alive so MQTT control (OTA, diag) still works
        i2sLockupCount = 0;
        return;
      } else if (i2sLockupCount >= I2S_WATCHDOG_THRESHOLD) {
        reinitI2S();
        i2sLockupCount = 0;
        bootTime = millis();  // fresh grace window after reinit
        sumSquaresOverall = 0;
        sampleCount = 0;
        lastPublish = millis();
        return;
      }
    } else {
      i2sLockupCount = 0;
      i2sReinitCount = 0;  // good data = reset reinit counter
    }

    char payload[512];
    unsigned long timestamp_ms = millis();
    String ipAddress = WiFi.localIP().toString();
    int len = snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"seq\":%u,\"ts\":%lu,\"firmware\":\"%s\",\"ip\":\"%s\",\"overall_dbfs\":%.1f,\"bands\":{",
      NODE_ID, messageSeq++, timestamp_ms, FIRMWARE_VERSION, ipAddress.c_str(), dbfsOverall);

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
