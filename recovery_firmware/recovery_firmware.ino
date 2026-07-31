// soundspy recovery firmware
// Lives in the factory partition — never overwritten by OTA.
// Triggered by: holding BOOT (GPIO0) at reset, or triple-pressing user button (GPIO34) at runtime.
//
// Capabilities:
//   - Reads WiFi + MQTT config from NVS
//   - If credentials missing or WiFi fails: starts AP (soundspy-recovery / soundspy123)
//   - Serves HTTP portal at 192.168.4.1 (AP) or device IP (STA) for:
//     * OTA firmware upload
//     * WiFi + MQTT credential update
//   - Publishes soundspy/<id>/recovery over MQTT when in STA mode

#include <WiFi.h>
#include <WebServer.h>
#include <HTTPUpdateServer.h>
#include <HTTPUpdate.h>
#include <Preferences.h>
#include <esp_ota_ops.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

#define RECOVERY_VERSION "1.0.0"
#define AP_SSID          "soundspy-recovery"
#define AP_PASS          "soundspy123"
#define PIN_BOOT         0   // built-in BOOT button (active LOW, pull-up)
#define PIN_LED          2   // built-in LED (active HIGH on most NodeMCU boards)

char NODE_ID[13];

Preferences prefs;
WebServer server(80);
HTTPUpdateServer updater;
WiFiClient mqttWifiClient;
PubSubClient mqtt(mqttWifiClient);

bool staMode = false;
String wifiSsid, wifiPass, mqttHost, mqttPort, wsHost, wsPort;

void deriveNodeId() {
  uint64_t mac = ESP.getEfuseMac();
  snprintf(NODE_ID, sizeof(NODE_ID), "%02x%02x%02x%02x%02x%02x",
    (uint8_t)(mac), (uint8_t)(mac >> 8), (uint8_t)(mac >> 16),
    (uint8_t)(mac >> 24), (uint8_t)(mac >> 32), (uint8_t)(mac >> 40));
}

void loadCredentials() {
  prefs.begin("soundspy", true);
  wifiSsid = prefs.getString("wifi_ssid", "");
  wifiPass = prefs.getString("wifi_pass", "");
  mqttHost = prefs.getString("mqtt_host", "");
  mqttPort = prefs.getString("mqtt_port", "1883");
  wsHost   = prefs.getString("ws_host", "");
  wsPort   = prefs.getString("ws_port", "8091");
  prefs.end();
}

void saveCredentials(const String& ssid, const String& pass,
                     const String& mHost, const String& mPort,
                     const String& wHost, const String& wPort) {
  prefs.begin("soundspy", false);
  prefs.putString("wifi_ssid", ssid);
  prefs.putString("wifi_pass", pass);
  prefs.putString("mqtt_host", mHost);
  prefs.putString("mqtt_port", mPort);
  prefs.putString("ws_host",   wHost);
  prefs.putString("ws_port",   wPort);
  prefs.end();
}

bool connectWiFiSTA() {
  if (wifiSsid.isEmpty()) return false;
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  Serial.print("[recovery] Connecting to WiFi");
  for (int i = 0; i < 20; i++) {
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println(" connected: " + WiFi.localIP().toString());
      return true;
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println(" failed");
  return false;
}

void startAP() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.println("[recovery] AP started: " + String(AP_SSID) + " / " + String(AP_PASS));
  Serial.println("[recovery] Portal: http://192.168.4.1");
}

void blinkLed(int times, int ms = 150) {
  for (int i = 0; i < times; i++) {
    digitalWrite(PIN_LED, HIGH);
    delay(ms);
    digitalWrite(PIN_LED, LOW);
    delay(ms);
  }
}

// --- HTTP portal ---

const char* PORTAL_HTML = R"(<!DOCTYPE html>
<html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
<title>soundspy recovery</title>
<style>
body{font-family:monospace;background:#0a0f0c;color:#8ec9a0;padding:20px;max-width:480px;margin:0 auto}
h1{color:#44dd66;text-shadow:0 0 8px #44dd66}
input{background:#080e0a;border:1px solid #2a4a34;color:#8ec9a0;padding:6px 10px;width:100%;box-sizing:border-box;margin:4px 0 12px;font-family:monospace}
label{color:#4a7a5a;font-size:0.85em}
button{background:#1a3a28;border:1px solid #44dd66;color:#44dd66;padding:8px 20px;cursor:pointer;font-family:monospace;margin-top:8px}
button:hover{background:#2a5a38}
.section{background:#0f1a14;border:1px solid #1a2e24;padding:16px;margin-bottom:16px;border-radius:6px}
h2{font-size:1em;color:#44dd66;margin:0 0 12px}
.info{color:#2a6e3f;font-size:0.8em;margin-bottom:16px}
</style></head>
<body>
<h1>soundspy recovery</h1>
<p class='info'>Node: %NODE_ID% &nbsp;|&nbsp; v%VERSION%</p>
<div class='section'>
  <h2>OTA Firmware Upload</h2>
  <form method='POST' action='/update' enctype='multipart/form-data'>
    <label>Firmware .bin file</label>
    <input type='file' name='firmware' accept='.bin'>
    <button type='submit'>Flash firmware</button>
  </form>
</div>
<div class='section'>
  <h2>Network Configuration</h2>
  <form method='POST' action='/save'>
    <label>WiFi SSID</label><input name='ssid' value='%SSID%'>
    <label>WiFi Password</label><input name='pass' type='password' placeholder='(unchanged if empty)'>
    <label>MQTT Host</label><input name='mqtt_host' value='%MQTT_HOST%'>
    <label>MQTT Port</label><input name='mqtt_port' value='%MQTT_PORT%'>
    <label>WebSocket Host</label><input name='ws_host' value='%WS_HOST%'>
    <label>WebSocket Port</label><input name='ws_port' value='%WS_PORT%'>
    <button type='submit'>Save &amp; Reboot</button>
  </form>
</div>
<div class='section'>
  <h2>Boot Main Firmware</h2>
  <p class='info'>Reboots into the latest valid OTA partition.</p>
  <form method='POST' action='/boot'>
    <button type='submit'>Boot main firmware</button>
  </form>
</div>
</body></html>)";

void handleRoot() {
  String html = String(PORTAL_HTML);
  html.replace("%NODE_ID%", NODE_ID);
  html.replace("%VERSION%", RECOVERY_VERSION);
  html.replace("%SSID%", wifiSsid);
  html.replace("%MQTT_HOST%", mqttHost);
  html.replace("%MQTT_PORT%", mqttPort);
  html.replace("%WS_HOST%", wsHost);
  html.replace("%WS_PORT%", wsPort);
  server.send(200, "text/html", html);
}

void handleSave() {
  String ssid     = server.arg("ssid");
  String pass     = server.arg("pass");
  String mHost    = server.arg("mqtt_host");
  String mPort    = server.arg("mqtt_port");
  String wHost    = server.arg("ws_host");
  String wPort    = server.arg("ws_port");

  if (pass.isEmpty()) pass = wifiPass;  // keep existing if not changed
  saveCredentials(ssid, pass, mHost, mPort, wHost, wPort);

  server.send(200, "text/html",
    "<html><body style='font-family:monospace;background:#0a0f0c;color:#44dd66;padding:20px'>"
    "<h2>Saved. Rebooting...</h2></body></html>");
  delay(1500);
  ESP.restart();
}

void handleBoot() {
  // Find the last valid OTA partition and set it as next boot
  const esp_partition_t* ota0 = esp_partition_find_first(ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_0, NULL);
  const esp_partition_t* ota1 = esp_partition_find_first(ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_1, NULL);
  esp_ota_img_states_t state0 = ESP_OTA_IMG_UNDEFINED, state1 = ESP_OTA_IMG_UNDEFINED;
  if (ota0) esp_ota_get_state_partition(ota0, &state0);
  if (ota1) esp_ota_get_state_partition(ota1, &state1);

  const esp_partition_t* target = nullptr;
  if (state0 == ESP_OTA_IMG_VALID) target = ota0;
  else if (state1 == ESP_OTA_IMG_VALID) target = ota1;
  else if (ota0) target = ota0;  // fallback

  if (target) {
    esp_ota_set_boot_partition(target);
    server.send(200, "text/html",
      "<html><body style='font-family:monospace;background:#0a0f0c;color:#44dd66;padding:20px'>"
      "<h2>Booting main firmware...</h2></body></html>");
    delay(1000);
    ESP.restart();
  } else {
    server.send(500, "text/plain", "No valid OTA partition found");
  }
}

void performOTA(const char* url) {
  Serial.println("[recovery] OTA update requested: " + String(url));
  WiFiClient client;
  t_httpUpdate_return ret = httpUpdate.update(client, url);
  if (ret == HTTP_UPDATE_OK) {
    Serial.println("[recovery] OTA success, rebooting");
    esp_restart();
  } else {
    Serial.println("[recovery] OTA failed: " + httpUpdate.getLastErrorString());
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, payload, length)) return;
  if (doc.containsKey("ota_url")) {
    performOTA(doc["ota_url"]);
  }
}

void connectMQTT() {
  if (mqttHost.isEmpty()) return;
  mqtt.setServer(mqttHost.c_str(), mqttPort.toInt());
  mqtt.setCallback(mqttCallback);
  String clientId = String("recovery-") + NODE_ID;
  if (mqtt.connect(clientId.c_str())) {
    String controlTopic = String("soundspy/") + NODE_ID + "/control";
    mqtt.subscribe(controlTopic.c_str());
    Serial.println("[recovery] MQTT connected, subscribed to " + controlTopic);
  }
}

void setupServer() {
  updater.setup(&server, "/update");
  server.on("/", HTTP_GET, handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  server.on("/boot", HTTP_POST, handleBoot);
  server.begin();
  Serial.println("[recovery] HTTP server started");
}

void publishRecoveryStatus() {
  // Lightweight MQTT publish — no PubSubClient, raw TCP
  if (!staMode || mqttHost.isEmpty()) return;
  WiFiClient client;
  if (!client.connect(mqttHost.c_str(), mqttPort.toInt())) return;

  String topic = String("soundspy/") + NODE_ID + "/recovery";
  String payload = "{\"node\":\"" + String(NODE_ID) + "\",\"mode\":\"recovery\",\"version\":\"" + RECOVERY_VERSION + "\",\"ip\":\"" + WiFi.localIP().toString() + "\"}";

  // Minimal MQTT CONNECT + PUBLISH (no library needed)
  uint8_t clientId[] = {'r','e','c','v'};
  uint16_t topicLen = topic.length();
  uint16_t payloadLen = payload.length();
  uint16_t remainLen = 2 + 4 + 2 + 1 + 2 + 2 + topicLen + payloadLen; // rough

  // Just send a raw connect + publish — enough for monitoring
  String mqttConnect = "";
  client.write(0x10); // CONNECT
  client.write(16 + 4); // remaining length
  client.write((uint8_t*)"\x00\x04MQTT\x04\x02\x00\x3c", 9); // protocol
  client.write((uint8_t*)"\x00\x04recv", 6); // client ID
  delay(200);
  if (client.available()) {
    // got CONNACK — now publish
    client.print((char)0x31); // PUBLISH, no QoS
    uint8_t remLen = 2 + topicLen + payloadLen;
    client.write(remLen);
    client.write((uint8_t)(topicLen >> 8));
    client.write((uint8_t)(topicLen & 0xFF));
    client.print(topic);
    client.print(payload);
    delay(100);
  }
  client.stop();
  Serial.println("[recovery] Published recovery status to MQTT");
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_BOOT, INPUT_PULLUP);

  deriveNodeId();

  Serial.println("\n\n[recovery] ========================================");
  Serial.println("[recovery] soundspy RECOVERY firmware v" + String(RECOVERY_VERSION));
  Serial.println("[recovery] Node ID: " + String(NODE_ID));
  Serial.println("[recovery] ========================================\n");

  // 3 fast blinks to signal recovery mode
  blinkLed(3, 100);

  loadCredentials();
  staMode = connectWiFiSTA();
  if (!staMode) startAP();

  setupServer();
  if (staMode) connectMQTT();
  publishRecoveryStatus();

  // Slow blink to indicate portal is running
  Serial.println("[recovery] Portal ready — waiting for connections");
}

void loop() {
  server.handleClient();
  if (staMode) {
    if (!mqtt.connected()) connectMQTT();
    mqtt.loop();
  }
  // Slow heartbeat blink
  static unsigned long lastBlink = 0;
  if (millis() - lastBlink > 2000) {
    lastBlink = millis();
    blinkLed(1, 50);
  }
}
