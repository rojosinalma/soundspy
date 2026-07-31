# Soundspy v2.0.0 — Development Plan

## Goal

Introduce a full notification system with multi-channel delivery, flexible alert rules,
per-node and global scopes, and migrate all persistent state from JSON files to SQLite.
Current dashboard functionality must remain intact at release.

---

## Branch

`v2` — incremental commits, possible release candidates (`v2.0.0-rc.1`, etc.).
Merge to `main` and tag `v2.0.0` when complete.

---

## File Structure (target)

```
dashboard/
  app.py                  — Flask app factory, SocketIO, routes, MQTT wiring
  node_state.py           — In-memory node data, history, EMA, heartbeat logic
  notifications.py        — Alert evaluation engine, channel dispatchers
  db.py                   — SQLite schema, migrations, all DB access
  helpers.py              — Shared utilities (dBFS math, A-weighting, formatting)
  templates/
    dashboard.html        — Main real-time dashboard (unchanged functionality)
    settings.html         — Notification + alert configuration page
  Dockerfile.dashboard
  requirements.txt
```

The `threshold_monitor.py` and its `Dockerfile` are deleted. The monitor service
is removed from `docker-compose.yml`. The ntfy container remains optional.

---

## Database — SQLite at `/app/data/soundspy.db`

### Migration on first startup

On boot, `db.py` checks if the DB exists. If not (or if tables are empty), it reads
`node_names.json` and `node_thresholds.json` and imports them. The JSON files are
left in place but no longer written to after migration.

### Tables

**nodes**
```sql
chip_id       TEXT PRIMARY KEY
display_name  TEXT NOT NULL
threshold     REAL DEFAULT -20.0
created_at    INTEGER
```

**alert_rules**
```sql
id            INTEGER PRIMARY KEY AUTOINCREMENT
name          TEXT NOT NULL
scope         TEXT NOT NULL  -- 'global' | 'node'
node_id       TEXT           -- NULL if global
band          TEXT           -- 'overall' | 'sub_bass' | 'bass' | 'low_mid' | 'mid' | 'high_mid' | 'high'
threshold     REAL NOT NULL
condition     TEXT NOT NULL  -- 'instant' | 'sustained' | 'repeated'
-- sustained: level > threshold continuously for `duration_seconds`
-- repeated:  threshold broken `repeat_count` times within `repeat_window_seconds`
duration_seconds     INTEGER  -- for 'sustained'
repeat_count         INTEGER  -- for 'repeated'
repeat_window_seconds INTEGER -- for 'repeated'
cooldown_mode   TEXT NOT NULL  -- 'every' | 'cooldown' | 'count'
-- every:    fire on every breach (no cooldown)
-- cooldown: fire once, then silence for `cooldown_seconds`
-- count:    fire once every `cooldown_count` breaches
cooldown_seconds  INTEGER
cooldown_count    INTEGER
urgency       TEXT NOT NULL DEFAULT 'warning'  -- 'info' | 'warning' | 'critical'
enabled       INTEGER NOT NULL DEFAULT 1
created_at    INTEGER
```

**notification_channels**
```sql
id            INTEGER PRIMARY KEY AUTOINCREMENT
platform      TEXT NOT NULL  -- 'telegram' | 'discord' | 'ntfy' | 'pushover' | 'email'
label         TEXT NOT NULL  -- human-readable name e.g. "Studio Telegram"
env_key       TEXT NOT NULL  -- e.g. 'TELEGRAM_BOT_TOKEN', 'TELEGRAM_BOT_TOKEN_1'
config        TEXT NOT NULL  -- JSON blob: platform-specific non-secret config
                             -- e.g. {"chat_id": "123456"} for Telegram
                             -- e.g. {"webhook_url_env": "DISCORD_WEBHOOK_1"} for Discord
enabled       INTEGER NOT NULL DEFAULT 1
created_at    INTEGER
```

**alert_rule_channels**  (many-to-many: which channels fire for which rule)
```sql
rule_id       INTEGER REFERENCES alert_rules(id) ON DELETE CASCADE
channel_id    INTEGER REFERENCES notification_channels(id) ON DELETE CASCADE
PRIMARY KEY (rule_id, channel_id)
```

**alert_history**
```sql
id            INTEGER PRIMARY KEY AUTOINCREMENT
rule_id       INTEGER REFERENCES alert_rules(id)
node_id       TEXT
band          TEXT
level         REAL
scope         TEXT   -- 'global' | 'node'
channels_fired TEXT  -- JSON list of channel labels
fired_at      INTEGER
```

---

## Credentials — `.env` convention

Secrets never touch the DB. The DB stores only the env var key name.

| Platform   | Env var pattern                        | Notes                              |
|------------|----------------------------------------|------------------------------------|
| Telegram   | `TELEGRAM_BOT_TOKEN`, `_1`, `_2` ...  | `config` stores `chat_id`         |
| Discord    | `DISCORD_WEBHOOK`, `_1`, `_2` ...     | Full webhook URL in env            |
| ntfy       | `NTFY_URL`, `_1`, `_2` ...            | Full URL including topic           |
| Pushover   | `PUSHOVER_TOKEN` + `PUSHOVER_USER`    | Both required, suffixed together   |
| Email      | `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS` | `config` stores to/from/port       |

Multiple instances of the same platform use `_1`, `_2` suffixes.
Default (no suffix) is always tried first.

---

## Alert Engine — `notifications.py`

### Evaluation (called per MQTT data message, after node state update)

```
for each enabled alert_rule:
  if rule.scope == 'node' and rule.node_id != current_node: skip
  get level = band value or overall from current payload
  if level <= rule.threshold: reset breach state; continue

  // level exceeds threshold
  if condition == 'instant':
    fire if cooldown allows
  if condition == 'sustained':
    start/continue timer; fire when timer >= duration_seconds
  if condition == 'repeated':
    append breach timestamp; prune older than repeat_window_seconds
    fire if len(breaches) >= repeat_count and cooldown allows
```

Breach state is in-memory (resets on restart). History is written to `alert_history`.

### Cooldown logic
- `every`: always fire
- `cooldown`: track `last_fired_at` per rule; gate on `now - last_fired_at >= cooldown_seconds`
- `count`: track `breach_count` per rule; fire when `breach_count % cooldown_count == 0`

### Channel dispatch
Each enabled channel for the rule fires concurrently (asyncio or threads).
Message format includes: node name (or "Global"), band, level, threshold, rule name, urgency.
Global-scope alerts that were triggered by a specific node say so in the message body.

---

## Settings Page — `/settings`

Single HTML page served by Flask. Sections:

1. **Notification Channels** — add/edit/delete/enable channels per platform.
   Shows env var key expected, lets user set non-secret config (chat_id, etc.).
   Tests channel with a "Send test" button.

2. **Alert Rules** — add/edit/delete/enable rules.
   Form: name, scope (global/node selector), band, threshold, condition + params,
   cooldown, urgency, channel assignments.

3. **Alert History** — last N alerts fired, with timestamp, node, rule, channels.

Cogwheel icon in dashboard header (top right) links to `/settings`.
Settings page has a "← Dashboard" back link.

---

## Channels — Implementation Priority

### Phase 1 (v2.0.0)
- **Telegram** — Bot API `sendMessage` to `chat_id`
- **Discord** — Webhook POST with embed

### Phase 2 (v2.0.0 or shortly after)
- **ntfy** — HTTP POST (replaces current monitor behaviour)
- **Pushover** — API POST

### Phase 3 (post v2.0.0)
- **Email** — SMTP with `smtplib`

---

## Work Phases

### Phase 0 — Cleanup & branch setup ✓
- [x] Create `v2` branch
- [ ] Delete `threshold_monitor.py`, `Dockerfile` (monitor), remove monitor service from compose
- [ ] Remove ntfy service from compose (keep as optional comment)

### Phase 1 — Refactor dashboard into modules
- [ ] Extract `db.py` — schema, migration from JSONs
- [ ] Extract `helpers.py` — dBFS math, A-weighting, formatting
- [ ] Extract `node_state.py` — node data structures, history, heartbeat
- [ ] Extract `notifications.py` — alert engine skeleton (no channels yet)
- [ ] `app.py` becomes the thin Flask entrypoint wiring everything together
- [ ] All existing functionality verified working

### Phase 2 — SQLite migration
- [ ] Node names read/written from DB (migrated from JSON on first boot)
- [ ] Thresholds read/written from DB
- [ ] API endpoints updated to use DB

### Phase 3 — Alert engine
- [ ] `alert_rules` CRUD API + DB
- [ ] Breach state tracking in `node_state.py`
- [ ] Alert evaluation wired into MQTT message handler
- [ ] `alert_history` written on fire

### Phase 4 — Notification channels
- [ ] Telegram dispatcher
- [ ] Discord dispatcher
- [ ] ntfy dispatcher
- [ ] Pushover dispatcher
- [ ] Email dispatcher (stretch)

### Phase 5 — Settings UI
- [ ] `/settings` page
- [ ] Channels CRUD
- [ ] Rules CRUD
- [ ] Alert history table
- [ ] Cogwheel in dashboard header

### Phase 6 — Polish & release
- [ ] End-to-end test all existing functionality
- [ ] CHANGELOG.md entry for v2.0.0
- [ ] Merge `v2` → `main`
- [ ] Tag v2.0.0

---

## Key Decisions Log

| Decision | Choice | Reason |
|---|---|---|
| DB engine | SQLite at `/app/data/soundspy.db` | Portable, no daemon, fits self-hosted scope |
| Secrets storage | `.env` only, DB stores key names | Avoids credential exposure in DB file |
| Service topology | Single container, multiple Python modules | Avoids inter-service coordination overhead |
| Multiple channel instances | `PLATFORM_TOKEN_1`, `_2` suffix pattern | Simple, .env-native, no extra DB columns |
| Notification scope | Global default, per-node optional, both fire if both set | Maximum flexibility |
| Urgency | Arbitrary label set by user per rule | No hardcoded tiers |
| Branch strategy | `v2` branch, RC tags, merge to main at v2.0.0 | Safe checkpoint, backwards compat wished |
| Settings navigation | Cogwheel in dashboard header → `/settings` | Unobtrusive, expandable later |
| Existing state files | JSON files kept post-migration, not written to | Safe rollback, no data loss |
