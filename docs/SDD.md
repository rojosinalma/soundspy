# soundspy — software design document

## Purpose

soundspy measures sound levels in several rooms at once with cheap ESP32 nodes and shows them live in one place. Each node meters its microphone in six frequency bands plus an overall level and publishes the numbers over MQTT; the dashboard turns that into live meters, spectrum, history, listen-in audio and alerts. I use it to know when a rehearsal or a mix is loud enough to be heard through a wall; it fits any room you want to keep an ear on from elsewhere.

## Architecture

```
 ESP32 node (firmware/)                 MQTT broker              dashboard (dashboard/)              browser
 ┌───────────────────────┐   status/data/log  ┌──────┐  subscribe  ┌──────────────────────────┐  Socket.IO ┌────────┐
 │ I2S capture task      │ ─────────────────▶ │      │ ──────────▶ │ app.py  (MQTT, HTTP, SIO)│ ─────────▶ │ UI     │
 │ 6× band-pass + RMS    │ ◀───────────────── │      │ ◀────────── │ node_state.py (live/hist)│ ◀───────── │        │
 │ PCM TCP server :8181  │        cmd         └──────┘   publish   │ notifications.py (rules) │  HTTP API  │        │
 │ Esp32Base: WiFi, NVS, │                                         │ db.py (SQLite)           │            └────────┘
 │  portal, OTA, MQTT    │ ◀──── raw s16le PCM over TCP ────────── │ audio_relay.py           │
 └───────────────────────┘                                         └──────────────────────────┘
```

### Node firmware (`firmware/`)

- `soundspy.ino` is a reporter: it calls `Base.begin("soundspy", APP_VERSION)`, registers the status hook, the `cmd` handler and `GET/POST /api/audio`, and every `publish_ms` publishes the levels on `<prefix>/<chip_id>/data`.
- `audio.cpp` owns the I2S channel (ESP-IDF `i2s_std`, 44.1 kHz, 32-bit slots, left slot by default on GPIO 32/25/33). A capture task applies gain, runs two cascaded biquad band-passes per band and accumulates power; `takeLevels()` hands the RMS since the last call to `loop()`. A watchdog reinitialises the bus after ~3.5 s of digital silence (up to three times). A second task serves one TCP client with raw PCM from a ring buffer that is allocated only while a client is connected.
- Settings (`gain`, `publish_ms`, `stream_port`, `awake`, `slot`) live in NVS namespace `sspy`, are validated in `Settings::apply`, and are echoed in the retained status under `app_status`.
- Everything that is not audio comes from the Esp32Base library: configuration in NVS with a captive setup portal, WiFi management, a boot guard with recovery fallback, the `/sys` portal and `POST /api` command endpoint, firmware upload, MQTT over mqtt/mqtts/ws/wss with a retained status and LWT, and log publishing.

### Legacy firmware (`node_firmware/`)

The 1.7.x standalone sketch and its `recovery_firmware/`. It implements the same metering with the older `driver/i2s.h` API, publishes on `soundspy/<chip_id>/…`, pushes audio as base64 JSON over a WebSocket to the dashboard host and takes OTA URLs over MQTT. It stays in the tree so boards flashed with it keep a buildable source and because it needs only public libraries, which is what CI compiles.

### Dashboard (`dashboard/`)

- `app.py` — Flask app and Socket.IO server (threading mode), the paho-mqtt client in a thread, the HTTP API and the fan-out of `node_status`, `sensor_data`, `hw_gain`, `node_log` and `audio_data` events.
- `node_state.py` — in-memory live state per node: last data/heartbeat time, current levels, 3600 one-second history points (linear-power averages), firmware version, hostname, IP, gain, sleeping/recovery flags; the online decision.
- `audio_relay.py` — one thread per node that pulls the PCM TCP stream while any browser is connected and emits 50 ms chunks; bounded to 16 relays; reconnects after 5 s.
- `notifications.py` — rule evaluation on every `data` message (instant / sustained / repeated; time- or count-based cooldown) and dispatch to Telegram, Discord, ntfy, Pushover and SMTP in a thread per firing.
- `db.py` — SQLite schema, migrations and accessors.
- `templates/dashboard.html`, `templates/settings.html` — the UI, vanilla JS with Chart.js and the Web Audio API; no build step.

## Data model and storage

SQLite at `DB_PATH` (`/app/data/soundspy.db`, mounted from `./data`), created by `db.init_db()` with `CREATE TABLE IF NOT EXISTS` and small in-code migrations:

| Table | Columns | Role |
|---|---|---|
| `nodes` | `chip_id` PK, `display_name`, `threshold` (dBFS, default −20), `created_at` | Names and card thresholds; the name follows the board hostname until renamed |
| `alert_rules` | `id`, `name`, `scope` (`global`/`node`), `node_id`, `band` (`overall` or a band key), `threshold`, `condition` (`instant`/`sustained`/`repeated`), `duration_seconds`, `repeat_count`, `repeat_window_seconds`, `cooldown_mode` (`cooldown`/`count`), `cooldown_seconds`, `cooldown_count`, `urgency`, `enabled`, `created_at` | Alert rules |
| `notification_channels` | `id`, `platform`, `label`, `config` (JSON incl. the secret), `enabled`, `created_at` | Delivery targets |
| `alert_rule_channels` | `rule_id`, `channel_id` (both cascade) | Rule → channels |
| `alert_history` | `id`, `rule_id`, `node_id`, `band`, `level`, `scope`, `channels_fired`, `fired_at` | Every firing |

On first start `db._migrate_from_json()` imports `node_names.json` / `node_thresholds.json` from `data/` if they exist. Live levels and history are memory only (`node_state`); the last 200 log lines are a deque in `app.py`.

## Key flows

**Node → dashboard.** The node publishes a retained `status` on connect and on every settings change (`app`, `version`, `hostname`, `ip`, `role`, `app_status`), `data` every `publish_ms`, `log` lines as they happen; the broker publishes `{"online": false}` as LWT. `app.py` accepts a node once a status with `app == "soundspy"` arrives, upserts its name, retargets its audio relay (`ip`, `app_status.stream_port`, active when online, awake and not in recovery) and emits `node_status`. Each `data` updates `node_state`, emits `sensor_data` and runs `notifications.evaluate`.

**Online decision** (`node_state.get_node_status`): offline if the LWT said so; a sleeping or recovering node is online while its status is < 90 s old; otherwise online means a `data` message < 10 s ago. The browser applies the same staleness check with its own clock, so clock skew between host and browser cannot flap the cards.

**Control.** The UI posts `/api/control`; `to_node_cmd` maps it to `{"cmd":"gain"|"sleep"|"wake"|"reboot", …}` on `<prefix>/<chip_id>/cmd`. The node applies the patch through `Settings::apply`, saves it and republishes its status, which is what updates every open browser.

**Live audio.** When a browser connects, `audio_relay.listener_connected()` lets the relays run. A relay opens `ip:stream_port`, reads the JSON header, then loops reading 4410-byte chunks (50 ms) and emitting `audio_data` (base64). The browser decodes into the Web Audio API. When the last browser leaves, the loops exit, the node sees the socket close and frees its ring buffer.

**Alerts.** For each enabled rule matching the node, the band's level is compared to the threshold. Instant rules fire at once, sustained rules once the level has stayed above for `duration_seconds`, repeated rules after `repeat_count` breaches inside `repeat_window_seconds`; the cooldown then gates re-firing by time or by breach count. A firing dispatches to the rule's channels in a thread and is logged.

**Firmware update.** Upload a `.bin` in the node's `/sys` portal (or `POST /api` with `op=flash`); Esp32Base writes the application slot and reboots; the boot guard rolls back when the new build does not confirm itself.

## Configuration surface

- Dashboard: `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASS`, `MQTT_PREFIX`, `DB_PATH`, `DASHBOARD_PORT` (compose) — see `docs/dashboard.md`. Everything else is in the database and edited in the UI.
- Node: WiFi, broker URL, admin password and hostname in the setup portal / `/sys`; audio settings over `cmd` or `/api/audio` — see `docs/firmware.md`.
- Build: `ESP32_BASE_DIR`, `FQBN`, `BUILD_DIR` for `scripts/build_firmware.sh`; `.env` for the legacy build.

## Decisions and rationale

- **Nodes report, the dashboard thinks.** Thresholds, history, alerts and names live in the dashboard so a node is a dumb, interchangeable sensor: one binary for every board, no per-node build.
- **Metering on the node, not the audio.** Six RMS bands at 20–50 Hz fit in a 256-byte JSON message; streaming audio from every node all the time would not. Audio is pulled on demand and only while someone listens.
- **Pull-based audio over plain TCP.** The dashboard connects to the node, so a node never has to know where the dashboard is, and an idle node spends neither CPU nor RAM on a stream nobody hears.
- **Retained status + LWT instead of heartbeats.** The broker keeps the last status, so a freshly started dashboard knows every node immediately, and the LWT gives an authoritative offline.
- **Shared platform library.** WiFi, portal, OTA, boot guard and MQTT plumbing are the same for every ESP32 project, so they live in Esp32Base and the sketch stays at the audio code.
- **SQLite in the container's data volume.** Small write volume, one process, no server to run.
- **Threads, not an async framework.** Flask-SocketIO in threading mode with a few daemon threads (MQTT loop, relays, dispatch) is enough for dozens of nodes and keeps the code plain.
- **Bounded memory everywhere.** Fixed-size history deques, a 200-line log deque, a 16-relay cap, a PCM ring that exists only while streaming.

## Current scope

Today soundspy runs with ESP32-WROOM DevKits and I2S MEMS mics, one MQTT broker, one dashboard instance without authentication of its own (put it behind your reverse proxy if it is reachable from outside your network), and in-memory history of one hour. Band edges are fixed in the firmware. These are the current shape of the project, not boundaries.

## Operations

- **Logs.** `docker logs -f soundspy`: broker connection, every accepted status (`[status] …`), relay events (`[relay] …`), alert dispatch and MQTT errors. Node logs arrive in the dashboard's log panel and on `/sys` → logs on the node.
- **Health.** `GET /health` returns 200 with the version, the MQTT link state and the node count (the image's `HEALTHCHECK` polls it every 30 s). `GET /api/nodes` lists the nodes and their online state; `GET /api/relays` the audio relays. A node answers `GET /` with its version.
- **Persistence and backup.** Everything persistent is `data/soundspy.db`; copy that file.
- **Container user.** The image runs as uid 1000 (`soundspy`), so the directory bound to `/app/data` must be writable by that uid (`chown -R 1000:1000 data`), or set `user:` in compose to the owner of your data directory.
- **Upgrade.** `docker compose pull && docker compose up -d` for the dashboard (the schema is additive, migrations run on start); upload the new `.bin` to each node's `/sys` portal for the firmware. Versions: `VERSION`, `APP_VERSION`, `DASHBOARD_VERSION` are bumped together by `scripts/bump_version.sh`; a changed `VERSION` on `main` creates the tag and the GitHub release and triggers the firmware and image builds for it.
