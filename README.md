<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/logo.svg" width="120" alt="soundspy logo"/>
</p>

<h1 align="center">soundspy</h1>
<p align="center">Real-time multi-node sound monitoring system for ESP32</p>

---

ESP32 nodes with I2S MEMS microphones sample audio, meter it in six frequency bands plus an overall level, and publish the readings over MQTT. The dashboard discovers the nodes, shows live meters, spectrum and an hour of history per node, relays live audio from any node to the browser, and sends alerts (Telegram, Discord, ntfy, Pushover, email) when a configurable rule fires. One application is keeping an eye on how much of a rehearsal or a mix makes it through a shared wall; the same setup works for any room you want to listen to from elsewhere.

<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/screenshot.png" alt="soundspy dashboard" width="100%"/>
</p>

Hardware, firmware, dashboard, enclosure and design notes are documented in `docs/`.

## Requirements

**Hardware (per node)**
- ESP32 development board (38-pin DevKit with 4 MB flash)
- ICS-43434 or INMP441 I2S MEMS microphone (optionally on the carrier PCB in `pcb/`)

**Software**
- Docker + Docker Compose for the dashboard
- An MQTT broker (for example Mosquitto) reachable by both the dashboard and the nodes
- Arduino CLI with the `esp32:esp32` core (3.x) to build the firmware

## Setup

**1. Configure and start the dashboard**
```bash
cp .env.example .env     # broker address and credentials, dashboard port
docker compose up -d
```
The dashboard listens on `http://<host>:8091`.

**2. Build and flash a node**
```bash
./scripts/init_arduino.sh                     # ESP32 core + libraries (once)
ESP32_BASE_DIR=/path/to/Esp32Base ./scripts/build_firmware.sh
```
Flash `builds/soundspy_latest.bin` over USB the first time, then join the node's WiFi setup portal and enter your network and broker settings. The node appears on the dashboard as soon as it publishes. Flashing, OTA updates and the standalone legacy firmware are covered in [docs/firmware.md](docs/firmware.md); wiring in [docs/hardware.md](docs/hardware.md).

## License

[AGPL-3.0](LICENSE)
