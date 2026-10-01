// Audio capture, 6-band metering and the raw PCM stream server for soundspy.
#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

namespace Audio {

constexpr uint8_t  BAND_COUNT          = 6;
constexpr uint32_t SAMPLE_RATE         = 44100;
constexpr float    GAIN_MIN            = 0.0f;
constexpr float    GAIN_MAX            = 10.0f;
constexpr float    GAIN_DEFAULT        = 10.0f;   // 20 dB, matches the legacy nodes
constexpr uint16_t PUBLISH_MS_MIN      = 20;
constexpr uint16_t PUBLISH_MS_MAX      = 5000;
constexpr uint16_t PUBLISH_MS_DEFAULT  = 20;
constexpr uint16_t STREAM_PORT_DEFAULT = 8181;

extern const char* const BAND_NAMES[BAND_COUNT];

struct Settings {
  float    gain       = GAIN_DEFAULT;        // linear, applied before metering and streaming
  uint16_t publishMs  = PUBLISH_MS_DEFAULT;  // interval of the MQTT "data" message
  uint16_t streamPort = STREAM_PORT_DEFAULT; // raw PCM TCP server; 0 = off. Takes effect on reboot
  bool     awake      = true;                // false = soft sleep: I2S off, status keeps going
  uint8_t  slot       = 0;                   // I2S slot the mic drives: 0 = left (L/R pin low), 1 = right

  void   load();
  void   save() const;
  void   toJson(JsonObject o) const;
  String apply(JsonObjectConst in);  // validates, assigns and saves; "" on success, else the error
};
Settings& settings();

struct Levels {
  float    overallDb;
  float    bandDb[BAND_COUNT];
  uint32_t samples;
};

void begin();
bool takeLevels(Levels& out);  // levels since the previous call; false when nothing was captured
void levelsJson(const Levels& l, JsonObject o);
void statusJson(JsonObject o);

}  // namespace Audio
