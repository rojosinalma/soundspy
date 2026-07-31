import math
import time
from collections import deque, defaultdict
from threading import Lock

from helpers import linear_to_dbfs, dbfs_to_linear

HISTORY_SIZE = 3600  # 1 hour at 1 point/sec

_lock = Lock()

_nodes = defaultdict(lambda: {
    "last_update": None,
    "last_heartbeat": None,
    "last_recovery": None,
    "current": {"overall_dbfs": None, "freq_dbfs": None},
    "history": deque(maxlen=HISTORY_SIZE),
    "history_acc": {"sum_power": 0, "count": 0, "bands": {}, "last_sec": 0},
    "firmware_version": "unknown",
    "sleeping": False,
    "in_recovery": False,
})


def get_lock():
    return _lock


def get_node(node_id: str) -> dict:
    return _nodes[node_id]


def get_all_nodes() -> dict:
    return dict(_nodes)


def update_node_data(node_id: str, overall_dbfs: float, bands: dict, seq, esp_ts, recv_time: float, firmware_version: str | None, ip: str):
    timestamp = time.time()
    with _lock:
        node = _nodes[node_id]
        node["last_update"] = timestamp
        node["sleeping"] = False
        node["current"] = {
            "overall_dbfs": overall_dbfs,
            "bands": bands,
            "seq": seq,
            "ts": esp_ts,
            "backend_recv_time": recv_time,
            "ip": ip,
        }
        if firmware_version:
            node["firmware_version"] = firmware_version

        # Downsample to 1 point/sec (average in linear power domain)
        current_sec = int(timestamp)
        acc = node["history_acc"]
        if current_sec != acc["last_sec"]:
            if acc["count"] > 0:
                avg_dbfs = linear_to_dbfs(acc["sum_power"] / acc["count"])
                avg_bands = {
                    k: linear_to_dbfs(v / acc["count"])
                    for k, v in acc["bands"].items()
                }
                node["history"].append({
                    "timestamp": acc["last_sec"],
                    "overall_dbfs": round(avg_dbfs, 1),
                    "bands": {k: round(v, 1) for k, v in avg_bands.items()},
                })
            acc["sum_power"] = dbfs_to_linear(overall_dbfs)
            acc["count"] = 1
            acc["bands"] = {k: dbfs_to_linear(v) for k, v in bands.items()}
            acc["last_sec"] = current_sec
        else:
            acc["sum_power"] += dbfs_to_linear(overall_dbfs)
            acc["count"] += 1
            for k, v in bands.items():
                acc["bands"][k] = acc["bands"].get(k, 0) + dbfs_to_linear(v)


def update_heartbeat(node_id: str, sleeping: bool):
    with _lock:
        _nodes[node_id]["last_heartbeat"] = time.time()
        _nodes[node_id]["sleeping"] = sleeping
        _nodes[node_id]["in_recovery"] = False


def update_recovery(node_id: str):
    with _lock:
        _nodes[node_id]["last_recovery"] = time.time()
        _nodes[node_id]["in_recovery"] = True


def update_firmware_version(node_id: str, version: str):
    with _lock:
        _nodes[node_id]["firmware_version"] = version


def set_node_offline(node_id: str):
    with _lock:
        _nodes[node_id]["last_update"] = None


def get_node_status(node_id: str, db_nodes: dict) -> dict:
    now = time.time()
    with _lock:
        data = _nodes[node_id]
        last_update = data["last_update"]
        last_heartbeat = data["last_heartbeat"]
        is_sleeping = data["sleeping"]

        in_recovery = data.get("in_recovery", False)
        last_recovery = data.get("last_recovery")

        if in_recovery:
            is_online = last_recovery and (now - last_recovery) < 30
        elif is_sleeping:
            is_online = last_heartbeat and (now - last_heartbeat) < 60
        else:
            is_online = last_update and (now - last_update) < 10

        db_node = db_nodes.get(node_id, {})
        return {
            "online": is_online,
            "sleeping": is_sleeping,
            "in_recovery": in_recovery and bool(last_recovery and (now - last_recovery) < 30),
            "last_update": last_update,
            "current": data["current"],
            "firmware_version": data.get("firmware_version", "unknown"),
            "display_name": db_node.get("display_name", node_id),
        }


def get_node_history(node_id: str) -> list:
    with _lock:
        return list(_nodes[node_id]["history"])


def disconnect_node(node_id: str):
    with _lock:
        if node_id in _nodes:
            del _nodes[node_id]
