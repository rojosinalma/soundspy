# Dashboard

Access the dashboard at `http://<server-ip>:8091` (or `https://soundspy.silver.local` if Traefik is configured via the override file).

## Features

### Real-Time Monitoring

Each active node gets a card showing:
- Overall level meter (dBA by default, click the unit label to toggle to dBFS)
- 6-band EQ spectrum — switchable between bar and wave visualization modes
- Sleep/wake state indicator
- Firmware version and IP address

Nodes are auto-discovered: any ESP32 publishing to `soundspy/<chip_id>/data` appears automatically without any manual configuration.

### Node Naming

New nodes are auto-named `node-1`, `node-2`, etc. Click the name in a node card to rename it inline. Names persist across restarts in `data/node_names.json`.

### Live Audio Streaming

The dashboard streams live PCM audio from each node via WebSocket. Click the audio icon on a node card to listen. Latency is under 100 ms. Audio has gain applied (same as the published level data).

### Remote Control

Per-node controls available from the dashboard:
- **Gain slider** — adjusts capture gain (0–10×) sent to the node via MQTT
- **Sleep / Wake** — stops I2S on the node to reduce power; MQTT remains connected so the node stays reachable
- **OTA update** — upload a firmware binary and push it to a specific node wirelessly
- **Reboot** — sends a reboot command via MQTT

### Historical Data

Each node maintains a 1-hour in-memory history (3600 samples). The history chart supports selectable time ranges. Level values are averaged in the linear power domain before display to preserve perceptual accuracy.

### Visualization Modes

- **Bar mode** — standard spectrum bar chart
- **Wave mode** — continuous waveform overlay

Both chart types use colored background zones:
- Green (−80 to −20 dBFS): quiet / ambient
- Yellow (−20 to −10 dBFS): noticeable
- Red (−10 to 0 dBFS): loud / clipping

### Live Logs

A logs panel shows remote log messages from all nodes, split into per-node sidebars and an app/system tab. Firmware publishes log events over MQTT to `soundspy/<chip_id>/log` and boot reports to `soundspy/<chip_id>/boot`.

### Push Notifications

The threshold monitor service watches the `soundspy/+/data` topic and sends an ntfy push notification when bass exceeds the configured threshold. Default threshold is −20 dBA with a 5-minute cooldown. Configure via `FREQ_THRESHOLD_DBFS` and `COOLDOWN_SECONDS` in `.env`.

## Calibration and Threshold

### dBFS vs. dBA

The dashboard displays levels in dBA by default. dBA is computed by applying A-weighting offsets to the per-band dBFS values. The A-weighting offset for each band is cached after the first calculation. Click the unit label on any level display to toggle between dBA and dBFS.

### Alert Threshold

The alert threshold is stored internally in dBFS and defaults to −20 dBFS (approximately −20 dBA for typical broadband noise). It is set via `FREQ_THRESHOLD_DBFS` in `.env` and is applied by `threshold_monitor.py`.

Each node card shows a threshold line on the level meter. The position reflects the dBFS value; the displayed label switches with the dBFS/dBA toggle.

### Gain Adjustment

Increase gain if the displayed levels seem too low for your environment. Decrease it if the meter is clipping (reaching 0 dBFS) during normal use. Gain changes take effect immediately on the node; no rebuild or reflash is needed.
