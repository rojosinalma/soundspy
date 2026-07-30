# Adding More Nodes

soundspy is designed to scale horizontally with no per-node configuration. The firmware is generic — the same binary runs on every board. Node identity is derived at runtime from the ESP32's chip ID, so you never need to rebuild or modify anything for a new node.

## Steps

1. Wire the new ESP32 + mic using the same [hardware wiring](Hardware-Wiring.md).

2. Flash the existing firmware binary via USB:

   ```bash
   arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 \
     --input-file builds/soundspy_latest.bin
   ```

   If you have not built firmware yet, run `./scripts/build_firmware.sh` first.

3. Power on the new node. It will connect to WiFi and MQTT, derive its chip ID, and begin publishing to `soundspy/<chip_id>/data`.

4. The dashboard auto-discovers the new node and assigns it a name (`node-2`, `node-3`, etc.). Click the name to rename it.

## No Rebuild Needed

The same `builds/soundspy_latest.bin` can be flashed to any number of boards. WiFi credentials and MQTT addresses are baked in at build time from `.env`. If your network config has not changed since the last build, there is nothing to regenerate.

If you need to update credentials or addresses, rebuild once:

```bash
./scripts/build_firmware.sh
```

Then flash the new binary to all nodes — either via USB for the first flash, or via OTA for nodes already running:

```bash
./scripts/deploy_ota.sh <chip_id>
```

## Subsequent OTA Updates

Once a node has been flashed once via USB, all future updates can be done wirelessly from the dashboard UI or the CLI:

```bash
./scripts/deploy_ota.sh <chip_id>
```

The `chip_id` is visible in the dashboard node card and in the serial output during boot.

## Resource Considerations

Each node adds one MQTT subscriber connection, one WebSocket audio stream, and one 3600-sample in-memory history deque in the dashboard. The dashboard is single-threaded (Flask-SocketIO with eventlet), so at very high node counts (10+) you may want to profile memory and SocketIO broadcast latency. For typical home or small-studio use, a dozen nodes on a modest server is well within range.
