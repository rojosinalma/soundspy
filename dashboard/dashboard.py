"""
Web dashboard for soundspy.

Shows real-time and historical readings from all nodes.
"""

import os
import json
import time
import math
from collections import deque, defaultdict
from threading import Thread, Lock
import paho.mqtt.client as mqtt
from flask import Flask, render_template, Response, jsonify, request, send_from_directory
from flask_socketio import SocketIO, emit
from flask_sock import Sock
from werkzeug.utils import secure_filename

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
FREQ_THRESHOLD_DBFS = float(os.environ.get("FREQ_THRESHOLD_DBFS", -20))
DASHBOARD_VERSION = "1.4.5"

TOPIC_DATA = "soundspy/+/data"
TOPIC_VERSION = "soundspy/+/version"
TOPIC_LOG = "soundspy/+/log"
TOPIC_BOOT = "soundspy/+/boot"
TOPIC_HEARTBEAT = "soundspy/+/heartbeat"

# Node name persistence
NODE_NAMES_FILE = "/app/data/node_names.json"


def load_node_names():
    try:
        with open(NODE_NAMES_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_node_names(names):
    os.makedirs(os.path.dirname(NODE_NAMES_FILE), exist_ok=True)
    with open(NODE_NAMES_FILE, "w") as f:
        json.dump(names, f, indent=2)


def get_node_name(chip_id):
    """Get display name for a chip ID, auto-assigning if new."""
    names = load_node_names()
    if chip_id not in names:
        existing_nums = []
        for name in names.values():
            if name.startswith("node-"):
                try:
                    existing_nums.append(int(name.split("-")[1]))
                except (IndexError, ValueError):
                    pass
        next_num = max(existing_nums, default=0) + 1
        names[chip_id] = f"node-{next_num}"
        save_node_names(names)
    return names[chip_id]


# Store last 1 hour of data per node (1 point/second = 3600 points)
HISTORY_SIZE = 3600
node_data = defaultdict(lambda: {
    "last_update": None,
    "last_heartbeat": None,
    "current": {"overall_dbfs": None, "freq_dbfs": None},
    "history": deque(maxlen=HISTORY_SIZE),
    "history_acc": {"sum_power": 0, "count": 0, "bands": {}, "last_sec": 0},
    "firmware_version": "unknown",
    "sleeping": False
})
data_lock = Lock()

app = Flask(__name__)
app.config['SECRET_KEY'] = 'soundspy-secret'
app.config['UPLOAD_FOLDER'] = '/app/firmware'
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024  # 2MB max firmware size
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')
sock = Sock(app)

# Create firmware directory if it doesn't exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)


def on_connect(client, userdata, flags, rc):
    print(f"Dashboard connected to MQTT broker (rc={rc})", flush=True)
    client.subscribe(TOPIC_DATA)
    client.subscribe(TOPIC_VERSION)
    client.subscribe(TOPIC_LOG)
    client.subscribe(TOPIC_BOOT)
    client.subscribe(TOPIC_HEARTBEAT)


def on_message(client, userdata, msg):
    try:
        recv_time = time.time()
        payload = json.loads(msg.payload.decode("utf-8"))
        node_id = payload.get("node", "unknown")

        # Handle version messages
        if msg.topic.endswith("/version"):
            firmware_version = payload.get("firmware", "unknown")
            with data_lock:
                node_data[node_id]["firmware_version"] = firmware_version
            print(f"[version] {node_id}: firmware {firmware_version}", flush=True)
            return

        # Handle log messages (system logs from the node)
        if msg.topic.endswith("/log"):
            socketio.emit('node_log', {
                'node_id': node_id,
                'type': 'system',
                'payload': payload,
                'timestamp': time.time()
            }, namespace='/')
            return

        # Handle boot messages
        if msg.topic.endswith("/boot"):
            socketio.emit('node_log', {
                'node_id': node_id,
                'type': 'system',
                'payload': {
                    'level': 'boot',
                    'msg': f"Boot: partition={payload.get('partition','?')} reset={payload.get('reset_reason','?')} heap={payload.get('free_heap','?')}",
                    **payload
                },
                'timestamp': time.time()
            }, namespace='/')
            return

        # Handle heartbeat messages
        if msg.topic.endswith("/heartbeat"):
            with data_lock:
                node_data[node_id]["last_heartbeat"] = time.time()
                node_data[node_id]["sleeping"] = payload.get("sleeping", False)
            return

        # Handle data messages
        overall_dbfs = payload.get("overall_dbfs")
        bands = payload.get("bands", {})
        seq = payload.get("seq")
        firmware_version = payload.get("firmware")
        esp_ts = payload.get("ts")

        # Handle both old single-band and new multi-band formats
        if bands:
            # New multi-band format
            freq_data = bands
        else:
            # Old single-band format (backwards compatibility)
            freq_dbfs = payload.get("freq_dbfs")
            if freq_dbfs is None:
                return
            freq_data = {"freq_band": freq_dbfs}

        if overall_dbfs is None:
            return

        timestamp = time.time()

        with data_lock:
            node_data[node_id]["last_update"] = timestamp
            node_data[node_id]["sleeping"] = False
            node_data[node_id]["current"] = {
                "overall_dbfs": overall_dbfs,
                "bands": freq_data,
                "seq": seq,
                "ts": esp_ts,
                "backend_recv_time": recv_time,
                "ip": payload.get("ip", "unknown")
            }
            # Update firmware version if present in payload
            if firmware_version:
                node_data[node_id]["firmware_version"] = firmware_version
            # Downsample to 1 point/second for history (average in linear power domain)
            current_sec = int(timestamp)
            acc = node_data[node_id]["history_acc"]
            if current_sec != acc["last_sec"]:
                if acc["count"] > 0:
                    avg_power = acc["sum_power"] / acc["count"]
                    avg_dbfs = 10 * math.log10(avg_power + 1e-18)
                    avg_bands = {}
                    for k, v in acc["bands"].items():
                        band_power = v / acc["count"]
                        avg_bands[k] = 10 * math.log10(band_power + 1e-18)
                    node_data[node_id]["history"].append({
                        "timestamp": acc["last_sec"],
                        "overall_dbfs": round(avg_dbfs, 1),
                        "bands": {k: round(v, 1) for k, v in avg_bands.items()}
                    })
                acc["sum_power"] = 10 ** (overall_dbfs / 10)
                acc["count"] = 1
                acc["bands"] = {k: 10 ** (v / 10) for k, v in (freq_data.items() if isinstance(freq_data, dict) else [])}
                acc["last_sec"] = current_sec
            else:
                acc["sum_power"] += 10 ** (overall_dbfs / 10)
                acc["count"] += 1
                for k, v in (freq_data.items() if isinstance(freq_data, dict) else []):
                    acc["bands"][k] = acc["bands"].get(k, 0) + 10 ** (v / 10)

            # Broadcast real-time update via WebSocket (faster than SSE)
            socketio.emit('sensor_data', {
                'node_id': node_id,
                'display_name': get_node_name(node_id),
                'firmware_version': node_data[node_id].get("firmware_version", "unknown"),
                'data': node_data[node_id]["current"],
                'timestamp': timestamp
            }, namespace='/')

    except (ValueError, UnicodeDecodeError) as e:
        print(f"[warn] could not parse payload: {e}", flush=True)


def mqtt_thread():
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    print(f"Connecting to MQTT broker at {MQTT_HOST}:{MQTT_PORT}...", flush=True)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_forever()


@app.route("/")
def index():
    return render_template("dashboard.html", dashboard_version=DASHBOARD_VERSION)


@app.route("/api/nodes")
def api_nodes():
    """Get current state of all nodes."""
    with data_lock:
        result = {}
        now = time.time()
        for node_id, data in node_data.items():
            last_update = data["last_update"]
            last_heartbeat = data.get("last_heartbeat")
            is_sleeping = data.get("sleeping", False)
            if is_sleeping:
                is_online = last_heartbeat and (now - last_heartbeat) < 60
            else:
                is_online = last_update and (now - last_update) < 10

            result[node_id] = {
                "online": is_online,
                "sleeping": is_sleeping,
                "last_update": last_update,
                "current": data["current"],
                "firmware_version": data.get("firmware_version", "unknown"),
                "display_name": get_node_name(node_id)
            }

        return jsonify({
            "nodes": result,
            "threshold": FREQ_THRESHOLD_DBFS
        })


@app.route("/api/node/rename", methods=["POST"])
def api_rename_node():
    """Rename a node's display name."""
    data = request.get_json()
    chip_id = data.get("chip_id")
    new_name = data.get("name", "").strip()

    if not chip_id or not new_name:
        return jsonify({"error": "Missing chip_id or name"}), 400

    names = load_node_names()
    names[chip_id] = new_name
    save_node_names(names)

    print(f"Node {chip_id} renamed to '{new_name}'", flush=True)
    return jsonify({"success": True, "chip_id": chip_id, "name": new_name})


@app.route("/api/history/<node_id>")
def api_history(node_id):
    """Get historical data for a specific node."""
    with data_lock:
        if node_id not in node_data:
            return jsonify({"error": "Node not found"}), 404

        history = list(node_data[node_id]["history"])

        return jsonify({
            "node_id": node_id,
            "history": history
        })


@app.route("/api/control", methods=["POST"])
def api_control():
    """Send control commands to ESP32 nodes via MQTT."""
    data = request.get_json()
    node_id = data.get("node_id")
    command = data.get("command")

    if not node_id or not command:
        return jsonify({"error": "Missing node_id or command"}), 400

    # Publish control command to MQTT
    topic = f"soundspy/{node_id}/control"
    payload = json.dumps(command)

    # Get MQTT client from the mqtt_thread (use a simple approach)
    # We'll create a new client for control messages (simpler than sharing)
    control_client = mqtt.Client()
    control_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    control_client.publish(topic, payload)
    control_client.disconnect()

    # Track sleep/wake state
    with data_lock:
        if command.get("sleep"):
            node_data[node_id]["sleeping"] = True
        elif command.get("wake"):
            node_data[node_id]["sleeping"] = False

    print(f"Sent control to {node_id}: {payload}", flush=True)

    return jsonify({"success": True})


@app.route("/api/disconnect", methods=["POST"])
def api_disconnect():
    """Remove a node from the dashboard."""
    data = request.get_json()
    node_id = data.get("node_id")

    if not node_id:
        return jsonify({"error": "Missing node_id"}), 400

    with data_lock:
        if node_id in node_data:
            del node_data[node_id]

    print(f"Disconnected node: {node_id}", flush=True)
    return jsonify({"success": True})


@app.route("/api/ota/upload", methods=["POST"])
def ota_upload():
    """Upload firmware binary for OTA updates."""
    if 'firmware' not in request.files:
        return jsonify({"error": "No firmware file"}), 400

    file = request.files['firmware']
    if file.filename == '':
        return jsonify({"error": "No filename"}), 400

    if not file.filename.endswith('.bin'):
        return jsonify({"error": "Must be a .bin file"}), 400

    filename = secure_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)

    print(f"Firmware uploaded: {filename}", flush=True)

    return jsonify({
        "success": True,
        "filename": filename,
        "url": f"http://{request.host}/firmware/{filename}"
    })


@app.route("/api/ota/trigger", methods=["POST"])
def ota_trigger():
    """Trigger OTA update on a specific node."""
    data = request.get_json()
    node_id = data.get("node_id")
    firmware_url = data.get("firmware_url")

    if not node_id or not firmware_url:
        return jsonify({"error": "Missing node_id or firmware_url"}), 400

    # Send OTA command via MQTT
    topic = f"soundspy/{node_id}/control"
    payload = json.dumps({"ota_url": firmware_url})

    control_client = mqtt.Client()
    control_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    control_client.publish(topic, payload)
    control_client.disconnect()

    print(f"OTA triggered for {node_id}: {firmware_url}", flush=True)

    return jsonify({"success": True})


@app.route("/firmware/<filename>")
def serve_firmware(filename):
    """Serve firmware files for ESP32 to download."""
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)


@socketio.on('connect')
def handle_connect():
    print(f"Client connected to audio stream", flush=True)


@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client disconnected from audio stream", flush=True)


# Raw WebSocket endpoint for ESP32 audio streaming
@sock.route('/ws/audio')
def audio_websocket(ws):
    """Raw WebSocket endpoint for ESP32 nodes to stream audio."""
    print("ESP32 audio WebSocket connected", flush=True)

    try:
        while True:
            data = ws.receive()
            if data:
                try:
                    # Parse JSON from ESP32
                    import json
                    msg = json.loads(data)
                    node_id = msg.get('node_id')
                    audio_b64 = msg.get('audio')

                    if node_id and audio_b64:
                        # Broadcast to web clients via SocketIO
                        socketio.emit('audio_data', {
                            'node_id': node_id,
                            'audio': audio_b64
                        }, namespace='/')
                        print(f"Relayed audio from {node_id}", flush=True)
                except Exception as e:
                    print(f"Error processing audio data: {e}", flush=True)
    except Exception as e:
        print(f"ESP32 audio WebSocket error: {e}", flush=True)
    finally:
        print("ESP32 audio WebSocket disconnected", flush=True)


# Start MQTT thread when module loads
mqtt_t = Thread(target=mqtt_thread, daemon=True)
mqtt_t.start()

if __name__ == "__main__":
    # Start Flask-SocketIO server (MQTT thread already started at module load)
    socketio.run(app, host="0.0.0.0", port=8091, debug=True, use_reloader=True, reloader_type='watchdog', allow_unsafe_werkzeug=True)
