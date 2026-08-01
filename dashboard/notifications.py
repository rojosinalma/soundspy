"""
Alert evaluation engine and channel dispatchers.

Called after each MQTT data message is processed. Evaluates all enabled alert
rules against the current node data and fires configured channels when triggered.
"""

import time
import threading
from typing import Optional

import db


# --- In-memory breach state (resets on restart) ---

# { rule_id: { "sustained_since": float|None, "breach_times": [float], "last_fired": float, "breach_count": int } }
_breach_state: dict = {}
_state_lock = threading.Lock()


def _get_state(rule_id: int) -> dict:
    if rule_id not in _breach_state:
        _breach_state[rule_id] = {
            "sustained_since": None,
            "breach_times": [],
            "last_fired": 0,
            "breach_count": 0,
        }
    return _breach_state[rule_id]


# --- Cooldown check ---

def _cooldown_allows(state: dict, rule: dict) -> bool:
    mode = rule["cooldown_mode"]
    if mode == "every":
        return True
    if mode == "cooldown":
        return (time.time() - state["last_fired"]) >= (rule["cooldown_seconds"] or 300)
    if mode == "count":
        count = rule["cooldown_count"] or 1
        return state["breach_count"] % count == 0
    return True


# --- Main evaluation entry point ---

def evaluate(node_id: str, overall_dbfs: float, bands: dict, node_display_name: str):
    rules = db.get_alert_rules(enabled_only=True)

    for rule in rules:
        # Scope filter
        if rule["scope"] == "node" and rule["node_id"] != node_id:
            continue

        # Get the level for this rule's band
        band = rule["band"]
        if band == "overall":
            level = overall_dbfs
        else:
            level = bands.get(band, -80.0)

        threshold = rule["threshold"]

        with _state_lock:
            state = _get_state(rule["id"])

            if level <= threshold:
                # Reset sustained timer when level drops below threshold
                state["sustained_since"] = None
                continue

            # Level exceeds threshold — evaluate condition
            fired = False
            now = time.time()

            if rule["condition"] == "instant":
                if _cooldown_allows(state, rule):
                    fired = True

            elif rule["condition"] == "sustained":
                duration = rule["duration_seconds"] or 60
                if state["sustained_since"] is None:
                    state["sustained_since"] = now
                elif (now - state["sustained_since"]) >= duration:
                    if _cooldown_allows(state, rule):
                        fired = True
                        state["sustained_since"] = now  # reset so it doesn't re-fire every frame

            elif rule["condition"] == "repeated":
                window = rule["repeat_window_seconds"] or 60
                count = rule["repeat_count"] or 3
                state["breach_times"].append(now)
                # Prune old breaches outside window
                state["breach_times"] = [t for t in state["breach_times"] if now - t <= window]
                if len(state["breach_times"]) >= count:
                    if _cooldown_allows(state, rule):
                        fired = True
                        state["breach_times"] = []  # reset after firing

            if fired:
                state["breach_count"] += 1
                state["last_fired"] = now
                threading.Thread(
                    target=_dispatch_rule,
                    args=(rule, node_id, node_display_name, band, level),
                    daemon=True
                ).start()


def _dispatch_rule(rule: dict, node_id: str, node_display_name: str, band: str, level: float):
    channels = db.get_rule_channels(rule["id"])
    if not channels:
        return

    scope = rule["scope"]
    message = _build_message(rule, node_id, node_display_name, band, level, scope)
    channels_fired = []

    for channel in channels:
        if not channel["enabled"]:
            continue
        try:
            _dispatch_channel(channel, message, rule["urgency"])
            channels_fired.append(channel["label"])
        except Exception as e:
            print(f"[notifications] channel '{channel['label']}' failed: {e}", flush=True)

    db.log_alert(rule["id"], node_id, band, level, scope, channels_fired)


def _build_message(rule: dict, node_id: str, node_display_name: str, band: str, level: float, scope: str) -> dict:
    band_label = band.replace("_", " ").title() if band != "overall" else "Overall"
    scope_label = f"Global alert (triggered by {node_display_name})" if scope == "global" else f"Node: {node_display_name}"
    return {
        "title": f"[{rule['urgency'].upper()}] {rule['name']}",
        "body": (
            f"{scope_label}\n"
            f"Band: {band_label} | Level: {level:.1f} dBFS | Threshold: {rule['threshold']:.1f} dBFS"
        ),
        "urgency": rule["urgency"],
        "rule_name": rule["name"],
        "node_id": node_id,
        "node_name": node_display_name,
        "band": band_label,
        "level": level,
        "threshold": rule["threshold"],
    }


# --- Channel dispatchers ---

def _dispatch_channel(channel: dict, message: dict, urgency: str):
    platform = channel["platform"]
    config = channel["config"]
    token = config.get("token", "")

    if not token:
        print(f"[notifications] no token configured for channel '{channel['label']}', skipping", flush=True)
        return

    if platform == "telegram":
        _send_telegram(token, config.get("chat_id", ""), message)
    elif platform == "discord":
        _send_discord(token, message, urgency)
    elif platform == "ntfy":
        _send_ntfy(token, message, urgency)
    elif platform == "pushover":
        _send_pushover(token, config.get("user_key", ""), message, urgency)
    elif platform == "email":
        _send_email(token, config, message)
    else:
        print(f"[notifications] unknown platform '{platform}'", flush=True)


def _send_telegram(bot_token: str, chat_id: str, message: dict):
    import requests
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    requests.post(url, json={
        "chat_id": chat_id,
        "text": f"*{message['title']}*\n{message['body']}",
        "parse_mode": "Markdown",
    }, timeout=10)


def _send_discord(webhook_url: str, message: dict, urgency: str):
    import requests
    color = {"info": 0x3b82f6, "warning": 0xf59e0b, "critical": 0xef4444}.get(urgency, 0x6366f1)
    requests.post(webhook_url, json={
        "embeds": [{
            "title": message["title"],
            "description": message["body"],
            "color": color,
        }]
    }, timeout=10)


def _send_ntfy(url: str, message: dict, urgency: str):
    import requests
    priority = {"info": "default", "warning": "high", "critical": "urgent"}.get(urgency, "default")
    requests.post(url, data=message["body"].encode(), headers={
        "Title": message["title"],
        "Priority": priority,
        "Tags": "loud_sound",
    }, timeout=10)


def _send_pushover(token: str, user_key: str, message: dict, urgency: str):
    import requests
    priority = {"info": 0, "warning": 1, "critical": 2}.get(urgency, 0)
    requests.post("https://api.pushover.net/1/messages.json", data={
        "token": token,
        "user": user_key,
        "title": message["title"],
        "message": message["body"],
        "priority": priority,
    }, timeout=10)


def _send_email(smtp_pass: str, config: dict, message: dict):
    import smtplib
    from email.mime.text import MIMEText
    smtp_host = config.get("smtp_host", "")
    smtp_user = config.get("smtp_user", "")
    smtp_port = int(config.get("smtp_port", 587))
    to_addr = config.get("to", "")
    if not all([smtp_host, smtp_user, smtp_pass, to_addr]):
        print("[notifications] email config incomplete", flush=True)
        return
    msg = MIMEText(message["body"])
    msg["Subject"] = message["title"]
    msg["From"] = smtp_user
    msg["To"] = to_addr
    with smtplib.SMTP(smtp_host, smtp_port) as s:
        s.starttls()
        s.login(smtp_user, smtp_pass)
        s.send_message(msg)


def test_channel(channel: dict) -> tuple[bool, str]:
    """Send a test notification to a channel. Returns (success, error_message)."""
    test_msg = {
        "title": "[TEST] Soundspy notification test",
        "body": "This is a test notification from Soundspy.",
        "urgency": "info",
        "rule_name": "test",
        "node_id": "test",
        "node_name": "test",
        "band": "Overall",
        "level": -20.0,
        "threshold": -20.0,
    }
    try:
        _dispatch_channel(channel, test_msg, "info")
        return True, ""
    except Exception as e:
        return False, str(e)
