# Firmware Setup

## Prerequisites

**Arduino CLI** is required to compile firmware. The build script looks for it in `bin/arduino-cli` (project-local) first, then falls back to the system PATH.

Install to the project `bin/` directory:

```bash
cd bin && curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
```

Or install system-wide and let the script find it on PATH.

## Initialize Arduino CLI

Run once after installing arduino-cli to install the ESP32 core and required libraries (PubSubClient, WebSockets, ArduinoJson):

```bash
./scripts/init_arduino.sh
```

## Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and set your values:

| Variable              | Description                                            |
|-----------------------|--------------------------------------------------------|
| `WIFI_SSID`           | WiFi network name                                      |
| `WIFI_PASSWORD`       | WiFi password                                          |
| `FIRMWARE_MQTT_HOST`  | IP address of your MQTT broker (ESP32-reachable)       |
| `FIRMWARE_MQTT_PORT`  | MQTT port (default `1883`)                             |
| `FIRMWARE_WS_HOST`    | IP address for WebSocket audio stream                  |
| `FIRMWARE_WS_PORT`    | WebSocket port (default `8091`)                        |
| `MQTT_HOST`           | Internal Docker container name (`soundspy-mosquitto`)  |
| `MQTT_PORT`           | MQTT port for Docker services                          |
| `DASHBOARD_PORT`      | Dashboard HTTP port (default `8091`)                   |
| `NTFY_PORT`           | ntfy push server port (default `8090`)                 |
| `NTFY_URL`            | ntfy URL for the monitor service                       |
| `FREQ_THRESHOLD_DBFS` | Alert threshold in dBFS (default `-20`)                |
| `COOLDOWN_SECONDS`    | Minimum seconds between alerts (default `300`)         |

The ESP32 cannot resolve Docker hostnames, so `FIRMWARE_MQTT_HOST` and `FIRMWARE_WS_HOST` must be IP addresses, not hostnames.

The firmware version is hardcoded in `node_firmware/node_firmware.ino` — it is not set in `.env`.

## Build Firmware

The firmware is **generic** — it contains no node-specific configuration. Node identity is derived at runtime from the ESP32's chip ID. Compile once and flash the same binary to any board.

```bash
./scripts/build_firmware.sh
```

The script:
1. Reads `.env` and injects WiFi credentials and MQTT/WS addresses into the `PLACEHOLDER_*` tokens in the source
2. Compiles with arduino-cli for `esp32:esp32:esp32`
3. Outputs `builds/soundspy_v<version>.bin` and a symlink `builds/soundspy_latest.bin`
4. Also writes `node_firmware/node_firmware.rendered.ino` — a secrets-injected copy for manual Arduino IDE flashing

No arguments are needed. The version is read from the `.ino` source automatically.

## Initial Flash (USB)

Flash to a board for the first time via USB serial:

```bash
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 \
  --input-file builds/soundspy_latest.bin
```

Replace `/dev/ttyUSB0` with the actual serial port (`/dev/ttyACM0` on some Linux systems, `COMx` on Windows). After the first USB flash, all subsequent updates can be done via OTA.

Alternatively, open `node_firmware/node_firmware.rendered.ino` in the Arduino IDE and use its upload button.

## OTA Updates

After a node is running and connected, deploy new firmware wirelessly:

```bash
./scripts/deploy_ota.sh <chip_id>
```

The `chip_id` is the 8-character hex string shown in the dashboard node card and on the serial output during boot (e.g., `a1b2c3d4`).

The script:
1. Uploads the firmware binary to the dashboard (`/api/ota/upload`)
2. Triggers the OTA update via the dashboard API (`/api/ota/trigger`), which publishes the firmware URL to `soundspy/<chip_id>/control` over MQTT
3. The ESP32 downloads the firmware (~30 s), flashes it (~10 s), and reboots (~10 s)

To deploy a specific build instead of the latest:

```bash
./scripts/deploy_ota.sh a1b2c3d4 builds/soundspy_v1.4.0.bin
```

OTA includes automatic rollback: if the new firmware fails to establish MQTT connectivity on boot, the ESP32 bootloader reverts to the previous partition.

You can also trigger OTA from the dashboard UI — navigate to a node card and use the OTA panel.

## Monitoring

```bash
docker logs -f soundspy_dashboard   # Dashboard + OTA progress
docker logs -f soundspy_monitor     # Alert service
```

Boot and log messages from the firmware are also visible in the dashboard's live logs panel, published over MQTT to `soundspy/<chip_id>/log` and `soundspy/<chip_id>/boot`.
