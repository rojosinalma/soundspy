// soundspy — sound level node on esp32-base (ESP32 DevKit + ICS-43434/INMP441 I2S mic).
//
// Reporter only: meters 6 bands + overall level and publishes them on MQTT
// (<prefix>/<chip_id>/data every publish_ms), serves raw PCM on a TCP port for the
// dashboard's live audio, and takes settings over MQTT cmd / POST /api/audio.
// Everything else (UI, history, alerts) is the dashboard service.
#include <Esp32Base.h>
#include "audio.h"

#define APP_VERSION "2.1.1"

static uint32_t s_seq = 0;
static uint32_t s_lastPublish = 0;
static String   s_dataTopic;

static void sendJson(int code, JsonDocument& doc) {
  String out;
  serializeJson(doc, out);
  Base.http().sendHeader("Cache-Control", "no-store");
  Base.http().send(code, "application/json", out);
}

static void audioJson(JsonDocument& doc) {
  Audio::settings().toJson(doc["settings"].to<JsonObject>());
  Audio::statusJson(doc["status"].to<JsonObject>());
}

static void handleGet() {
  JsonDocument doc;
  doc["ok"] = true;
  doc["message"] = "audio";
  audioJson(doc);
  sendJson(200, doc);
}

static void handlePost() {
  JsonDocument body, doc;
  if (deserializeJson(body, Base.http().arg("plain")) || !body.is<JsonObject>()) {
    doc["ok"] = false;
    doc["message"] = "expected a JSON object";
    return sendJson(400, doc);
  }
  String err = Audio::settings().apply(body.as<JsonObjectConst>());
  if (err.length()) {
    doc["ok"] = false;
    doc["message"] = err;
    return sendJson(422, doc);
  }
  BaseMqtt::publishStatus();
  doc["ok"] = true;
  doc["message"] = "Settings saved";
  audioJson(doc);
  sendJson(200, doc);
}

// {"cmd":"gain","value":5} | {"cmd":"sleep"} | {"cmd":"wake"} | {"cmd":"set","settings":{...}}
static void onCommand(const String& leaf, const String& payload) {
  if (leaf != "cmd") return;
  JsonDocument d;
  if (deserializeJson(d, payload)) return;
  const char* cmd = d["cmd"] | "";

  JsonDocument patch;
  if (!strcmp(cmd, "gain")) {
    if (!d["value"].is<float>()) return Base.warn("cmd gain: missing numeric value");
    patch["gain"] = d["value"];
  } else if (!strcmp(cmd, "sleep")) {
    patch["awake"] = false;
  } else if (!strcmp(cmd, "wake")) {
    patch["awake"] = true;
  } else if (!strcmp(cmd, "set") && d["settings"].is<JsonObjectConst>()) {
    patch.set(d["settings"]);
  } else {
    return;
  }
  String err = Audio::settings().apply(patch.as<JsonObjectConst>());
  if (err.length()) return Base.warn("cmd %s rejected: %s", cmd, err.c_str());
  Base.log("cmd %s applied", cmd);
  BaseMqtt::publishStatus();
}

static void publishLevels() {
  Audio::Levels l;
  if (!Audio::takeLevels(l)) return;
  if (!Base.mqtt().connected()) return;

  char buf[256];
  int n = snprintf(buf, sizeof(buf), "{\"seq\":%u,\"ts\":%u,\"samples\":%u,\"overall_dbfs\":%.1f,\"bands\":{",
                   ++s_seq, millis(), l.samples, l.overallDb);
  for (uint8_t b = 0; b < Audio::BAND_COUNT && n < (int)sizeof(buf); b++)
    n += snprintf(buf + n, sizeof(buf) - n, "%s\"%s\":%.1f", b ? "," : "", Audio::BAND_NAMES[b], l.bandDb[b]);
  if (n < (int)sizeof(buf)) n += snprintf(buf + n, sizeof(buf) - n, "}}");
  Base.mqtt().publish(s_dataTopic.c_str(), buf);
}

void setup() {
  Audio::settings().load();
  Base.begin("soundspy", APP_VERSION);
  s_dataTopic = Base.topic("data");

  Base.onStatus([](JsonObject o) { Audio::statusJson(o); });
  Base.onMessage(onCommand);
  Base.on("/api/audio", HTTP_GET, handleGet);
  Base.on("/api/audio", HTTP_POST, handlePost);
  Base.http().on("/", HTTP_GET, []() {
    Base.http().send(200, "text/plain", "soundspy " APP_VERSION " — system portal at /sys, settings at /api/audio\n");
  });

  Audio::begin();
}

void loop() {
  Base.loop();
  uint32_t now = millis();
  if (now - s_lastPublish >= Audio::settings().publishMs) {
    s_lastPublish = now;
    publishLevels();
  }
  delay(1);
}
