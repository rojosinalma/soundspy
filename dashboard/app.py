"""
Soundspy dashboard — Flask/SocketIO entrypoint.
"""

import os
import json
import time
from collections import deque
from threading import Thread

import paho.mqtt.client as mqtt
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit

import audio_relay
import db
import node_state
import notifications

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
MQTT_USER = os.environ.get("MQTT_USER", "")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
MQTT_PREFIX = os.environ.get("MQTT_PREFIX", "esp32")  # esp32-base topic prefix: <prefix>/<chip_id>/<leaf>
DASHBOARD_VERSION = "2.1.2"

NODE_APP = "soundspy"  # esp32-base app name the nodes report in their status; other apps on the broker are ignored
TOPIC_DATA = f"{MQTT_PREFIX}/+/data"
TOPIC_STATUS = f"{MQTT_PREFIX}/+/status"
TOPIC_LOG = f"{MQTT_PREFIX}/+/log"
LOG_LEVELS = {"I": "info", "W": "warn", "E": "error"}

MAX_SYSTEM_LOGS = 200
system_logs: deque = deque(maxlen=MAX_SYSTEM_LOGS)

app = Flask(__name__)
app.config["SECRET_KEY"] = "soundspy-secret"
app.config["TEMPLATES_AUTO_RELOAD"] = True
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")

# --- MQTT ---

mqtt_client = mqtt.Client()


def on_connect(client, userdata, flags, rc):
    print(f"Dashboard connected to MQTT broker (rc={rc})", flush=True)
    for topic in [TOPIC_STATUS, TOPIC_DATA, TOPIC_LOG]:
        client.subscribe(topic)


def cmd_topic(node_id: str) -> str:
    return f"{MQTT_PREFIX}/{node_id}/cmd"


def handle_status(node_id: str, payload: dict):
    # The broker carries every esp32-base board; keep only soundspy nodes, plus a known node that
    # dropped to recovery or went offline (LWT carries no app field).
    is_ours = payload.get("app") == NODE_APP
    if not is_ours and not node_state.is_known(node_id):
        return
    node_state.update_status(node_id, payload)
    if payload.get("hostname"):
        db.upsert_node(node_id, display_name=payload["hostname"])  # display names follow the board's hostname
    else:
        db.get_node_name(node_id)

    status = node_state.get_node_status(node_id, db.get_all_nodes())
    app_status = payload.get("app_status") or {}
    audio_relay.update(node_id, status["ip"], app_status.get("stream_port", 0),
                       active=bool(status["online"] and not status["sleeping"] and not status["in_recovery"]))
    socketio.emit("node_status", {
        "node_id": node_id,
        "online": status["online"],
        "sleeping": status["sleeping"],
        "in_recovery": status["in_recovery"],
        "display_name": status["display_name"],
        "firmware_version": status["firmware_version"],
        "ip": status["ip"],
        "gain": status["gain"],
    }, namespace="/")
    if status["gain"] is not None:
        socketio.emit("hw_gain", {"node_id": node_id, "gain": status["gain"]}, namespace="/")
    print(f"[status] {node_id} ({status['display_name']}): online={status['online']} sleeping={status['sleeping']} "
          f"recovery={status['in_recovery']} v{status['firmware_version']} ip={status['ip']}", flush=True)


def handle_log(node_id: str, payload: dict, recv_time: float):
    if not node_state.is_known(node_id):
        return
    entry = {
        "node_id": node_id,
        "type": "system",
        "payload": {"level": LOG_LEVELS.get(payload.get("level"), payload.get("level", "info")),
                    "msg": payload.get("text", ""), "uptime_ms": payload.get("ms"), "seq": payload.get("seq")},
        "timestamp": recv_time,
    }
    system_logs.append(entry)
    socketio.emit("node_log", entry, namespace="/")


def on_message(client, userdata, msg):
    try:
        recv_time = time.time()
        parts = msg.topic.split("/")
        if len(parts) != 3:
            return
        _, node_id, leaf = parts
        payload = json.loads(msg.payload.decode("utf-8"))

        if leaf == "status":
            return handle_status(node_id, payload)
        if leaf == "log":
            return handle_log(node_id, payload, recv_time)
        if leaf != "data" or not node_state.is_known(node_id):
            return  # data from a board whose status we have not accepted (not a soundspy node)

        overall_dbfs = payload.get("overall_dbfs")
        bands = payload.get("bands")
        if overall_dbfs is None or not bands:
            return

        node_state.update_node_data(node_id, overall_dbfs, bands, payload.get("seq"), payload.get("ts"), recv_time)
        db.get_node_name(node_id)

        db_nodes = db.get_all_nodes()
        status = node_state.get_node_status(node_id, db_nodes)

        socketio.emit("sensor_data", {
            "node_id": node_id,
            "data": status["current"],
            "timestamp": time.time(),
            "firmware_version": status["firmware_version"],
            "display_name": status["display_name"],
        }, namespace="/")

        # Evaluate alert rules
        notifications.evaluate(node_id, overall_dbfs, bands, status["display_name"])

    except Exception as e:
        print(f"[mqtt] message error: {e}", flush=True)


# --- SocketIO ---

@socketio.on("connect")
def handle_connect():
    audio_relay.listener_connected()
    print("Browser connected", flush=True)
    for log_entry in list(system_logs):
        emit("node_log", log_entry)


@socketio.on("disconnect")
def handle_disconnect():
    audio_relay.listener_disconnected()
    print("Browser disconnected", flush=True)


# --- REST API ---

@app.route("/")
def index():
    return render_template("dashboard.html", dashboard_version=DASHBOARD_VERSION)


@app.route("/settings")
def settings():
    return render_template("settings.html")


@app.route("/api/nodes")
def api_nodes():
    db_nodes = db.get_all_nodes()
    live_node_ids = node_state.get_all_nodes().keys()
    result = {}
    for node_id in live_node_ids:
        result[node_id] = node_state.get_node_status(node_id, db_nodes)

    return jsonify({
        "nodes": result,
        "node_thresholds": {nid: info["threshold"] for nid, info in db_nodes.items()},
    })


@app.route("/api/node/rename", methods=["POST"])
def api_rename_node():
    data = request.get_json()
    chip_id = data.get("chip_id")
    new_name = data.get("name", "").strip()
    if not chip_id or not new_name:
        return jsonify({"error": "Missing chip_id or name"}), 400
    db.upsert_node(chip_id, display_name=new_name)
    print(f"Node {chip_id} renamed to '{new_name}'", flush=True)
    return jsonify({"success": True, "chip_id": chip_id, "name": new_name})


@app.route("/api/node/threshold", methods=["POST"])
def api_set_threshold():
    data = request.get_json()
    chip_id = data.get("chip_id")
    value = data.get("value")
    if not chip_id or value is None:
        return jsonify({"error": "Missing chip_id or value"}), 400
    value = max(-80, min(0, float(value)))
    db.set_node_threshold(chip_id, value)
    return jsonify({"success": True, "chip_id": chip_id, "value": value})


@app.route("/api/history/<node_id>")
def api_history(node_id):
    if node_id not in node_state.get_all_nodes():
        return jsonify({"error": "Node not found"}), 404
    return jsonify({"node_id": node_id, "history": node_state.get_node_history(node_id)})


def to_node_cmd(command: dict) -> dict | None:
    """Map the UI's control payload to an esp32-base cmd message."""
    if "gain" in command:
        return {"cmd": "gain", "value": float(command["gain"])}
    for flag in ("reboot", "sleep", "wake"):
        if command.get(flag):
            return {"cmd": flag}
    return None


@app.route("/api/control", methods=["POST"])
def api_control():
    data = request.get_json()
    node_id = data.get("node_id")
    command = data.get("command", {})
    if not node_id:
        return jsonify({"error": "Missing node_id"}), 400
    cmd = to_node_cmd(command)
    if cmd is None:
        return jsonify({"error": f"Unknown command {command}"}), 400
    mqtt_client.publish(cmd_topic(node_id), json.dumps(cmd))
    return jsonify({"success": True, "cmd": cmd})


@app.route("/api/disconnect", methods=["POST"])
def api_disconnect():
    data = request.get_json()
    node_id = data.get("node_id")
    if not node_id:
        return jsonify({"error": "Missing node_id"}), 400
    node_state.disconnect_node(node_id)
    return jsonify({"success": True})


# --- Notification / settings API ---

@app.route("/api/channels", methods=["GET"])
def api_get_channels():
    return jsonify(db.get_channels())


@app.route("/api/channels", methods=["POST"])
def api_upsert_channel():
    data = request.get_json()
    channel_id = db.upsert_channel(data)
    return jsonify({"success": True, "id": channel_id})


@app.route("/api/channels/<int:channel_id>", methods=["DELETE"])
def api_delete_channel(channel_id):
    db.delete_channel(channel_id)
    return jsonify({"success": True})


@app.route("/api/channels/<int:channel_id>/test", methods=["POST"])
def api_test_channel(channel_id):
    channels = db.get_channels()
    channel = next((c for c in channels if c["id"] == channel_id), None)
    if not channel:
        return jsonify({"error": "Channel not found"}), 404
    success, error = notifications.test_channel(channel)
    if success:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": error}), 500


@app.route("/api/rules", methods=["GET"])
def api_get_rules():
    rules = db.get_alert_rules()
    for rule in rules:
        rule["channels"] = db.get_rule_channels(rule["id"])
    return jsonify(rules)


@app.route("/api/rules", methods=["POST"])
def api_upsert_rule():
    data = request.get_json()
    channel_ids = data.pop("channel_ids", [])
    rule_id = db.upsert_alert_rule(data)
    db.set_rule_channels(rule_id, channel_ids)
    return jsonify({"success": True, "id": rule_id})


@app.route("/api/rules/<int:rule_id>", methods=["DELETE"])
def api_delete_rule(rule_id):
    db.delete_alert_rule(rule_id)
    return jsonify({"success": True})


@app.route("/api/alert-history")
def api_alert_history():
    limit = int(request.args.get("limit", 100))
    return jsonify(db.get_alert_history(limit))


@app.route("/api/relays")
def api_relays():
    return jsonify(audio_relay.status())


# --- Startup ---

def start_mqtt():
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    if MQTT_USER:
        mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
    print(f"Connecting to MQTT broker at {MQTT_HOST}:{MQTT_PORT} as {MQTT_USER or 'anonymous'}...", flush=True)
    mqtt_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    mqtt_client.loop_forever()


if __name__ == "__main__":
    db.init_db()
    audio_relay.init(lambda event, data: socketio.emit(event, data, namespace="/"), log=lambda m: print(m, flush=True))
    Thread(target=start_mqtt, daemon=True).start()
    socketio.run(app, host="0.0.0.0", port=8091, debug=False, allow_unsafe_werkzeug=True)
