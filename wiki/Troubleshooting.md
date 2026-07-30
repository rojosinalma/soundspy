# Troubleshooting

## Node does not appear on the dashboard

- Confirm the node is connected to WiFi — check serial output on boot for `Connecting to WiFi` and the assigned IP address.
- Confirm the node is connected to MQTT — serial output shows `Connecting to MQTT... connected` and the subscribed control topic.
- Verify `FIRMWARE_MQTT_HOST` in `.env` is an IP address, not a hostname. ESP32 nodes on the IoT VLAN cannot resolve `.local` or internal DNS names.
- Check that the Mosquitto broker is running: `docker logs soundspy_mosquitto`.
- Check that the dashboard is running: `docker logs soundspy_dashboard`.
- Confirm `DASHBOARD_PORT` in `.env` matches the port you are browsing to.

## Node appears but shows no data / level stuck at −180 dBFS

- The I2S bus may be in a lockup state. The firmware watchdog will reinitialize the bus automatically after ~3 seconds of sustained silence. Check serial or remote logs for `I2S watchdog: reinitializing bus`.
- After 3 reinit attempts the firmware stops retrying. OTA a fresh firmware or reboot the node from the dashboard.
- Verify wiring — particularly that the L/R pin is tied to GND and that SD (GPIO 32), WS (GPIO 25), and SCK (GPIO 33) are all connected.
- For the ICS-43434 breakout: confirm the sound port hole in the PCB is not blocked.

## Audio stream not working

- The WebSocket connection for audio uses the same host and port as the dashboard (`FIRMWARE_WS_HOST:FIRMWARE_WS_PORT`). Confirm these are reachable IP addresses from the ESP32.
- Check for WebSocket disconnections in serial output: `WebSocket disconnected`.
- The audio stream reconnects automatically every 5 seconds after a drop.

## OTA update fails or node does not reboot after OTA

- Confirm `DASHBOARD_PORT` is correct in `.env` — `deploy_ota.sh` constructs the dashboard URL from `FIRMWARE_MQTT_HOST:DASHBOARD_PORT`.
- Check that the `builds/` directory is mounted into the dashboard container (see `docker-compose.yml` volumes).
- Watch dashboard logs during OTA: `docker logs -f soundspy_dashboard`.
- If the node downloads firmware but does not come back online, the OTA rollback may have triggered — the previous firmware is still running. Check serial output for `OTA Error` or MQTT connectivity failures on the new firmware.
- The firmware only calls `esp_ota_mark_app_valid_cancel_rollback()` after MQTT connects successfully. If MQTT credentials or network config changed in the new build, the rollback will fire.

## Node keeps reconnecting to MQTT

- Check for a duplicate `client_id` — each node uses `esp32-<chip_id>` as its MQTT client ID. If two nodes share a chip ID (should not happen with genuine ESP32 chips), they will boot-loop each other off the broker.
- Increase `MQTT_KEEPALIVE` or check for network instability between the IoT VLAN and the server.

## Push notifications not arriving

- Confirm `soundspy_monitor` is running: `docker logs soundspy_monitor`.
- Verify `NTFY_URL` in `.env` points to the correct ntfy instance and that your ntfy client is subscribed to the correct topic.
- Check `FREQ_THRESHOLD_DBFS` — if set too low (e.g., `−60`), alerts will fire constantly; if too high (e.g., `0`), they will never fire.
- The cooldown defaults to 300 seconds. Alerts will not repeat within that window.

## Build fails

- Run `./scripts/init_arduino.sh` to ensure the ESP32 core and all required libraries are installed.
- Confirm arduino-cli is in `bin/arduino-cli` or on the system PATH.
- If the ESP32 core is outdated, `init_arduino.sh` will upgrade it automatically.
- Check that `.env` exists and all `PLACEHOLDER_*` variables have values — a missing variable will produce a compile error or a runtime connection failure.

## Dashboard shows stale node state after restart

- In-memory state (levels, history) is lost on container restart. Only `data/node_names.json` persists. Nodes re-appear and start publishing fresh data automatically once they reconnect to MQTT.
