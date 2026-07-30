# Soundspy Project Context

## What Soundspy Does

A real-time multi-node sound monitoring system that tracks when audio production (studio monitors, instruments) might be disturbing neighbors through shared walls. ESP32 microcontrollers with I2S MEMS microphones sample audio, perform frequency analysis, and publish data over MQTT to a web dashboard with push notification alerts.

## Architecture & Data Flow

```
ESP32 + I2S Mic (44.1kHz, 6-band Butterworth filters, 50Hz publish rate)
    → MQTT "soundspy/<chip_id>/data" (chip_id = lower 4 bytes of ESP32 EfuseMAC as 8-char hex)
    → Mosquitto broker (port 1883, LAN-only, no auth)
    → Flask/SocketIO Dashboard (port 8091) → Browser (Socket.IO + Web Audio API)
    → Threshold Monitor → ntfy push alerts (port 8090)
```

Control flow (gain, OTA): Browser → POST /api/control → dashboard.py → MQTT → ESP32

Nodes are auto-discovered — any ESP32 publishing to `soundspy/<chip_id>/data` appears on the dashboard. The dashboard maintains a chip_id → display_name mapping for friendly node names.

## Project Structure

```
node_firmware/
  node_firmware.ino           — Firmware source (version hardcoded, all else uses PLACEHOLDER_* tokens)
  node_firmware.rendered.ino  — Build output with secrets injected, for Arduino IDE flashing (gitignored)
dashboard/
  dashboard.py                — Flask+SocketIO server, MQTT subscriber, REST API, OTA mgmt
  threshold_monitor.py        — Alert service (MQTT → ntfy push notifications)
  templates/dashboard.html    — Single-page web UI (spectrum, audio, charts, gain, OTA, live logs)
  Dockerfile                  — Container for threshold_monitor
  Dockerfile.dashboard        — Container for dashboard
  requirements.txt            — Python deps
data/
  node_names.json             — Persistent chip_id → display_name mapping (mounted into dashboard container)
scripts/
  build_firmware.sh           — Compiles firmware, injects config from .env, generates rendered .ino
  deploy_ota.sh               — CLI OTA deployment (upload binary + trigger via MQTT, takes chip_id arg)
  init_arduino.sh             — Arduino CLI setup (ESP32 core + libs)
pcb/
  soundspy-mic-breakout.*     — KiCad project: ICS-43434 breakout adapter (15x12mm)
  DESIGN.md                   — BOM, pinout, assembly notes
builds/                       — Compiled .bin firmware files (gitignored)
mosquitto/config/             — Mosquitto broker config
docker-compose.yml            — 4-service stack: mosquitto, dashboard, ntfy, monitor
docker-compose.override.yml   — Traefik + homepage labels (gitignored, local only)
.env                          — Docker service config + firmware version (gitignored)
```

## Tech Stack

- **Hardware:** ESP32 + ICS-43434 I2S MEMS mic (GPIO32 SD, GPIO25 WS, GPIO33 SCK)
- **Firmware:** Arduino/C++ — PubSubClient, WebSocketsClient, ArduinoJson, HTTPUpdate, custom biquad DSP
- **Backend:** Python 3.12 — Flask 3.0, Flask-SocketIO 5.3.6, Flask-Sock 0.7, paho-mqtt 1.6.1
- **Frontend:** Vanilla JS (no build step) — Socket.IO 4.5.4, Chart.js 4.4.0, Web Audio API, Canvas 2D
- **Infra:** Docker Compose, Eclipse Mosquitto 2, binwiederhier/ntfy, Traefik reverse proxy
- **Build:** arduino-cli, bash scripts

## Key Features

- 6-band real-time EQ spectrum visualization (bars or wave mode)
- Live audio streaming from ESP32 to browser via WebSocket (<100ms latency)
- Remote gain control (0–20x) per node
- OTA firmware updates from dashboard UI or CLI script with automatic rollback
- Push notifications (ntfy) when bass exceeds threshold (-20 dBA default, 5-min cooldown)
- 1-hour in-memory history (deque, 3600 samples/node) with selectable time ranges; averaged in linear power domain
- I2S watchdog: detects bus lockup, reinits up to 3 times then stays alive in degraded mode
- Remote logging: firmware publishes to soundspy/<chip_id>/log and /boot over MQTT
- Live logs panel in dashboard: per-node sidebar + app/system tab split
- OTA rollback: esp_ota_mark_app_valid_cancel_rollback() gates on MQTT connectivity
- Node naming: dashboard auto-names new nodes "node-N", users can rename via inline edit in UI
- Soft sleep/wake: node stops I2S but keeps MQTT alive; wakeable remotely from dashboard
- Heartbeat: firmware publishes to soundspy/<chip_id>/heartbeat every 30s; backend uses it to distinguish sleeping vs crashed
- dBFS/dBA toggle: click unit label to switch; dBA is default; threshold defaults to -20 dBA, stored as dBFS internally after first band calibration
- State persisted to `data/node_names.json` (mounted volume); all other state is in-memory

## Dashboard Chart Zones

Both the history chart and EQ spectrum use colored background zones:
- Green (-80 to -20 dBFS): quiet/ambient
- Yellow (-20 to -10 dBFS): noticeable noise
- Red (-10 to 0 dBFS): loud/clipping

Alert threshold defaults to -20 dBFS (configurable per-node via slider).

## Configuration

Firmware version is the only hardcoded value in `node_firmware.ino`. All other config (WiFi creds, MQTT/WS addresses) uses `PLACEHOLDER_*` tokens that `build_firmware.sh` replaces from `.env` at build time. Node identity is derived at runtime from the ESP32's chip ID (lower 4 bytes of EfuseMAC as 8-char hex), so firmware is generic — compile once, flash to any board.

`.env` firmware vars: `WIFI_SSID`, `WIFI_PASSWORD`, `FIRMWARE_MQTT_HOST`, `FIRMWARE_MQTT_PORT`, `FIRMWARE_WS_HOST`, `FIRMWARE_WS_PORT`.

Docker services use `.env` for internal container networking (`MQTT_HOST=soundspy-mosquitto`).

The `docker-compose.override.yml` (gitignored) adds traefik labels for `soundspy.silver.local` routing and homepage dashboard integration.

## Deployment

1. `docker compose up -d` — launches all 4 services (with override for traefik/homepage); `data/` volume mounted for state persistence
2. `./scripts/build_firmware.sh` — compiles generic firmware (no node ID needed), injects .env config, generates rendered .ino
3. Initial flash via USB serial (or open rendered .ino in Arduino IDE) — same binary works on any ESP32
4. Subsequent updates via OTA: `deploy_ota.sh <chip_id>` or dashboard UI
5. OTA automatically rolls back if new firmware fails to connect to MQTT

## Versioning

Single source of truth: `VERSION` file in repo root. Use `./scripts/bump_version.sh <new-version>` to update VERSION, firmware, and dashboard in one step. GitHub Actions (`.github/workflows/release.yml`) auto-tags and creates a GitHub release when VERSION changes on main, pulling notes from CHANGELOG.md.

## Network

- Server: 10.10.10.20 (silver.local)
- ESP32 node: 10.10.10.249 (rojo_IoT WiFi, IoT VLAN — cannot resolve .silver.local DNS)
- Dashboard: https://soundspy.silver.local (via traefik) or http://10.10.10.20:8091
- MQTT: 10.10.10.20:1883 (direct TCP, not proxied by traefik)
