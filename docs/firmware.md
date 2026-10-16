# Firmware

Two sketches live in the repository:

| Sketch | Version | Built with | Status |
|---|---|---|---|
| `firmware/` | `APP_VERSION` in `soundspy.ino` (2.1.2) | `./scripts/build_firmware.sh` (default target `current`) | Current firmware. Needs the **Esp32Base** Arduino library. |
| `node_firmware/` (+ `recovery_firmware/`) | `FIRMWARE_VERSION` (1.7.7) | `./scripts/build_firmware.sh legacy` | Standalone legacy firmware, public libraries only. Builds in CI. |

Both publish the same `data` payload the dashboard understands; the topic layout differs (see below). Use `firmware/` for new nodes.

## Toolchain

```bash
cd bin && curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh && cd ..
./scripts/init_arduino.sh
```

`init_arduino.sh` installs the `esp32:esp32` core (3.x) and the libraries PubSubClient, WebSockets and ArduinoJson. The build scripts look for `bin/arduino-cli` first and fall back to one on `PATH`.

### Esp32Base (current firmware only)

`firmware/` is written on top of Esp32Base, an Arduino library that provides what every node needs besides the audio work: NVS-backed configuration, WiFi with a captive setup portal, a boot guard with recovery fallback, the HTTP system portal (`/sys`) and `POST /api` command endpoint, HTTP firmware upload, and MQTT with a retained status message and LWT. The library is not on the Arduino library index yet, so you need a checkout of it; point `ESP32_BASE_DIR` at the folder that holds its `library.properties`:

```bash
ESP32_BASE_DIR=/path/to/Esp32Base ./scripts/init_arduino.sh   # links it into the Arduino libraries folder, or
ESP32_BASE_DIR=/path/to/Esp32Base ./scripts/build_firmware.sh # passes it to arduino-cli for this build only
```

Without it, `build_firmware.sh` stops with a message and the legacy sketch remains buildable.

## Building

```bash
./scripts/build_firmware.sh            # firmware/  -> builds/soundspy_v2.1.2.bin, soundspy_latest.bin, soundspy_v2.1.2_FULL_FLASH.bin
./scripts/build_firmware.sh legacy     # node_firmware/ -> builds/soundspy_v1.7.7.bin + soundspy_recovery_v1.0.0.bin
```

- `FQBN` (default `esp32:esp32:esp32:FlashMode=dio`) and `BUILD_DIR` (default `builds/`) can be overridden in the environment.
- The current firmware bakes no credentials in; nothing from `.env` is needed.
- The legacy build reads `.env` for the `PLACEHOLDER_*` defaults (`WIFI_SSID`, `WIFI_PASSWORD`, `FIRMWARE_MQTT_HOST/PORT`, `FIRMWARE_WS_HOST/PORT`) and writes a `node_firmware.rendered.ino` copy (git-ignored) that you can open in the Arduino IDE. It uses the repository `partitions.csv` (factory recovery slot + two 1.4 MB app slots).

## First flash over USB

Current firmware — write the merged image at address 0:

```bash
esptool --chip esp32 --port /dev/ttyUSB0 --baud 921600 write-flash 0x0 builds/soundspy_v2.1.2_FULL_FLASH.bin
# or, from WSL with the board attached through usbipd:
./scripts/flash_wsl.sh /dev/ttyUSB0
```

Legacy firmware — `./scripts/flash_initial.sh /dev/ttyUSB0` writes bootloader, partition table, recovery image, main firmware and the credentials from `.env` into NVS.

## First boot and configuration (current firmware)

A node with no WiFi configured opens a setup access point and a captive portal; join it, enter your WiFi, the MQTT broker (`mqtt://`, `mqtts://`, `ws://` or `wss://` URL with credentials) and an admin password, and the node reboots onto your network. From then on:

- `http://<node-ip>/` prints the firmware version and where to go.
- `http://<node-ip>/sys` is the system portal: network and broker settings, logs, firmware upload, reboot and recovery.
- `GET /api/audio` returns the audio settings and status; `POST /api/audio` with a JSON object changes them (admin session or device token required). Example: `{"gain": 5, "publish_ms": 50}`.

### Settings

Persisted on the node (NVS namespace `sspy`) and reported in the retained status message under `app_status`:

| Key | Range / default | Meaning |
|---|---|---|
| `gain` | 0–10, default 10 | Linear gain applied before metering and streaming (10 = +20 dB) |
| `publish_ms` | 20–5000, default 20 | Interval of the MQTT `data` message |
| `stream_port` | 0 or 1024–65535, default 8181 | TCP port of the raw PCM stream; 0 disables it (takes effect on reboot) |
| `awake` | `true` | `false` = soft sleep: I2S off, status keeps publishing |
| `slot` | 0 (left) / 1 (right) | I2S slot the microphone drives |

### MQTT topics

Prefix `esp32` by default (the dashboard's `MQTT_PREFIX` must match); `<chip_id>` is the 12-hex-digit MAC.

| Topic | Direction | Content |
|---|---|---|
| `esp32/<chip_id>/status` | node → (retained) | `app`, `version`, `hostname`, `ip`, `role` (`app`/`recovery`), `online`, `app_status` {gain, publish_ms, stream_port, awake, slot, sample_rate, …}; LWT sets `online: false` |
| `esp32/<chip_id>/data` | node → | `{"seq", "ts", "samples", "overall_dbfs", "bands": {"sub_bass", "bass", "low_mid", "mid", "high_mid", "high"}}` in dBFS |
| `esp32/<chip_id>/log` | node → | `{"level": "I"/"W"/"E", "text", "ms", "seq"}` |
| `esp32/<chip_id>/cmd` | → node | `{"cmd":"gain","value":5}`, `{"cmd":"sleep"}`, `{"cmd":"wake"}`, `{"cmd":"set","settings":{…}}` |

Bands: 50–120, 120–250, 250–500, 500–2000, 2000–6000 and 6000–20000 Hz, each a pair of biquad band-passes; levels are RMS over the publish interval.

### Live audio

While awake, the node runs a TCP server on `stream_port`. A client gets one JSON header line (`{"format":"s16le","rate":44100,"channels":1,"chip_id":"…"}`) followed by raw mono 16-bit PCM with gain applied. The PCM ring buffer exists only while a client is connected, so an unattended node spends nothing on it. The dashboard is the normal client; `nc <node-ip> 8181 | tail -c +N | aplay -f S16_LE -r 44100 -c 1` works for a quick listen.

## Over-the-air updates

Current firmware: open `http://<node-ip>/sys`, log in as admin, and upload `builds/soundspy_v<version>.bin` under **Firmware**; the node writes it to the application slot and reboots into it. The boot guard rolls back to the previous image or to the recovery slot if the new build does not come up healthy. The same upload works from a shell: `curl -F op=flash -F target=app -F file=@builds/soundspy_latest.bin http://<node-ip>/api` with an admin session cookie or a device bearer token.

Legacy firmware: `./scripts/deploy_ota.sh <chip_id> [builds/soundspy_v1.7.x.bin]` uploads the binary to the dashboard and publishes the download URL on `soundspy/<chip_id>/control`; the node fetches it with HTTPUpdate, reboots, and confirms the image once MQTT reconnects (otherwise the bootloader reverts).

## Legacy firmware in brief

`node_firmware/node_firmware.ino` is self-contained: WiFi + PubSubClient + WebSocketsClient + HTTPUpdate. It publishes to `soundspy/<chip_id>/{data,heartbeat,log,boot}`, listens on `soundspy/<chip_id>/control`, pushes live audio as base64 JSON over a WebSocket to the dashboard host (`FIRMWARE_WS_HOST:FIRMWARE_WS_PORT`), and reads its credentials from NVS (written by `flash_initial.sh` or the recovery portal) with the `PLACEHOLDER_*` build-time values as fallback. `recovery_firmware/` is the factory-slot image: it counts crashes in NVS, serves a credential portal and accepts MQTT-triggered OTA so a bricked main slot can be refilled without USB.

## Serial monitor

`./scripts/serial_monitor.sh [port…]` follows one or all `/dev/ttyUSB*` ports at 115200 baud.
