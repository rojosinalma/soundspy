"""
Soundspy dashboard — Flask/SocketIO entrypoint.
"""

import os
import json
import time
from collections import deque
from threading import Thread
from base64 import b64encode

import paho.mqtt.client as mqtt
from flask import Flask, render_template, jsonify, request, send_from_directory
from flask_socketio import SocketIO, emit
from flask_sock import Sock
from werkzeug.utils import secure_filename

import db
import node_state
import notifications

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
DASHBOARD_VERSION = "2.0.0"

TOPIC_DATA = "soundspy/+/data"
TOPIC_VERSION = "soundspy/+/version"
TOPIC_LOG = "soundspy/+/log"
TOPIC_BOOT = "soundspy/+/boot"
TOPIC_HEARTBEAT = "soundspy/+/heartbeat"

MAX_SYSTEM_LOGS = 200
system_logs: deque = deque(maxlen=MAX_SYSTEM_LOGS)

app = Flask(__name__)
app.config["SECRET_KEY"] = "soundspy-secret"
app.config["UPLOAD_FOLDER"] = "/app/firmware"
app.config["MAX_CONTENT_LENGTH"] = 2 * 1024 * 1024
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
sock = Sock(app)

os.makedirs(app.config["UPLOAD_FOLDER"], exist_ok=True)

# --- MQTT ---

mqtt_client = mqtt.Client()


def on_connect(client, userdata, flags, rc):
    print(f"Dashboard connected to MQTT broker (rc={rc})", flush=True)
    for topic in [TOPIC_DATA, TOPIC_VERSION, TOPIC_LOG, TOPIC_BOOT, TOPIC_HEARTBEAT]:
        client.subscribe(topic)


def on_message(client, userdata, msg):
    try:
        recv_time = time.time()
        payload = json.loads(msg.payload.decode("utf-8"))
        node_id = payload.get("node", "unknown")

        if msg.topic.endswith("/version"):
            version = payload.get("firmware", "unknown")
            node_state.update_firmware_version(node_id, version)
            print(f"[version] {node_id}: firmware {version}", flush=True)
            return

        if msg.topic.endswith("/log"):
            log_entry = {"node_id": node_id, "type": "system", "payload": payload, "timestamp": recv_time}
            system_logs.append(log_entry)
            socketio.emit("node_log", log_entry, namespace="/")
            return

        if msg.topic.endswith("/boot"):
            log_entry = {
                "node_id": node_id,
                "type": "system",
                "payload": {
                    "level": "boot",
                    "msg": f"Boot: partition={payload.get('partition','?')} reset={payload.get('reset_reason','?')} heap={payload.get('free_heap','?')}",
                    **payload,
                },
                "timestamp": recv_time,
            }
            system_logs.append(log_entry)
            socketio.emit("node_log", log_entry, namespace="/")
            return

        if msg.topic.endswith("/heartbeat"):
            node_state.update_heartbeat(node_id, payload.get("sleeping", False))
            return

        # Data message
        overall_dbfs = payload.get("overall_dbfs")
        bands = payload.get("bands", {})
        if not bands:
            freq_dbfs = payload.get("freq_dbfs")
            if freq_dbfs is None:
                return
            bands = {"freq_band": freq_dbfs}
        if overall_dbfs is None:
            return

        firmware_version = payload.get("firmware")
        node_state.update_node_data(
            node_id, overall_dbfs, bands,
            payload.get("seq"), payload.get("ts"),
            recv_time, firmware_version,
            payload.get("ip", "unknown"),
        )

        # Ensure node exists in DB (auto-names on first contact)
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
    print("Client connected to audio stream", flush=True)
    for log_entry in list(system_logs):
        emit("node_log", log_entry)


@socketio.on("disconnect")
def handle_disconnect():
    print("Client disconnected from audio stream", flush=True)


# --- REST API ---

@app.route("/")
def index():
    return render_template("dashboard.html")


@app.route("/settings")
def settings():
    return render_template("settings.html")


@app.route("/api/nodes")
def api_nodes():
    db_nodes = db.get_all_nodes()
    all_node_ids = set(node_state.get_all_nodes().keys()) | set(db_nodes.keys())
    result = {}
    for node_id in all_node_ids:
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


@app.route("/api/control", methods=["POST"])
def api_control():
    data = request.get_json()
    node_id = data.get("node_id")
    command = data.get("command", {})
    if not node_id:
        return jsonify({"error": "Missing node_id"}), 400
    topic = f"soundspy/{node_id}/control"
    mqtt_client.publish(topic, json.dumps(command))
    return jsonify({"success": True})


@app.route("/api/disconnect", methods=["POST"])
def api_disconnect():
    data = request.get_json()
    node_id = data.get("node_id")
    if not node_id:
        return jsonify({"error": "Missing node_id"}), 400
    node_state.disconnect_node(node_id)
    return jsonify({"success": True})


@app.route("/api/ota/upload", methods=["POST"])
def api_ota_upload():
    if "firmware" not in request.files:
        return jsonify({"error": "No firmware file"}), 400
    f = request.files["firmware"]
    filename = secure_filename(f.filename or "soundspy_latest.bin")
    save_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
    f.save(save_path)
    latest = os.path.join(app.config["UPLOAD_FOLDER"], "soundspy_latest.bin")
    if os.path.islink(latest):
        os.remove(latest)
    os.symlink(filename, latest)
    return jsonify({"success": True, "filename": filename, "url": f"/firmware/{filename}"})


@app.route("/api/ota/trigger", methods=["POST"])
def api_ota_trigger():
    data = request.get_json()
    node_id = data.get("node_id")
    firmware_url = data.get("firmware_url")
    if not node_id or not firmware_url:
        return jsonify({"error": "Missing node_id or firmware_url"}), 400
    topic = f"soundspy/{node_id}/control"
    mqtt_client.publish(topic, json.dumps({"ota_url": firmware_url}))
    return jsonify({"success": True})


@app.route("/firmware/<path:filename>")
def serve_firmware(filename):
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


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


# --- WebSocket audio relay ---

audio_clients: list = []
audio_clients_lock = __import__("threading").Lock()


@sock.route("/ws/audio")
def audio_websocket(ws):
    print("ESP32 audio WebSocket connected", flush=True)
    node_id = None
    try:
        first = ws.receive(timeout=5)
        if first:
            meta = json.loads(first)
            node_id = meta.get("node_id")
        with audio_clients_lock:
            audio_clients.append(ws)
        while True:
            data = ws.receive(timeout=30)
            if data is None:
                break
            with audio_clients_lock:
                dead = []
                for client in audio_clients:
                    if client is ws:
                        continue
                    try:
                        client.send(data)
                    except Exception:
                        dead.append(client)
                for d in dead:
                    audio_clients.remove(d)
            if node_id:
                socketio.emit("audio_data", {"node_id": node_id, "audio": b64encode(data).decode()}, namespace="/")
    except Exception as e:
        print(f"Audio WebSocket error: {e}", flush=True)
    finally:
        with audio_clients_lock:
            if ws in audio_clients:
                audio_clients.remove(ws)
        print("ESP32 audio WebSocket disconnected", flush=True)


# --- Startup ---

def start_mqtt():
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    print(f"Connecting to MQTT broker at {MQTT_HOST}:{MQTT_PORT}...", flush=True)
    mqtt_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    mqtt_client.loop_forever()


if __name__ == "__main__":
    db.init_db()
    Thread(target=start_mqtt, daemon=True).start()
    socketio.run(app, host="0.0.0.0", port=8091, debug=False, allow_unsafe_werkzeug=True)
