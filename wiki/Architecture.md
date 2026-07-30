# Architecture

soundspy is a real-time multi-node sound monitoring system. ESP32 microcontrollers with I2S MEMS microphones sample audio, perform frequency analysis, and publish data over MQTT to a web dashboard with push notification alerts.

## Data Flow

```
ESP32 + I2S Mic (44.1kHz, 6-band Butterworth filters, 50Hz publish rate)
    → MQTT soundspy/<chip_id>/data
    → Eclipse Mosquitto broker (port 1883, LAN-only, no auth)
    → Flask/SocketIO Dashboard (port 8091) → Browser (Socket.IO + Web Audio API)
    → Threshold Monitor → ntfy push alerts (port 8090)
```

Control flow (gain, OTA, sleep/wake):

```
Browser → POST /api/control → dashboard.py → MQTT soundspy/<chip_id>/control → ESP32
```

## Hardware (per node)

- ESP32 development board
- ICS-43434 or INMP441 I2S MEMS microphone
- Audio sampled at 44.1 kHz, published at 50 Hz

### Per-node Processing

Each firmware loop reads 1024 I2S samples, applies adjustable gain (default 4x / 12 dB), then runs each sample through a cascade of two 2nd-order biquad bandpass filters per band:

| Band      | Frequency Range  |
|-----------|-----------------|
| sub_bass  | 50–120 Hz       |
| bass      | 120–250 Hz      |
| low_mid   | 250–500 Hz      |
| mid       | 500–2000 Hz     |
| high_mid  | 2000–6000 Hz    |
| high      | 6000–20000 Hz   |

At each 20 ms publish interval, the firmware computes RMS per band and overall, converts to dBFS, and publishes a JSON payload over MQTT.

For live audio streaming, 100 ms PCM chunks (4410 samples of 16-bit) are base64-encoded and sent to the dashboard via WebSocket at `/ws/audio`.

### Node Identity

Node ID is derived at runtime from the lower 4 bytes of the ESP32's EfuseMAC, formatted as an 8-character hex string (e.g., `a1b2c3d4`). No configuration is required — the firmware is generic and each board self-identifies on first boot.

### Sleep / Wake

The firmware supports soft sleep: I2S is stopped but WiFi and MQTT remain connected. The node can be woken remotely from the dashboard. A heartbeat is published to `soundspy/<chip_id>/heartbeat` every 30 seconds so the backend can distinguish sleeping nodes from crashed ones.

### OTA Rollback

`esp_ota_mark_app_valid_cancel_rollback()` is called only after MQTT connectivity is confirmed on boot. If the new firmware fails to reach MQTT, the bootloader automatically rolls back to the previous partition.

### I2S Watchdog

If the overall level stays below −170 dBFS for ~3 seconds after the 5-second startup grace period, the firmware reinitializes the I2S bus. After 3 reinit attempts it stops retrying but stays alive so MQTT control (OTA, diagnostics) continues to work.

## Backend Services

Four Docker services defined in `docker-compose.yml`:

| Service               | Container              | Role                                                |
|-----------------------|------------------------|-----------------------------------------------------|
| soundspy-mosquitto    | soundspy_mosquitto     | Eclipse Mosquitto 2 MQTT broker (port 1883)         |
| soundspy-dashboard    | soundspy_dashboard     | Flask + SocketIO dashboard, REST API, OTA manager   |
| soundspy-monitor      | soundspy_monitor       | Threshold monitor, publishes ntfy push alerts       |
| soundspy-ntfy         | soundspy_ntfy          | binwiederhier/ntfy push notification server         |

Node state is persisted in `data/node_names.json` (mounted into the dashboard container). All other state is in-memory.

Nodes are auto-discovered — any ESP32 publishing to `soundspy/<chip_id>/data` appears on the dashboard automatically. The dashboard maintains a `chip_id → display_name` mapping and auto-names new nodes `node-N`.

## MQTT Topics

| Topic                          | Publisher  | Content                                    |
|--------------------------------|------------|--------------------------------------------|
| `soundspy/<chip_id>/data`      | ESP32      | Frequency analysis payload (50 Hz)         |
| `soundspy/<chip_id>/control`   | Dashboard  | Gain, OTA URL, sleep/wake, reboot commands |
| `soundspy/<chip_id>/heartbeat` | ESP32      | Uptime, sleep state, free heap (30 s)      |
| `soundspy/<chip_id>/log`       | ESP32      | Remote log messages (level, msg, uptime)   |
| `soundspy/<chip_id>/boot`      | ESP32      | Boot report (firmware version, IP, reset reason) |
| `soundspy/<chip_id>/version`   | ESP32      | Firmware version string (on MQTT connect)  |

## Data Payload Example

Published to `soundspy/<chip_id>/data` at 50 Hz:

```json
{
  "node": "a1b2c3d4",
  "seq": 1042,
  "ts": 483920,
  "firmware": "1.4.1",
  "ip": "10.10.10.249",
  "overall_dbfs": -34.2,
  "bands": {
    "sub_bass": -52.1,
    "bass": -38.7,
    "low_mid": -41.3,
    "mid": -36.9,
    "high_mid": -44.5,
    "high": -58.2
  }
}
```

All dBFS values are computed from RMS over the accumulation window. The dashboard converts to dBA using A-weighting offsets per band; dBA is the default display mode.

## Tech Stack

- **Firmware:** Arduino/C++ — PubSubClient, WebSocketsClient, ArduinoJson, HTTPUpdate, custom biquad DSP
- **Backend:** Python 3.12 — Flask 3.0, Flask-SocketIO 5.3.6, Flask-Sock 0.7, paho-mqtt 1.6.1
- **Frontend:** Vanilla JS (no build step) — Socket.IO 4.5.4, Chart.js 4.4.0, Web Audio API, Canvas 2D
- **Infra:** Docker Compose, Eclipse Mosquitto 2, binwiederhier/ntfy, Traefik reverse proxy
- **Build:** arduino-cli, bash scripts

## Project Structure

```
node_firmware/
  node_firmware.ino           — Firmware source (version hardcoded, all else PLACEHOLDER_* tokens)
  node_firmware.rendered.ino  — Secrets-injected copy for Arduino IDE flashing (gitignored)
dashboard/
  dashboard.py                — Flask+SocketIO server, MQTT subscriber, REST API, OTA mgmt
  threshold_monitor.py        — Alert service (MQTT → ntfy push notifications)
  templates/dashboard.html    — Single-page web UI
  Dockerfile                  — Container for threshold_monitor
  Dockerfile.dashboard        — Container for dashboard
  requirements.txt            — Python deps
data/
  node_names.json             — Persistent chip_id → display_name mapping
scripts/
  build_firmware.sh           — Compile firmware, inject .env config, output soundspy_latest.bin
  deploy_ota.sh               — OTA deploy (upload binary + trigger via dashboard API)
  init_arduino.sh             — Arduino CLI setup (ESP32 core + libraries)
pcb/
  soundspy-mic-breakout.*     — KiCad project: ICS-43434 breakout adapter (15×12 mm)
  DESIGN.md                   — BOM, pinout, assembly notes
builds/                       — Compiled .bin files (gitignored, symlink soundspy_latest.bin)
docker-compose.yml            — 4-service stack
.env                          — Runtime config (gitignored)
```
