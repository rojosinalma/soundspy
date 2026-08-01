import os
import json
import sqlite3
import time
from contextlib import contextmanager

DB_PATH = os.environ.get("DB_PATH", "/app/data/soundspy.db")
NODE_NAMES_FILE = "/app/data/node_names.json"
NODE_THRESHOLDS_FILE = "/app/data/node_thresholds.json"

SCHEMA = """
CREATE TABLE IF NOT EXISTS nodes (
    chip_id      TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    threshold    REAL NOT NULL DEFAULT -20.0,
    created_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS alert_rules (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    name                  TEXT NOT NULL,
    scope                 TEXT NOT NULL DEFAULT 'global',
    node_id               TEXT,
    band                  TEXT NOT NULL DEFAULT 'overall',
    threshold             REAL NOT NULL DEFAULT -20.0,
    condition             TEXT NOT NULL DEFAULT 'instant',
    duration_seconds      INTEGER,
    repeat_count          INTEGER,
    repeat_window_seconds INTEGER,
    cooldown_mode         TEXT NOT NULL DEFAULT 'cooldown',
    cooldown_seconds      INTEGER DEFAULT 300,
    cooldown_count        INTEGER,
    urgency               TEXT NOT NULL DEFAULT 'warning',
    enabled               INTEGER NOT NULL DEFAULT 1,
    created_at            INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_channels (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    platform   TEXT NOT NULL,
    label      TEXT NOT NULL,
    config     TEXT NOT NULL DEFAULT '{}',
    enabled    INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS alert_rule_channels (
    rule_id    INTEGER NOT NULL REFERENCES alert_rules(id) ON DELETE CASCADE,
    channel_id INTEGER NOT NULL REFERENCES notification_channels(id) ON DELETE CASCADE,
    PRIMARY KEY (rule_id, channel_id)
);

CREATE TABLE IF NOT EXISTS alert_history (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id       INTEGER REFERENCES alert_rules(id),
    node_id       TEXT,
    band          TEXT,
    level         REAL,
    scope         TEXT,
    channels_fired TEXT,
    fired_at      INTEGER NOT NULL
);
"""


@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with get_conn() as conn:
        conn.executescript(SCHEMA)
        _migrate_schema(conn)
    _migrate_from_json()


def _migrate_schema(conn):
    cols = [r[1] for r in conn.execute("PRAGMA table_info(notification_channels)").fetchall()]
    if "env_key" in cols:
        # Move any existing env_key values into config, then drop the column
        rows = conn.execute("SELECT id, env_key, config FROM notification_channels").fetchall()
        for row in rows:
            cfg = json.loads(row["config"])
            if row["env_key"] and "token" not in cfg:
                cfg["token"] = ""  # env_key was a var name, not the actual secret — can't migrate value
            conn.execute("UPDATE notification_channels SET config=? WHERE id=?",
                         (json.dumps(cfg), row["id"]))
        # SQLite doesn't support DROP COLUMN before 3.35 — recreate the table
        conn.executescript("""
            CREATE TABLE notification_channels_new (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                platform   TEXT NOT NULL,
                label      TEXT NOT NULL,
                config     TEXT NOT NULL DEFAULT '{}',
                enabled    INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL
            );
            INSERT INTO notification_channels_new (id, platform, label, config, enabled, created_at)
                SELECT id, platform, label, config, enabled, created_at FROM notification_channels;
            DROP TABLE notification_channels;
            ALTER TABLE notification_channels_new RENAME TO notification_channels;
        """)


def _migrate_from_json():
    with get_conn() as conn:
        existing = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        if existing > 0:
            return

    names = {}
    thresholds = {}

    try:
        with open(NODE_NAMES_FILE) as f:
            names = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    try:
        with open(NODE_THRESHOLDS_FILE) as f:
            thresholds = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    if not names:
        return

    now = int(time.time())
    with get_conn() as conn:
        for chip_id, display_name in names.items():
            threshold = thresholds.get(chip_id, -20.0)
            conn.execute(
                "INSERT OR IGNORE INTO nodes (chip_id, display_name, threshold, created_at) VALUES (?, ?, ?, ?)",
                (chip_id, display_name, threshold, now)
            )
    print(f"[db] migrated {len(names)} nodes from JSON", flush=True)


# --- Node helpers ---

def get_all_nodes() -> dict:
    with get_conn() as conn:
        rows = conn.execute("SELECT chip_id, display_name, threshold FROM nodes").fetchall()
    return {row["chip_id"]: {"display_name": row["display_name"], "threshold": row["threshold"]} for row in rows}


def get_node(chip_id: str) -> dict | None:
    with get_conn() as conn:
        row = conn.execute(
            "SELECT chip_id, display_name, threshold FROM nodes WHERE chip_id = ?", (chip_id,)
        ).fetchone()
    return dict(row) if row else None


def upsert_node(chip_id: str, display_name: str | None = None, threshold: float | None = None):
    now = int(time.time())
    with get_conn() as conn:
        existing = conn.execute("SELECT chip_id, display_name, threshold FROM nodes WHERE chip_id = ?", (chip_id,)).fetchone()
        if existing:
            if display_name is not None:
                conn.execute("UPDATE nodes SET display_name = ? WHERE chip_id = ?", (display_name, chip_id))
            if threshold is not None:
                conn.execute("UPDATE nodes SET threshold = ? WHERE chip_id = ?", (threshold, chip_id))
        else:
            # Auto-assign name
            if display_name is None:
                rows = conn.execute("SELECT display_name FROM nodes WHERE display_name LIKE 'node-%'").fetchall()
                nums = []
                for r in rows:
                    try:
                        nums.append(int(r["display_name"].split("-")[1]))
                    except (IndexError, ValueError):
                        pass
                display_name = f"node-{max(nums, default=0) + 1}"
            conn.execute(
                "INSERT INTO nodes (chip_id, display_name, threshold, created_at) VALUES (?, ?, ?, ?)",
                (chip_id, display_name, threshold if threshold is not None else -20.0, now)
            )


def get_node_name(chip_id: str) -> str:
    node = get_node(chip_id)
    if node:
        return node["display_name"]
    upsert_node(chip_id)
    return get_node(chip_id)["display_name"]


# --- Threshold helpers ---

def set_node_threshold(chip_id: str, value: float):
    upsert_node(chip_id, threshold=value)


# --- Alert rules ---

def get_alert_rules(enabled_only: bool = False) -> list:
    query = "SELECT * FROM alert_rules"
    if enabled_only:
        query += " WHERE enabled = 1"
    with get_conn() as conn:
        return [dict(r) for r in conn.execute(query).fetchall()]


def upsert_alert_rule(data: dict) -> int:
    now = int(time.time())
    with get_conn() as conn:
        if "id" in data and data["id"]:
            conn.execute("""
                UPDATE alert_rules SET name=?, scope=?, node_id=?, band=?, threshold=?,
                condition=?, duration_seconds=?, repeat_count=?, repeat_window_seconds=?,
                cooldown_mode=?, cooldown_seconds=?, cooldown_count=?, urgency=?, enabled=?
                WHERE id=?
            """, (data["name"], data["scope"], data.get("node_id"), data["band"], data["threshold"],
                  data["condition"], data.get("duration_seconds"), data.get("repeat_count"),
                  data.get("repeat_window_seconds"), data["cooldown_mode"],
                  data.get("cooldown_seconds"), data.get("cooldown_count"),
                  data["urgency"], data.get("enabled", 1), data["id"]))
            return data["id"]
        else:
            cur = conn.execute("""
                INSERT INTO alert_rules (name, scope, node_id, band, threshold, condition,
                duration_seconds, repeat_count, repeat_window_seconds, cooldown_mode,
                cooldown_seconds, cooldown_count, urgency, enabled, created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (data["name"], data.get("scope", "global"), data.get("node_id"), data.get("band", "overall"),
                  data["threshold"], data.get("condition", "instant"), data.get("duration_seconds"),
                  data.get("repeat_count"), data.get("repeat_window_seconds"),
                  data.get("cooldown_mode", "cooldown"), data.get("cooldown_seconds", 300),
                  data.get("cooldown_count"), data.get("urgency", "warning"), data.get("enabled", 1), now))
            return cur.lastrowid


def delete_alert_rule(rule_id: int):
    with get_conn() as conn:
        conn.execute("DELETE FROM alert_rules WHERE id = ?", (rule_id,))


# --- Notification channels ---

def get_channels(enabled_only: bool = False) -> list:
    query = "SELECT * FROM notification_channels"
    if enabled_only:
        query += " WHERE enabled = 1"
    with get_conn() as conn:
        rows = conn.execute(query).fetchall()
    result = []
    for r in rows:
        d = dict(r)
        d["config"] = json.loads(d["config"])
        result.append(d)
    return result


def upsert_channel(data: dict) -> int:
    now = int(time.time())
    config_json = json.dumps(data.get("config", {}))
    with get_conn() as conn:
        if "id" in data and data["id"]:
            conn.execute("""
                UPDATE notification_channels SET platform=?, label=?, config=?, enabled=?
                WHERE id=?
            """, (data["platform"], data["label"], config_json, data.get("enabled", 1), data["id"]))
            return data["id"]
        else:
            cur = conn.execute("""
                INSERT INTO notification_channels (platform, label, config, enabled, created_at)
                VALUES (?,?,?,?,?)
            """, (data["platform"], data["label"], config_json, data.get("enabled", 1), now))
            return cur.lastrowid


def delete_channel(channel_id: int):
    with get_conn() as conn:
        conn.execute("DELETE FROM notification_channels WHERE id = ?", (channel_id,))


def set_rule_channels(rule_id: int, channel_ids: list):
    with get_conn() as conn:
        conn.execute("DELETE FROM alert_rule_channels WHERE rule_id = ?", (rule_id,))
        for cid in channel_ids:
            conn.execute("INSERT INTO alert_rule_channels (rule_id, channel_id) VALUES (?,?)", (rule_id, cid))


def get_rule_channels(rule_id: int) -> list:
    with get_conn() as conn:
        rows = conn.execute("""
            SELECT nc.* FROM notification_channels nc
            JOIN alert_rule_channels arc ON arc.channel_id = nc.id
            WHERE arc.rule_id = ?
        """, (rule_id,)).fetchall()
    result = []
    for r in rows:
        d = dict(r)
        d["config"] = json.loads(d["config"])
        result.append(d)
    return result


# --- Alert history ---

def log_alert(rule_id: int | None, node_id: str, band: str, level: float, scope: str, channels_fired: list):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO alert_history (rule_id, node_id, band, level, scope, channels_fired, fired_at)
            VALUES (?,?,?,?,?,?,?)
        """, (rule_id, node_id, band, level, scope, json.dumps(channels_fired), int(time.time())))


def get_alert_history(limit: int = 100) -> list:
    with get_conn() as conn:
        rows = conn.execute("""
            SELECT ah.*, ar.name as rule_name FROM alert_history ah
            LEFT JOIN alert_rules ar ON ar.id = ah.rule_id
            ORDER BY ah.fired_at DESC LIMIT ?
        """, (limit,)).fetchall()
    result = []
    for r in rows:
        d = dict(r)
        d["channels_fired"] = json.loads(d["channels_fired"])
        result.append(d)
    return result
