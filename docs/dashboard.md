# Dashboard

The dashboard is a Flask + Flask-SocketIO application (`dashboard/app.py`) packaged as `ghcr.io/rojosinalma/soundspy`. It subscribes to the nodes' MQTT topics, keeps live state and an hour of history per node in memory, relays live audio, evaluates alert rules and serves the web UI on port 8091.

<p align="center">
  <img src="https://raw.githubusercontent.com/rojosinalma/soundspy/main/assets/screenshot.png" alt="soundspy dashboard" width="100%"/>
</p>

## Configuration

Environment variables (set through `.env`, read by `docker-compose.yml`):

| Variable | Default | Meaning |
|---|---|---|
| `MQTT_HOST` / `MQTT_PORT` | `localhost` / `1883` | Broker the dashboard connects to |
| `MQTT_USER` / `MQTT_PASS` | empty | Broker credentials; leave empty for anonymous |
| `MQTT_PREFIX` | `esp32` | Topic prefix the nodes publish under (`<prefix>/<chip_id>/…`) |
| `DASHBOARD_PORT` | `8091` | Host port mapped to the container's 8091 |
| `DB_PATH` | `/app/data/soundspy.db` | SQLite file; `./data` is mounted at `/app/data` |

Everything else (node names, thresholds, channels, rules) is edited in the UI and stored in the database.

## Node discovery and state

- A node is accepted when its retained `status` message carries `app: "soundspy"`; other boards on the same broker are ignored. A known node that drops to recovery or whose LWT fires (`online: false`) stays listed.
- **Online** means a `data` message within the last 10 s; a sleeping node or one in recovery counts as online while its status is fresher than 90 s.
- The display name follows the board's hostname and can be overridden by clicking it in the card (`POST /api/node/rename`).
- Levels arrive up to 50× per second and are averaged in the linear power domain into one history point per second, 3600 points per node, in memory only.

## What you see

Per node card: overall level (dBA by default, click the unit to toggle dBFS), the six-band spectrum as bars or a wave with peak markers, a threshold marker you can drag, sleep/recovery indicators, firmware version and IP, a gain knob (0–10×), sleep/wake and reboot buttons, a listen button for live audio, and a history chart with selectable range. Zones: green below −20 dBFS, yellow to −10, red above.

The log panel shows the nodes' `log` messages and dashboard events, with pause-on-scroll, clear and fullscreen; the last 200 entries are replayed to a browser that connects later.

`/settings` manages notification channels, alert rules and the alert history.

## Live audio

`dashboard/audio_relay.py` keeps one relay thread per online node. While at least one browser is connected, each relay opens the node's PCM TCP port (from `app_status.stream_port`), reads the JSON header and then 50 ms chunks of s16le mono, and emits them as `audio_data` Socket.IO events (base64). With no browser connected the relays idle and the nodes stream nothing. At most 16 relays run at once. `GET /api/relays` shows their state.

## Alerts

Channels (`/settings` → Channels): Telegram, Discord webhook, ntfy, Pushover, email (SMTP). Tokens are stored in the `notification_channels` table and can be tested with the **Test** button.

Rules (`/settings` → Rules): scope *global* or one node; band *overall* or one of the six; a threshold in dBFS; a condition — *instant*, *sustained* for N seconds, or *repeated* N times within a window; a cooldown either time-based (seconds) or count-based (every Nth breach); an urgency that maps to the channel's priority. Each rule fans out to the channels you tick. Every firing is logged in the alert history.

## HTTP API

| Method, path | Purpose |
|---|---|
| `GET /api/nodes` | Live nodes with status, current levels and per-node thresholds |
| `GET /api/history/<node_id>` | The node's 1-second history |
| `POST /api/node/rename` `{chip_id, name}` | Set the display name |
| `POST /api/node/threshold` `{chip_id, value}` | Set the card threshold (−80…0 dBFS) |
| `POST /api/control` `{node_id, command}` | `{"gain": 5}`, `{"sleep": true}`, `{"wake": true}` or `{"reboot": true}` → published on the node's `cmd` topic |
| `POST /api/disconnect` `{node_id}` | Forget a node's live state |
| `GET/POST /api/channels`, `DELETE /api/channels/<id>`, `POST /api/channels/<id>/test` | Notification channels |
| `GET/POST /api/rules`, `DELETE /api/rules/<id>` | Alert rules (`channel_ids` list on POST) |
| `GET /api/alert-history?limit=100` | Fired alerts |
| `GET /api/relays` | Audio relay state |

Socket.IO events to the browser: `node_status`, `sensor_data`, `hw_gain`, `node_log`, `audio_data`.

## Running without Docker

```bash
cd dashboard && pip install -r requirements.txt
MQTT_HOST=192.168.1.10 DB_PATH=./data/soundspy.db python app.py
```
