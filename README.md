<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/logo.svg" width="120" alt="soundspy logo"/>
</p>

<h1 align="center">soundspy</h1>
<p align="center">Real-time multi-node sound monitoring system for ESP32</p>

---

ESP32 nodes with I2S microphones sample audio, perform 6-band frequency analysis, and publish to a web dashboard via MQTT. Designed to monitor when audio production might be disturbing neighbors through shared walls.

## Requirements

**Hardware (per node)**
- ESP32 development board
- ICS-43434 or INMP441 I2S MEMS microphone

**Software**
- Docker + Docker Compose
- Arduino CLI (for firmware builds) — or Arduino IDE

## Setup

**1. Configure environment**
```bash
cp .env.example .env
# Edit .env with your WiFi credentials and server IP
```

**2. Start services**
```bash
docker compose up -d
```
Dashboard: `http://<server-ip>:8091`

**3. Build and flash firmware**
```bash
./scripts/build_firmware.sh
# Initial flash via USB:
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 \
  --input-file builds/soundspy_latest.bin
```
Subsequent updates can be done via OTA from the dashboard.

**Hardware wiring (I2S mic → ESP32)**

| Mic Pin | ESP32 GPIO |
|---------|------------|
| VDD     | 3.3V       |
| GND     | GND        |
| SD      | GPIO32     |
| WS      | GPIO25     |
| SCK     | GPIO33     |
| L/R     | GND        |

## Development

**Project structure**
```
node_firmware/node_firmware.ino   — ESP32 firmware
dashboard/dashboard.py            — Flask + SocketIO backend
dashboard/templates/dashboard.html — Web UI
dashboard/threshold_monitor.py    — Alert service
scripts/build_firmware.sh         — Build script
scripts/deploy_ota.sh             — OTA deploy script
```

**OTA deploy to a node**
```bash
./scripts/deploy_ota.sh <chip_id>
# chip_id visible in dashboard or serial output on boot
```

**Useful commands**
```bash
docker logs -f soundspy_dashboard   # Dashboard logs
docker logs -f soundspy_monitor     # Alert service logs
```

For detailed documentation see the [wiki](https://github.com/rojosinalma/soundspy/wiki).

## License

MIT
