"""
Bass threshold monitor.

Subscribes to bassmonitor/+/data (all 3 wall nodes), checks each node's
freq_dbfs reading against a threshold, and fires an ntfy push notification
when exceeded — with a per-node cooldown so you don't get spammed while
you're actively playing.
"""

import os
import json
import time
import requests
import paho.mqtt.client as mqtt

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
NTFY_URL = os.environ.get("NTFY_URL", "http://localhost/soundspy")
FREQ_THRESHOLD_DBFS = float(os.environ.get("FREQ_THRESHOLD_DBFS", -20))
COOLDOWN_SECONDS = int(os.environ.get("COOLDOWN_SECONDS", 300))

TOPIC = "soundspy/+/data"

last_alert_time = {}  # node_id -> timestamp of last alert


def send_ntfy(node_id: str, freq_dbfs: float, overall_dbfs: float):
    title = f"Sound level high — {node_id}"
    message = (
        f"{node_id}: frequency band {freq_dbfs:.1f} dBFS "
        f"(overall {overall_dbfs:.1f} dBFS), threshold {FREQ_THRESHOLD_DBFS} dBFS"
    )
    try:
        requests.post(
            NTFY_URL,
            data=message.encode("utf-8"),
            headers={"Title": title, "Priority": "high", "Tags": "loud_sound"},
            timeout=5,
        )
    except requests.RequestException as e:
        print(f"[warn] failed to send ntfy alert: {e}")


def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker at {MQTT_HOST}:{MQTT_PORT} (rc={rc})", flush=True)
    client.subscribe(TOPIC)
    print(f"Subscribed to {TOPIC}", flush=True)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        print(f"[warn] could not parse payload on {msg.topic}: {msg.payload}", flush=True)
        return

    node_id = payload.get("node", "unknown")
    overall_dbfs = payload.get("overall_dbfs")
    bands = payload.get("bands", {})

    if not bands:
        # Fallback: old single-band format
        freq_dbfs = payload.get("freq_dbfs")
        if freq_dbfs is None:
            return
        print(f"{node_id}: freq={freq_dbfs:.1f} dBFS overall={overall_dbfs:.1f} dBFS", flush=True)
        check_band = freq_dbfs
    else:
        # New multi-band format: check the bass band by default (configurable in future)
        check_band = bands.get("bass", -100)
        print(f"{node_id}: overall={overall_dbfs:.1f} dBFS, bands={bands}", flush=True)

    if check_band >= FREQ_THRESHOLD_DBFS:
        now = time.time()
        last = last_alert_time.get(node_id, 0)
        if now - last >= COOLDOWN_SECONDS:
            send_ntfy(node_id, check_band, overall_dbfs)
            last_alert_time[node_id] = now
            print(f"[alert] sent for {node_id}", flush=True)
        else:
            print(f"[cooldown] {node_id} over threshold but within cooldown window", flush=True)


def main():
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    print(f"Connecting to {MQTT_HOST}:{MQTT_PORT} ...")
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_forever()


if __name__ == "__main__":
    main()

