// I2S capture (ICS-43434 / INMP441, left slot), per-band RMS metering and the raw PCM stream.
//
// The capture task owns the I2S channel and runs the DSP; it never touches MQTT or HTTP.
// loop() takes a snapshot of the accumulated energy with takeLevels() and publishes it.
// The stream task serves one TCP client with s16le mono PCM at SAMPLE_RATE (gain applied);
// the dashboard service is that client. Nothing is buffered unless a client is connected.
#include "audio.h"
#include <Esp32Base.h>
#include <Preferences.h>
#include <WiFi.h>
#include <driver/i2s_std.h>
#include <math.h>

namespace Audio {

const char* const BAND_NAMES[BAND_COUNT] = { "sub_bass", "bass", "low_mid", "mid", "high_mid", "high" };

namespace {

constexpr gpio_num_t PIN_SCK = GPIO_NUM_33;
constexpr gpio_num_t PIN_WS  = GPIO_NUM_25;
constexpr gpio_num_t PIN_SD  = GPIO_NUM_32;

// Mono capture of the slot the mic drives. Which hardware slot that is (left/right) is a runtime
// setting, because on the ESP32 the mono slot select has swapped meanings between driver generations.
constexpr uint32_t CHUNK_WORDS       = 1024;   // samples per i2s read (~23 ms)
constexpr uint32_t DMA_DESC_NUM      = 4;      // ~93 ms of ring (16 KB of DMA RAM); the capture task drains it
                                               // every 23 ms, and the heap is needed for the TLS fleet check-in
constexpr uint32_t DMA_FRAME_NUM     = 1023;   // 4092 bytes per buffer, the driver's maximum
constexpr uint32_t READ_TIMEOUT_MS   = 1000;
constexpr int      I2S_24BIT_SHIFT   = 8;      // 24-bit sample, MSB-aligned in the 32-bit slot
constexpr float    I2S_FULL_SCALE    = 8388608.0f;  // 2^23
constexpr float    PCM16_SCALE       = 32767.0f;
constexpr float    DBFS_EPSILON      = 1e-9f;
constexpr uint8_t  FILTER_SECTIONS   = 2;      // two identical bandpass biquads per band

// I2S watchdog: a dead bus reads as digital silence far below any real noise floor.
constexpr float    LOCKUP_RMS        = 3.2e-9f;  // -170 dBFS
constexpr uint16_t LOCKUP_CHUNKS     = 150;      // ~3.5 s of silence before a reinit
constexpr uint32_t STARTUP_GRACE_MS  = 5000;
constexpr uint8_t  MAX_REINITS       = 3;
constexpr uint32_t REINIT_DELAY_MS   = 200;
constexpr uint8_t  DISCARD_READS     = 4;

constexpr uint32_t RING_SAMPLES      = 8192;   // power of two, ~185 ms of PCM; allocated only while a client streams
constexpr uint32_t STREAM_CHUNK      = 2205;   // 50 ms per TCP write
constexpr uint32_t CAPTURE_STACK     = 6144;
constexpr uint32_t STREAM_STACK      = 6144;
constexpr uint32_t SLEEP_POLL_MS     = 100;

constexpr const char* NVS_NS = "sspy";

struct BandDef { float fLow; float fHigh; };
const BandDef BANDS[BAND_COUNT] = {
  { 50, 120 }, { 120, 250 }, { 250, 500 }, { 500, 2000 }, { 2000, 6000 }, { 6000, 20000 },
};

// Transposed direct form II. RBJ constant-0 dB-peak bandpass, f0 = sqrt(fl*fh), Q = f0/(fh-fl).
struct Biquad {
  float b0 = 0, b2 = 0, a1 = 0, a2 = 0;  // b1 is always 0 for this bandpass
  float z1 = 0, z2 = 0;

  void design(double fLow, double fHigh, double fs) {
    double f0 = sqrt(fLow * fHigh), q = f0 / (fHigh - fLow);
    double w0 = 2.0 * M_PI * f0 / fs, alpha = sin(w0) / (2.0 * q), norm = 1.0 + alpha;
    b0 = alpha / norm;
    b2 = -b0;
    a1 = -2.0 * cos(w0) / norm;
    a2 = (1.0 - alpha) / norm;
    z1 = z2 = 0;
  }
  inline float process(float in) {
    float out = b0 * in + z1;
    z1 = z2 - a1 * out;
    z2 = b2 * in - a2 * out;
    return out;
  }
};

Settings s_settings;
Biquad   s_filters[BAND_COUNT][FILTER_SECTIONS];

portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
double   s_sumSq[BAND_COUNT + 1];  // [0..5] bands, [6] overall
uint32_t s_count = 0;

i2s_chan_handle_t s_rx = nullptr;
volatile bool s_restart = false;
float    s_slotDb = -180.0f;                   // last chunk, unweighted level of the captured slot
uint32_t s_nonzeroWords = 0;                   // last chunk, raw words != 0 (0 = nothing on SD)
uint32_t s_rawSample[2] = { 0, 0 };           // last chunk, first raw word of each slot
uint32_t s_graceUntil = 0;
uint16_t s_lockups = 0;
uint8_t  s_reinits = 0;
uint32_t s_totalReinits = 0;
int32_t* s_raw = nullptr;

int16_t* volatile s_ring = nullptr;  // owned by the stream task; the capture task only writes while s_streaming
volatile uint32_t s_head = 0, s_tail = 0;
volatile bool s_streaming = false;
String   s_streamClient;

// The ring lives only while a client is connected, so an idle node keeps ~32 KB free for TLS.
bool ringAcquire() {
  if (!s_ring) s_ring = (int16_t*)malloc(RING_SAMPLES * sizeof(int16_t));
  if (!s_ring) return false;
  s_head = s_tail = 0;
  return true;
}

void ringRelease() {
  s_streaming = false;
  delay(30);  // let a capture chunk in flight finish before the buffer goes away
  free(s_ring);
  s_ring = nullptr;
}

bool i2sStart() {
  i2s_chan_config_t chan = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  chan.dma_desc_num = DMA_DESC_NUM;
  chan.dma_frame_num = DMA_FRAME_NUM;
  if (i2s_new_channel(&chan, nullptr, &s_rx) != ESP_OK) return false;

  i2s_std_config_t cfg = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED, .bclk = PIN_SCK, .ws = PIN_WS, .dout = I2S_GPIO_UNUSED, .din = PIN_SD,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
    },
  };
  cfg.slot_cfg.slot_mask = s_settings.slot ? I2S_STD_SLOT_RIGHT : I2S_STD_SLOT_LEFT;
  if (i2s_channel_init_std_mode(s_rx, &cfg) != ESP_OK || i2s_channel_enable(s_rx) != ESP_OK) {
    i2s_del_channel(s_rx);
    s_rx = nullptr;
    return false;
  }
  size_t got;
  for (uint8_t i = 0; i < DISCARD_READS; i++) i2s_channel_read(s_rx, s_raw, CHUNK_WORDS * sizeof(int32_t), &got, 100);
  for (auto& band : s_filters) for (auto& f : band) f.z1 = f.z2 = 0;
  s_graceUntil = millis() + STARTUP_GRACE_MS;
  s_lockups = 0;
  return true;
}

void i2sStop() {
  if (!s_rx) return;
  i2s_channel_disable(s_rx);
  i2s_del_channel(s_rx);
  s_rx = nullptr;
}

void noteLockup() {
  if ((int32_t)(millis() - s_graceUntil) < 0) return;
  if (++s_lockups < LOCKUP_CHUNKS) return;
  s_lockups = 0;
  if (s_reinits >= MAX_REINITS) return;  // stay quiet rather than reboot-loop; status shows the count
  s_reinits++;
  s_totalReinits++;
  Base.warn("audio: I2S silent for %u chunks, reinitialising (%u/%u)", LOCKUP_CHUNKS, s_reinits, MAX_REINITS);
  i2sStop();
  delay(REINIT_DELAY_MS);
  if (!i2sStart()) Base.error("audio: I2S reinit failed");
}

inline float toFloat(int32_t word, float gain) {
  return constrain((float)(word >> I2S_24BIT_SHIFT) / I2S_FULL_SCALE * gain, -1.0f, 1.0f);
}

void processChunk(const int32_t* raw, uint32_t n) {
  const float gain = s_settings.gain;
  const bool stream = s_streaming;
  double sum[BAND_COUNT + 1] = {};
  uint32_t nonzero = 0;

  for (uint32_t i = 0; i < n; i++) {
    nonzero += raw[i] != 0;
    float s = toFloat(raw[i], gain);
    sum[BAND_COUNT] += s * s;
    for (uint8_t b = 0; b < BAND_COUNT; b++) {
      float y = s_filters[b][1].process(s_filters[b][0].process(s));
      sum[b] += y * y;
    }
    if (stream && s_ring && s_head - s_tail < RING_SAMPLES) {
      s_ring[s_head & (RING_SAMPLES - 1)] = (int16_t)(s * PCM16_SCALE);
      s_head++;
    }
  }

  taskENTER_CRITICAL(&s_mux);
  for (uint8_t b = 0; b <= BAND_COUNT; b++) s_sumSq[b] += sum[b];
  s_count += n;
  taskEXIT_CRITICAL(&s_mux);

  s_nonzeroWords = nonzero;
  s_rawSample[0] = (uint32_t)raw[0];
  s_rawSample[1] = (uint32_t)raw[1];
  float rms = sqrtf((float)(sum[BAND_COUNT] / n));
  s_slotDb = 20.0f * log10f(rms + DBFS_EPSILON);
  if (rms < LOCKUP_RMS) {
    noteLockup();
  } else {
    s_lockups = 0;
    s_reinits = 0;
  }
}

void captureTask(void*) {
  for (;;) {
    if (!s_settings.awake) {
      if (s_rx) {
        i2sStop();
        Base.log("audio: sleeping, I2S off");
      }
      delay(SLEEP_POLL_MS);
      continue;
    }
    if (s_restart) {
      s_restart = false;
      s_reinits = 0;
      i2sStop();
      Base.log("audio: restarting I2S (slot %u)", s_settings.slot);
    }
    if (!s_rx) {
      if (!i2sStart()) {
        Base.error("audio: I2S init failed, retrying");
        delay(1000);
        continue;
      }
      Base.log("audio: capturing %u Hz, gain %.1f", SAMPLE_RATE, s_settings.gain);
    }
    size_t got = 0;
    esp_err_t err = i2s_channel_read(s_rx, s_raw, CHUNK_WORDS * sizeof(int32_t), &got, READ_TIMEOUT_MS);
    if (err != ESP_OK || got < sizeof(int32_t)) {
      noteLockup();
      continue;
    }
    processChunk(s_raw, got / sizeof(int32_t));
  }
}

void streamTask(void*) {
  WiFiServer server(s_settings.streamPort);
  server.begin();
  WiFiClient client;
  static int16_t chunk[STREAM_CHUNK];

  for (;;) {
    WiFiClient incoming = server.accept();
    if (incoming) {
      if (client) {
        client.stop();
        Base.log("stream: replacing client %s", s_streamClient.c_str());
      }
      client = incoming;
      client.setNoDelay(true);
      s_streamClient = client.remoteIP().toString();
      if (!ringAcquire()) {
        Base.error("stream: no memory for the PCM buffer, refusing %s", s_streamClient.c_str());
        client.stop();
        client = WiFiClient();
        continue;
      }
      s_streaming = true;
      client.printf("{\"format\":\"s16le\",\"rate\":%u,\"channels\":1,\"chip_id\":\"%s\"}\n", SAMPLE_RATE, baseChipId().c_str());
      Base.log("stream: client %s connected", s_streamClient.c_str());
    }

    if (client && client.connected()) {
      if (s_head - s_tail >= STREAM_CHUNK) {
        for (uint32_t i = 0; i < STREAM_CHUNK; i++) chunk[i] = s_ring[(s_tail + i) & (RING_SAMPLES - 1)];
        s_tail += STREAM_CHUNK;
        if (client.write((const uint8_t*)chunk, sizeof(chunk)) != sizeof(chunk)) client.stop();
      } else {
        delay(5);
      }
    } else {
      if (client) {
        client.stop();
        client = WiFiClient();
        ringRelease();
        Base.log("stream: client %s disconnected", s_streamClient.c_str());
        s_streamClient = "";
      }
      delay(20);
    }
  }
}

}  // namespace

Settings& settings() { return s_settings; }

void Settings::load() {
  Preferences p;
  p.begin(NVS_NS, true);
  gain       = p.getFloat("gain", gain);
  publishMs  = p.getUShort("pub_ms", publishMs);
  streamPort = p.getUShort("stream_port", streamPort);
  awake      = p.getBool("awake", awake);
  slot       = p.getUChar("slot", slot) & 1;
  p.end();
}

void Settings::save() const {
  Preferences p;
  p.begin(NVS_NS, false);
  p.putFloat("gain", gain);
  p.putUShort("pub_ms", publishMs);
  p.putUShort("stream_port", streamPort);
  p.putBool("awake", awake);
  p.putUChar("slot", slot);
  p.end();
}

void Settings::toJson(JsonObject o) const {
  o["gain"]        = gain;
  o["publish_ms"]  = publishMs;
  o["stream_port"] = streamPort;
  o["awake"]       = awake;
  o["slot"]        = slot ? "right" : "left";
}

String Settings::apply(JsonObjectConst in) {
  Settings n = *this;
  if (in["gain"].is<float>()) {
    float g = in["gain"];
    if (g < GAIN_MIN || g > GAIN_MAX) return String("gain must be between ") + GAIN_MIN + " and " + GAIN_MAX;
    n.gain = g;
  }
  if (in["publish_ms"].is<int>()) {
    int ms = in["publish_ms"];
    if (ms < PUBLISH_MS_MIN || ms > PUBLISH_MS_MAX) return String("publish_ms must be between ") + PUBLISH_MS_MIN + " and " + PUBLISH_MS_MAX;
    n.publishMs = ms;
  }
  if (in["stream_port"].is<int>()) {
    int port = in["stream_port"];
    if (port != 0 && (port < 1024 || port > 65535)) return "stream_port must be 0 (off) or 1024-65535";
    n.streamPort = port;
  }
  if (in["awake"].is<bool>()) n.awake = in["awake"];
  if (in["slot"].is<const char*>()) {
    String v = in["slot"].as<const char*>();
    if (v != "left" && v != "right") return "slot must be left or right";
    n.slot = v == "right";
  }
  if (n.slot != slot) s_restart = true;
  *this = n;
  save();
  return "";
}

void begin() {
  s_raw = (int32_t*)malloc(CHUNK_WORDS * sizeof(int32_t));
  if (!s_raw) {
    Base.error("audio: out of memory, capture disabled");
    return;
  }
  for (uint8_t b = 0; b < BAND_COUNT; b++)
    for (auto& f : s_filters[b]) f.design(BANDS[b].fLow, BANDS[b].fHigh, SAMPLE_RATE);

  xTaskCreatePinnedToCore(captureTask, "audio", CAPTURE_STACK, nullptr, 2, nullptr, 1);
  if (s_settings.streamPort) xTaskCreatePinnedToCore(streamTask, "pcm", STREAM_STACK, nullptr, 1, nullptr, 0);
}

bool takeLevels(Levels& out) {
  double sum[BAND_COUNT + 1];
  uint32_t count;
  taskENTER_CRITICAL(&s_mux);
  count = s_count;
  for (uint8_t b = 0; b <= BAND_COUNT; b++) {
    sum[b] = s_sumSq[b];
    s_sumSq[b] = 0;
  }
  s_count = 0;
  taskEXIT_CRITICAL(&s_mux);
  if (!count) return false;

  out.samples = count;
  out.overallDb = 20.0f * log10f(sqrtf((float)(sum[BAND_COUNT] / count)) + DBFS_EPSILON);
  for (uint8_t b = 0; b < BAND_COUNT; b++) out.bandDb[b] = 20.0f * log10f(sqrtf((float)(sum[b] / count)) + DBFS_EPSILON);
  return true;
}

void levelsJson(const Levels& l, JsonObject o) {
  o["overall_dbfs"] = serialized(String(l.overallDb, 1));
  o["samples"] = l.samples;
  JsonObject bands = o["bands"].to<JsonObject>();
  for (uint8_t b = 0; b < BAND_COUNT; b++) bands[BAND_NAMES[b]] = serialized(String(l.bandDb[b], 1));
}

void statusJson(JsonObject o) {
  o["gain"]          = s_settings.gain;
  o["sleeping"]      = !s_settings.awake;
  o["publish_ms"]    = s_settings.publishMs;
  o["sample_rate"]   = SAMPLE_RATE;
  o["i2s_running"]   = s_rx != nullptr;
  o["i2s_reinits"]   = s_totalReinits;
  o["slot"]          = s_settings.slot ? "right" : "left";
  o["slot_dbfs"]     = serialized(String(s_slotDb, 1));
  o["raw_nonzero"] = s_nonzeroWords;
  o["heap_free"] = ESP.getFreeHeap();
  o["heap_max_alloc"] = ESP.getMaxAllocHeap();  // largest single allocation possible — what TLS actually needs
  char hex[24];
  snprintf(hex, sizeof(hex), "%08x %08x", s_rawSample[0], s_rawSample[1]);
  o["raw_first"] = hex;
  o["stream_port"]   = s_settings.streamPort;
  if (s_streaming) o["stream_client"] = s_streamClient; else o["stream_client"] = nullptr;
}

}  // namespace Audio
