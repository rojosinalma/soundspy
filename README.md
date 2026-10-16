<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/logo.svg" width="120" alt="soundspy logo"/>
</p>

<h1 align="center">soundspy</h1>
<p align="center">Real-time multi-node sound monitoring system for ESP32</p>

<p align="center">
  <a href="https://github.com/rojosinalma/soundspy/actions/workflows/publish-image.yml"><img src="https://github.com/rojosinalma/soundspy/actions/workflows/publish-image.yml/badge.svg" alt="publish-image"/></a>
  <a href="https://github.com/rojosinalma/soundspy/actions/workflows/build-firmware.yml"><img src="https://github.com/rojosinalma/soundspy/actions/workflows/build-firmware.yml/badge.svg" alt="build-firmware"/></a>
  <a href="https://github.com/rojosinalma/soundspy/actions/workflows/release.yml"><img src="https://github.com/rojosinalma/soundspy/actions/workflows/release.yml/badge.svg" alt="release"/></a>
  <a href="https://github.com/rojosinalma/soundspy/releases"><img src="https://img.shields.io/github/v/release/rojosinalma/soundspy" alt="release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/rojosinalma/soundspy" alt="licence"/></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/screenshot.png" alt="soundspy dashboard" width="100%"/>
</p>

ESP32 nodes with I2S MEMS microphones sample audio, meter it in six frequency bands plus an overall level, and publish the readings over MQTT. The dashboard discovers the nodes, shows live meters, spectrum and an hour of history per node, relays live audio from any node to the browser, and sends alerts (Telegram, Discord, ntfy, Pushover, email) when a configurable rule fires. One application is keeping an eye on how much of a rehearsal or a mix makes it through a shared wall; the same setup works for any room you want to listen to from elsewhere.

Hardware, firmware, dashboard, enclosure and design notes are documented in [`docs/`](docs/).

## Requirements

**Dashboard**
- Docker 24+ with Docker Compose v2 (or Python 3.12+ to run from source)
- An MQTT broker reachable by both the dashboard and the nodes, for example Eclipse Mosquitto 2.x

**Firmware**
- arduino-cli 1.x with the `esp32:esp32` core 3.3+
- The Esp32Base library for the current firmware (`firmware/`); the legacy firmware (`node_firmware/`) builds with PubSubClient, WebSockets and ArduinoJson from the library index

**Hardware (per node)**
- ESP32 development board (38-pin DevKit with 4 MB flash)
- ICS-43434 or INMP441 I2S MEMS microphone, optionally on the carrier PCB in `pcb/` — wiring in [docs/hardware.md](docs/hardware.md)

## Installation

```bash
git clone https://github.com/rojosinalma/soundspy.git && cd soundspy
cp .env.example .env     # broker address and credentials, dashboard port
docker compose up -d     # pulls ghcr.io/rojosinalma/soundspy:latest
```

The image runs as uid 1000; make sure `./data` is writable by that user (`chown -R 1000:1000 data`).

Then build and flash a node:

```bash
./scripts/init_arduino.sh                                     # ESP32 core + libraries (once)
ESP32_BASE_DIR=/path/to/Esp32Base ./scripts/build_firmware.sh
```

Flash `builds/soundspy_latest.bin` over USB the first time, then join the node's WiFi setup portal and enter your network and broker settings. Flashing, OTA updates and the legacy firmware are covered in [docs/firmware.md](docs/firmware.md).

## Usage

Open `http://<host>:8091`. A node appears on the dashboard as soon as it publishes; click its name to rename it, drag the threshold marker to set its alert level, and use the gain, sleep and live-audio controls on the card. Notification channels and alert rules live under **Settings**. The HTTP API (`GET /api/nodes`, `POST /api/control`, `GET /health`, …) is listed in [docs/dashboard.md](docs/dashboard.md).

## Development

```bash
# dashboard from source (templates reload; restart for Python changes)
cd dashboard && pip install -r requirements.txt && MQTT_HOST=<broker> DB_PATH=./soundspy.db python app.py

# checks
python -m py_compile dashboard/*.py && bash -n scripts/*.sh
./scripts/build_firmware.sh legacy
```

Layout, the Docker dev loop, enclosure rendering and the release flow are in [docs/development.md](docs/development.md); contribution rules in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[AGPL-3.0](LICENSE) — Copyright (C) 2026 rojosinalma
