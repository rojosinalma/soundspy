# Adding nodes

Nodes carry no per-node configuration: the same binary runs on every board, and a node identifies itself by its chip id (the ESP32's MAC). Adding one is wiring, flashing, joining the network.

1. Wire the ESP32 and the microphone as in [hardware.md](hardware.md), or plug them into a carrier PCB.
2. Flash the current build over USB (build it first if `builds/` is empty):
   ```bash
   ./scripts/build_firmware.sh
   esptool --chip esp32 --port /dev/ttyUSB0 --baud 921600 write-flash 0x0 builds/soundspy_v*_FULL_FLASH.bin
   ```
3. Power the node, join its setup access point and enter your WiFi, the broker URL and credentials, and an admin password. It reboots onto your network and starts publishing on `esp32/<chip_id>/data`.
4. The dashboard lists the node under its hostname within a few seconds. Click the name to rename it, set its threshold marker, and add it to alert rules on `/settings` if you want per-node alerts.

Updates after that are over the air through the node's `/sys` portal; see [firmware.md](firmware.md).

## Several nodes

Each node costs the dashboard one MQTT subscription share (one `+` subscription covers them all), one relay thread while a browser is listening, and a 3600-point history in memory. A dozen nodes on a small host is routine. The relay cap is 16 simultaneous audio streams (`MAX_RELAYS` in `dashboard/audio_relay.py`).

## Legacy nodes

Boards still on `node_firmware/` take their WiFi and broker settings from NVS, written by `./scripts/flash_initial.sh` on the first flash (from `.env`), and publish under `soundspy/<chip_id>/…`. The current dashboard listens on the `esp32` prefix, so move such nodes to the current firmware or run the dashboard with `MQTT_PREFIX=soundspy` for them.
