// soundspy node firmware — ESP32 + ICS-43434 I2S MEMS mic

#include <WiFi.h>
#include <PubSubClient.h>
#include <WebSocketsClient.h>
#include <HTTPUpdate.h>
#include <esp_ota_ops.h>
#include <driver/i2s.h>
#include <math.h>
#include <base64.h>
#include <ArduinoJson.h>
#include <esp_system.h>
#include <driver/adc.h>
#include <Preferences.h>

const char* FIRMWARE_VERSION = "1.6.0";

// --- NVS credentials (written by recovery portal or build_firmware.sh on first flash) ---
#define PIN_BOOT 0  // built-in BOOT button, active LOW

static char WIFI_SSID_BUF[64];
static char WIFI_PASS_BUF[64];
static char MQTT_HOST_BUF[64];
static int  MQTT_PORT_VAL = 1883;
static char WS_HOST_BUF[64];
static int  WS_PORT_VAL  = 8091;

const char* WIFI_SSID  = WIFI_SSID_BUF;
const char* WIFI_PASS  = WIFI_PASS_BUF;
const char* MQTT_HOST  = MQTT_HOST_BUF;
const char* WS_HOST    = WS_HOST_BUF;

void loadCredentials() {
  Preferences prefs;
  prefs.begin("soundspy", true);
  strlcpy(WIFI_SSID_BUF, prefs.getString("wifi_ssid", "PLACEHOLDER_WIFI_SSID").c_str(), sizeof(WIFI_SSID_BUF));
  strlcpy(WIFI_PASS_BUF, prefs.getString("wifi_pass", "PLACEHOLDER_WIFI_PASS").c_str(), sizeof(WIFI_PASS_BUF));
  strlcpy(MQTT_HOST_BUF, prefs.getString("mqtt_host", "PLACEHOLDER_MQTT_HOST").c_str(), sizeof(MQTT_HOST_BUF));
  MQTT_PORT_VAL = prefs.getInt("mqtt_port", PLACEHOLDER_MQTT_PORT);
  strlcpy(WS_HOST_BUF,   prefs.getString("ws_host",   "PLACEHOLDER_WS_HOST").c_str(), sizeof(WS_HOST_BUF));
  WS_PORT_VAL = prefs.getInt("ws_port", PLACEHOLDER_WS_PORT);
  prefs.end();
}

// --- Crash counter in RTC (counts boots; cleared after successful MQTT connect) ---
#define CRASH_BOOT_LIMIT 3

RTC_DATA_ATTR uint32_t crashBootCount = 0;
RTC_DATA_ATTR uint32_t crashBootMagic = 0;
#define CRASH_MAGIC 0xDEAD1234

void bootIntoRecovery() {
  Serial.println("[IMPORTANT] Crash limit reached — booting into recovery");
  const esp_partition_t* factory = esp_partition_find_first(
    ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_FACTORY, NULL);
  if (factory) {
    esp_ota_set_boot_partition(factory);
    delay(200);
    ESP.restart();
  }
  // If no factory partition, just hang — USB flash required
  Serial.println("[IMPORTANT] No factory partition found — connect via USB");
  while (true) delay(1000);
}

// --- Boot attempt tracking via RTC memory (survives reboot, not power loss) ---
#define BOOT_MAGIC 0xB007CA11

#define BOOT_STAGE_INIT    0
#define BOOT_STAGE_WIFI    1
#define BOOT_STAGE_MQTT    2
#define BOOT_STAGE_OTA_OK  3
#define BOOT_STAGE_I2S     4
#define BOOT_STAGE_VALID   0xFF  // fully validated

struct BootRecord {
  uint32_t magic;
  char firmware[16];
  uint8_t stage;
  uint8_t attempt;
};

RTC_DATA_ATTR BootRecord rtcBoot;     // current boot attempt
RTC_DATA_ATTR BootRecord rtcPrevBoot; // copy of last attempt before we overwrite it
RTC_DATA_ATTR bool rtcPrevValid;      // true if rtcPrevBoot has data worth reporting

void bootStage(uint8_t stage) {
  rtcBoot.stage = stage;
}

// Node ID derived from chip's unique ID (lower 4 bytes of MAC)
char NODE_ID[13];

// I2S pins
#define I2S_WS   25
#define I2S_SD   32
#define I2S_SCK  33
#define I2S_PORT I2S_NUM_0

// Audio config
#define SAMPLE_RATE     44100
#define SAMPLES_PER_READ 1024
#define PUBLISH_INTERVAL_MS 20  // 50Hz update rate

// Audio streaming config
#define STREAM_CHUNK_SIZE 4410    // 100ms chunks at 44.1kHz

int32_t i2s_read_buf[SAMPLES_PER_READ];
int16_t audioStreamBuffer[STREAM_CHUNK_SIZE];
int audioStreamIndex = 0;

// Remote-controllable gain
float audioGain = 10.0f;  // Default gain (20dB)

// Sleep mode — keeps WiFi+MQTT alive but stops I2S processing
bool sleeping = false;

// Hardware controls
#define PIN_BUTTON  34
#define PIN_POT     35
#define BUTTON_HOLD_MS     3000  // hold duration for hard reboot
#define BUTTON_DEBOUNCE_MS   50  // ignore transitions shorter than this
#define POT_CHANGE_THRESHOLD 0.5f

unsigned long buttonPressTime = 0;
unsigned long buttonLastChange = 0;
bool buttonWasPressed = false;
bool buttonStableState = HIGH;
volatile bool requestMqttReconnect = false;
float lastPublishedGain = -1.0f;

// Triple-press detection for recovery mode
uint8_t buttonPressCount = 0;
unsigned long buttonFirstPressTime = 0;
#define TRIPLE_PRESS_WINDOW_MS 2000

// Heartbeat interval (ms)
#define HEARTBEAT_INTERVAL_MS 30000
unsigned long lastHeartbeat = 0;

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
  char payload[512];
  int len = snprintf(payload, sizeof(payload),
    "{\"node\":\"%s\",\"firmware\":\"%s\",\"reset_reason\":%d,\"partition\":\"%s\",\"free_heap\":%u,\"ip\":\"%s\"",
    NODE_ID, FIRMWARE_VERSION, (int)esp_reset_reason(),
    running ? running->label : "unknown",
    ESP.getFreeHeap(),
    WiFi.localIP().toString().c_str());

  if (rtcPrevValid && rtcPrevBoot.magic == BOOT_MAGIC && rtcPrevBoot.stage != BOOT_STAGE_VALID) {
    const char* stageNames[] = {"init","wifi","mqtt","ota_ok","i2s"};
    const char* stageName = (rtcPrevBoot.stage < 5) ? stageNames[rtcPrevBoot.stage] : "unknown";
    len += snprintf(payload + len, sizeof(payload) - len,
      ",\"prev_failed_boot\":{\"firmware\":\"%s\",\"stage\":\"%s\",\"stage_id\":%d}",
      rtcPrevBoot.firmware, stageName, rtcPrevBoot.stage);
    rtcPrevValid = false;  // clear after reporting
  }

  snprintf(payload + len, sizeof(payload) - len, "}");
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

  // Handle sleep/wake — stops I2S processing but keeps WiFi+MQTT alive
  if (doc.containsKey("sleep") && doc["sleep"] == true && !sleeping) {
    sleeping = true;
    i2s_driver_uninstall(I2S_PORT);
    remoteLog("info", "Sleeping (I2S stopped, MQTT alive)");
    mqtt.loop();
  }
  if (doc.containsKey("wake") && doc["wake"] == true && sleeping) {
    sleeping = false;
    setupI2S();
    size_t discard;
    for (int i = 0; i < 4; i++) {
      i2s_read(I2S_PORT, i2s_read_buf, sizeof(i2s_read_buf), &discard, 100);
    }
    bootTime = millis();
    remoteLog("info", "Woke up (I2S restarted)");
    mqtt.loop();
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
  mqtt.setServer(MQTT_HOST, MQTT_PORT_VAL);
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
  webSocket.begin(WS_HOST, WS_PORT_VAL, "/ws/audio");
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
  pinMode(PIN_BOOT, INPUT_PULLUP);

  // Derive node ID from chip's full 6-byte fuse MAC (deterministic, no config needed)
  uint64_t mac = ESP.getEfuseMac();
  snprintf(NODE_ID, sizeof(NODE_ID), "%02x%02x%02x%02x%02x%02x",
    (uint8_t)(mac), (uint8_t)(mac >> 8), (uint8_t)(mac >> 16),
    (uint8_t)(mac >> 24), (uint8_t)(mac >> 32), (uint8_t)(mac >> 40));

  // Check BOOT button — if held at startup, go to recovery immediately
  if (digitalRead(PIN_BOOT) == LOW) {
    Serial.println("[IMPORTANT] BOOT button held — entering recovery mode");
    delay(100);
    bootIntoRecovery();
  }

  // Crash counter — if crashed too many times, enter recovery
  if (crashBootMagic != CRASH_MAGIC) {
    crashBootMagic = CRASH_MAGIC;
    crashBootCount = 0;
  }
  crashBootCount++;
  Serial.printf("[IMPORTANT] Boot attempt %u/%u\n", crashBootCount, CRASH_BOOT_LIMIT);
  if (crashBootCount > CRASH_BOOT_LIMIT) {
    crashBootCount = 0;
    bootIntoRecovery();
  }

  // Load credentials from NVS
  loadCredentials();

  Serial.println("\n\n[IMPORTANT] ========================================");
  Serial.print("[IMPORTANT] soundspy node starting - Firmware v");
  Serial.println(FIRMWARE_VERSION);
  Serial.print("[IMPORTANT] Node ID: ");
  Serial.println(NODE_ID);
  Serial.println("[IMPORTANT] ========================================\n");

  pinMode(PIN_BUTTON, INPUT);  // external 10k pull-up, active LOW
  // GPIO35 = ADC1 channel 7 — use legacy IDF driver (no conflict with analogRead)
  adc1_config_width(ADC_WIDTH_BIT_12);
  adc1_config_channel_atten(ADC1_CHANNEL_7, ADC_ATTEN_DB_12);  // full 0-3.3V range

  // Save previous boot record before overwriting
  if (rtcBoot.magic == BOOT_MAGIC && rtcBoot.stage != BOOT_STAGE_VALID) {
    rtcPrevBoot = rtcBoot;
    rtcPrevValid = true;
  } else {
    rtcPrevValid = false;
  }

  // Initialise new boot record
  rtcBoot.magic = BOOT_MAGIC;
  strncpy(rtcBoot.firmware, FIRMWARE_VERSION, sizeof(rtcBoot.firmware) - 1);
  rtcBoot.firmware[sizeof(rtcBoot.firmware) - 1] = '\0';
  rtcBoot.stage = BOOT_STAGE_INIT;
  rtcBoot.attempt = (rtcPrevValid ? rtcPrevBoot.attempt + 1 : 0);

  connectWiFi();
  bootStage(BOOT_STAGE_WIFI);

  connectMQTT();
  bootStage(BOOT_STAGE_MQTT);

  // Confirm OTA partition is valid — if this never runs, bootloader rolls back
  esp_ota_mark_app_valid_cancel_rollback();
  crashBootCount = 0;  // successful boot — reset crash counter
  bootStage(BOOT_STAGE_OTA_OK);

  publishBootReport();
  remoteLog("boot", "Stage 1 OK: WiFi + MQTT connected");
  mqtt.loop();

  configureBands();
  setupI2S();
  bootStage(BOOT_STAGE_I2S);
  connectWebSocket();
  lastPublish = millis();
  bootTime = millis();

  // All stages passed — mark as fully valid
  bootStage(BOOT_STAGE_VALID);
  // Start hardware control task on Core 0 (audio loop runs on Core 1)
  xTaskCreatePinnedToCore(hwControlTask, "hwControl", 8192, NULL, 1, NULL, 0);

  remoteLog("boot", "Stage 2 OK: I2S + WebSocket initialized");
  mqtt.loop();
}

void sendHeartbeat() {
  if (millis() - lastHeartbeat < HEARTBEAT_INTERVAL_MS) return;
  lastHeartbeat = millis();
  char payload[128];
  snprintf(payload, sizeof(payload),
    "{\"node\":\"%s\",\"uptime_ms\":%lu,\"sleeping\":%s,\"free_heap\":%u}",
    NODE_ID, millis(), sleeping ? "true" : "false", ESP.getFreeHeap());
  String topic = String("soundspy/") + NODE_ID + "/heartbeat";
  mqtt.publish(topic.c_str(), payload);
}

void handleButton() {
  bool reading = (digitalRead(PIN_BUTTON) == LOW);
  unsigned long now = millis();

  // Debounce: only accept state change after it's stable for BUTTON_DEBOUNCE_MS
  if (reading != buttonStableState) {
    if (now - buttonLastChange >= BUTTON_DEBOUNCE_MS) {
      buttonStableState = reading;
      buttonLastChange = now;

      if (buttonStableState == HIGH && buttonWasPressed) {
        // Released — determine click vs hold
        unsigned long held = now - buttonPressTime;
        buttonWasPressed = false;
        if (held >= BUTTON_HOLD_MS) {
          remoteLog("info", "Button held — hard reboot");
          delay(100);
          ESP.restart();
        } else {
          // Triple-press check
          unsigned long now2 = millis();
          if (buttonPressCount == 0 || (now2 - buttonFirstPressTime) > TRIPLE_PRESS_WINDOW_MS) {
            buttonPressCount = 1;
            buttonFirstPressTime = now2;
          } else {
            buttonPressCount++;
          }
          if (buttonPressCount >= 3) {
            buttonPressCount = 0;
            remoteLog("info", "Triple-press — entering recovery mode");
            delay(200);
            bootIntoRecovery();
          } else {
            remoteLog("info", "Button clicked — requesting MQTT reconnect");
            requestMqttReconnect = true;
          }
        }
      } else if (buttonStableState == LOW) {
        buttonPressTime = now;
        buttonWasPressed = true;
      }
    }
  } else {
    buttonLastChange = now;
    // Still held — trigger reboot immediately once threshold crossed
    if (buttonWasPressed && buttonStableState == LOW && (now - buttonPressTime >= BUTTON_HOLD_MS)) {
      remoteLog("info", "Button held — hard reboot");
      delay(100);
      ESP.restart();
    }
  }
}

void handlePot() {
  // Called from Core 0 task — runs independently of audio loop

  // Average 16 reads to reduce ADC noise
  int sum = 0;
  for (int i = 0; i < 16; i++) sum += adc1_get_raw(ADC1_CHANNEL_7);
  int raw = sum / 16;

  // Map 0-4095 → 0.0-10.0 gain
  float gain = (raw / 4095.0f) * 10.0f;

  // Apply immediately to audio
  audioGain = gain;

  // Only publish when change is significant (avoids flooding at 50Hz)
  if (lastPublishedGain < 0 || fabsf(gain - lastPublishedGain) >= POT_CHANGE_THRESHOLD) {
    lastPublishedGain = gain;

    char payload[128];
    snprintf(payload, sizeof(payload),
      "{\"node\":\"%s\",\"gain\":%.2f}", NODE_ID, gain);
    mqtt.publish((String("soundspy/") + NODE_ID + "/gain").c_str(), payload);

    char logMsg[64];
    snprintf(logMsg, sizeof(logMsg), "Knob gain: %.1fx (%.0f%%)", gain, gain * 10.0f);
    remoteLog("info", logMsg);
  }
}

// Core 0 task: handles hardware controls (button + pot) without blocking audio loop
void hwControlTask(void* pvParameters) {
  for (;;) {
    handleButton();
    handlePot();
    vTaskDelay(pdMS_TO_TICKS(20));  // 50Hz poll rate, non-blocking
  }
}

void loop() {
  if (requestMqttReconnect) {
    requestMqttReconnect = false;
    mqtt.disconnect();
    delay(100);
    connectMQTT();
  }
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();
  sendHeartbeat();

  if (sleeping) {
    delay(100);
    return;
  }

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
