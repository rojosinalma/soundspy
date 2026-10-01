import math
import time
from collections import deque, defaultdict
from threading import Lock

from helpers import linear_to_dbfs, dbfs_to_linear

HISTORY_SIZE = 3600  # 1 hour at 1 point/sec
DATA_TIMEOUT_S = 10     # no /data for this long = offline (when awake)
STATUS_TIMEOUT_S = 90   # no retained status refresh for this long = offline (asleep / in recovery); 3x the node's default 30 s

_lock = Lock()

_nodes = defaultdict(lambda: {
    "last_update": None,
    "last_heartbeat": None,
    "current": {"overall_dbfs": None, "bands": {}, "ip": None},
    "history": deque(maxlen=HISTORY_SIZE),
    "history_acc": {"sum_power": 0, "count": 0, "bands": {}, "last_sec": 0},
    "firmware_version": "unknown",
    "hostname": None,
    "ip": None,
    "gain": None,
    "sleeping": False,
    "in_recovery": False,
    "status_online": None,  # from the retained esp32 status / LWT; None until the first status arrives
})


def get_all_nodes() -> dict:
    return dict(_nodes)


def update_node_data(node_id: str, overall_dbfs: float, bands: dict, seq, esp_ts, recv_time: float):
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
            "ip": node["ip"],
        }

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


def update_status(node_id: str, status: dict):
    """Apply a retained esp32-base status (or its {"online": false} LWT)."""
    app_status = status.get("app_status") or {}
    with _lock:
        node = _nodes[node_id]
        node["last_heartbeat"] = time.time()
        node["status_online"] = bool(status.get("online", True))
        if not node["status_online"]:
            return
        node["in_recovery"] = status.get("role") == "recovery"
        node["sleeping"] = bool(app_status.get("sleeping", False))
        if status.get("version"):
            node["firmware_version"] = status["version"]
        if status.get("hostname"):
            node["hostname"] = status["hostname"]
        if status.get("ip"):
            node["ip"] = status["ip"]
            node["current"]["ip"] = status["ip"]
        if app_status.get("gain") is not None:
            node["gain"] = app_status["gain"]


def get_node_status(node_id: str, db_nodes: dict) -> dict:
    now = time.time()
    with _lock:
        data = _nodes[node_id]
        last_update = data["last_update"]
        last_heartbeat = data["last_heartbeat"]
        is_sleeping = data["sleeping"]
        in_recovery = data["in_recovery"]
        status_fresh = bool(last_heartbeat and (now - last_heartbeat) < STATUS_TIMEOUT_S)

        if data["status_online"] is False:
            is_online = False
        elif in_recovery or is_sleeping:
            is_online = status_fresh
        else:
            is_online = bool(last_update and (now - last_update) < DATA_TIMEOUT_S)

        db_node = db_nodes.get(node_id, {})
        return {
            "online": is_online,
            "sleeping": is_sleeping,
            "in_recovery": in_recovery and status_fresh,
            "last_update": last_update,
            "current": data["current"],
            "firmware_version": data.get("firmware_version", "unknown"),
            "hostname": data["hostname"],
            "ip": data["ip"],
            "gain": data["gain"],
            "display_name": db_node.get("display_name", node_id),
        }


def is_known(node_id: str) -> bool:
    with _lock:
        return node_id in _nodes


def get_node_history(node_id: str) -> list:
    with _lock:
        return list(_nodes[node_id]["history"])


def disconnect_node(node_id: str):
    with _lock:
        if node_id in _nodes:
            del _nodes[node_id]
