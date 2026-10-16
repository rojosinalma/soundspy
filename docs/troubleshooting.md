# Troubleshooting

## The node does not appear on the dashboard

- Open `http://<node-ip>/sys` and check the network and broker status; the serial console (`./scripts/serial_monitor.sh`) shows the same at boot.
- The dashboard only accepts nodes whose status says `app: "soundspy"` and listens on `MQTT_PREFIX` (`esp32` by default). Subscribe with `mosquitto_sub -t 'esp32/#' -v` on the broker to see what the node publishes.
- Both the node and the dashboard must reach the broker: the dashboard uses `MQTT_HOST` from `.env` (a container name or an address), the node the URL you entered in its portal (an IP address if your network has no DNS for the broker).
- `docker logs -f soundspy` prints every status the dashboard accepts (`[status] <chip_id> …`) and MQTT errors.

## Level stuck at −180 dBFS or no data

- The I2S bus can lock up; after about 3.5 s of silence the firmware reinitialises it (up to three times, logged as `audio: …` on the `log` topic). After that, reboot the node from the dashboard.
- Check SD (GPIO 32), WS (GPIO 25), SCK (GPIO 33) and that L/R is tied to GND — or set `slot` to `1` if the mic drives the right slot.
- A node in soft sleep publishes no data; wake it from the card.

## No live audio

- The relay connects to the node's `stream_port` (8181 by default) from the dashboard host; the port must be reachable from where the container runs, and `stream_port` must not be 0.
- `GET /api/relays` shows each relay's target and whether it is connected; `[relay] …` lines in the dashboard log give the reason for a failed connection.
- Relays only run while a browser is connected to the dashboard.

## OTA upload fails

- The portal rejects an upload when the file is not a `.bin` or exceeds the application slot; `build_firmware.sh` prints the size against the slot limit.
- If the node does not come back after flashing, the boot guard has rolled back to the previous image (or to recovery, reported as *recovery* on the card). Check `/sys` → logs for the reason, fix the build and upload again.
- Legacy nodes: `deploy_ota.sh` builds the dashboard URL from `FIRMWARE_MQTT_HOST:DASHBOARD_PORT` in `.env`; the node must be able to download from there.

## Alerts do not arrive

- Test the channel on `/settings` → Channels; the error returned by the provider is shown.
- A rule only fires when the level is **above** its threshold and the cooldown allows it; the alert history lists every firing.
- Rules evaluate the live `data` stream, so a node that is offline or sleeping never triggers.

## Build fails

- Run `./scripts/init_arduino.sh` again to make sure the `esp32:esp32` core and the libraries are installed.
- `firmware/` needs the Esp32Base library (`ESP32_BASE_DIR`); without it, build the legacy sketch with `./scripts/build_firmware.sh legacy`.
- The legacy build needs a `.env` (copy `.env.example`) for the `PLACEHOLDER_*` defaults.

## State after a restart

Live levels and history are in memory and start empty after a restart. Names, thresholds, channels, rules and alert history are in `data/soundspy.db`; nodes reappear as soon as their retained status is read from the broker.
