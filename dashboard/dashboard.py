"""
Web dashboard for soundspy.

Shows real-time and historical readings from all nodes.
"""

import os
import json
import time
from datetime import datetime
from collections import deque, defaultdict
from threading import Thread, Lock
import paho.mqtt.client as mqtt
from flask import Flask, render_template, Response, jsonify, request, send_from_directory
from flask_socketio import SocketIO, emit
from flask_sock import Sock
from werkzeug.utils import secure_filename
import base64
import os as os_module

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
FREQ_THRESHOLD_DBFS = float(os.environ.get("FREQ_THRESHOLD_DBFS", -20))
TOPIC_DATA = "soundspy/+/data"
TOPIC_VERSION = "soundspy/+/version"

# Store last 1 hour of data per node
# ESP32 publishes at 50Hz, so 1 hour = 3600 * 50 = 180,000 points
# Keep this reasonable for memory
HISTORY_SIZE = 3600
node_data = defaultdict(lambda: {
    "last_update": None,
    "current": {"overall_dbfs": None, "freq_dbfs": None},
    "history": deque(maxlen=HISTORY_SIZE),
    "firmware_version": "unknown"
})
data_lock = Lock()

app = Flask(__name__)
app.config['SECRET_KEY'] = 'soundspy-secret'
app.config['UPLOAD_FOLDER'] = '/app/firmware'
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024  # 2MB max firmware size
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')
sock = Sock(app)

# Create firmware directory if it doesn't exist
os_module.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)


def on_connect(client, userdata, flags, rc):
    print(f"Dashboard connected to MQTT broker (rc={rc})", flush=True)
    client.subscribe(TOPIC_DATA)
    client.subscribe(TOPIC_VERSION)


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

        # Handle data messages
        overall_dbfs = payload.get("overall_dbfs")
        bands = payload.get("bands", {})
        seq = payload.get("seq")
        firmware_version = payload.get("firmware")
        esp_ts = payload.get("ts")  # ESP32 millis() timestamp

        # Log latency (for debugging)
        if esp_ts is not None:
            mqtt_latency = (recv_time * 1000) - esp_ts  # Convert to ms, relative to ESP32 uptime
            # Note: This will be incorrect until we sync clocks, but shows MQTT transit time
            print(f"[latency] {node_id} seq={seq}: received at backend", flush=True)

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
            node_data[node_id]["history"].append({
                "timestamp": timestamp,
                "overall_dbfs": overall_dbfs,
                "bands": freq_data
            })

            # Broadcast real-time update via WebSocket (faster than SSE)
            socketio.emit('sensor_data', {
                'node_id': node_id,
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
    return render_template("dashboard.html")


@app.route("/api/nodes")
def api_nodes():
    """Get current state of all nodes."""
    with data_lock:
        result = {}
        now = time.time()
        for node_id, data in node_data.items():
            last_update = data["last_update"]
            is_online = last_update and (now - last_update) < 10  # offline if no data for 10s

            result[node_id] = {
                "online": is_online,
                "last_update": last_update,
                "current": data["current"],
                "firmware_version": data.get("firmware_version", "unknown")
            }

        return jsonify({
            "nodes": result,
            "threshold": FREQ_THRESHOLD_DBFS
        })


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

    print(f"Sent control to {node_id}: {payload}", flush=True)

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
    filepath = os_module.path.join(app.config['UPLOAD_FOLDER'], filename)
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


@app.route("/stream")
def stream():
    """Server-sent events stream for real-time updates."""
    def event_stream():
        last_sent = {}
        while True:
            with data_lock:
                for node_id, data in node_data.items():
                    last_update = data["last_update"]
                    if last_update and last_update != last_sent.get(node_id):
                        last_sent[node_id] = last_update
                        event_data = json.dumps({'node_id': node_id, 'data': data['current'], 'timestamp': last_update})
                        yield f"data: {event_data}\n\n"

            time.sleep(0.1)  # Reduced from 0.5s to 0.1s for lower latency

    response = Response(event_stream(), mimetype="text/event-stream")
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    return response


# WebSocket handlers for audio streaming from ESP32 nodes
@socketio.on('audio_stream')
def handle_audio_stream(data):
    """Receive audio data from ESP32 nodes and broadcast to web clients."""
    node_id = data.get('node_id')
    audio_chunk = data.get('audio')  # Base64 encoded PCM data

    # Broadcast to all connected web clients
    socketio.emit('audio_data', {
        'node_id': node_id,
        'audio': audio_chunk
    }, broadcast=True)


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
    socketio.run(app, host="0.0.0.0", port=8091, debug=False, allow_unsafe_werkzeug=True)
