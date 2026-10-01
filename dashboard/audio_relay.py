"""
Pulls the raw PCM stream from each online node and fans it out to the browsers as
Socket.IO ``audio_data`` events (base64 s16le mono chunks).

A node runs a TCP server (``app_status.stream_port``) that sends one JSON header line and
then raw PCM. One relay thread per node, started only while at least one browser is
connected, so an unattended dashboard costs the nodes nothing.
"""

import base64
import json
import socket
import threading
import time

MAX_RELAYS = 16                 # bound on concurrent node streams
CHUNK_BYTES = 4410              # 50 ms of s16le mono at 44.1 kHz, matches the node's write size
CONNECT_TIMEOUT_S = 3
READ_TIMEOUT_S = 5              # node stopped sending (asleep, dead) -> reconnect
RETRY_S = 5
HEADER_MAX_BYTES = 256

_lock = threading.Lock()
_relays: dict[str, "Relay"] = {}
_emit = None
_log = print
_listeners = 0


class Relay:
    def __init__(self, node_id: str):
        self.node_id = node_id
        self.ip = None
        self.port = 0
        self.active = False
        self.stop = False
        self.thread = threading.Thread(target=self._run, name=f"relay-{node_id}", daemon=True)
        self.connected = False

    def _run(self):
        while not self.stop:
            if not (self.active and self.ip and self.port and _listeners > 0):
                time.sleep(1)
                continue
            try:
                self._stream()
            except (OSError, ValueError) as e:
                if self.active:
                    _log(f"[relay] {self.node_id} {self.ip}:{self.port}: {e}, retry in {RETRY_S}s")
                    time.sleep(RETRY_S)

    def _stream(self):
        with socket.create_connection((self.ip, self.port), timeout=CONNECT_TIMEOUT_S) as s:
            s.settimeout(READ_TIMEOUT_S)
            header = _read_line(s)
            info = json.loads(header)
            _log(f"[relay] {self.node_id}: streaming {info.get('format')} {info.get('rate')} Hz from {self.ip}:{self.port}")
            self.connected = True
            try:
                while self.active and not self.stop and _listeners > 0:
                    chunk = _read_exact(s, CHUNK_BYTES)
                    _emit("audio_data", {"node_id": self.node_id, "audio": base64.b64encode(chunk).decode("ascii")})
            finally:
                self.connected = False
                _log(f"[relay] {self.node_id}: stream closed")


def _read_line(s: socket.socket) -> str:
    buf = b""
    while not buf.endswith(b"\n"):
        b = s.recv(1)
        if not b:
            raise OSError("closed before header")
        buf += b
        if len(buf) > HEADER_MAX_BYTES:
            raise ValueError("header too long")
    return buf.decode("utf-8")


def _read_exact(s: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        part = s.recv(n - len(buf))
        if not part:
            raise OSError("stream closed by node")
        buf.extend(part)
    return bytes(buf)


def init(emit, log=print):
    global _emit, _log
    _emit, _log = emit, log


def listener_connected():
    global _listeners
    with _lock:
        _listeners += 1


def listener_disconnected():
    global _listeners
    with _lock:
        _listeners = max(0, _listeners - 1)


def update(node_id: str, ip: str | None, port: int, active: bool):
    """Called on every node status: (re)target the node's relay or pause it."""
    with _lock:
        relay = _relays.get(node_id)
        if relay is None:
            if not active:
                return
            if len(_relays) >= MAX_RELAYS:
                _log(f"[relay] not relaying {node_id}: {MAX_RELAYS} relays already running")
                return
            relay = _relays[node_id] = Relay(node_id)
            relay.thread.start()
        relay.ip, relay.port, relay.active = ip, int(port or 0), bool(active and ip and port)


def status() -> dict:
    with _lock:
        return {nid: {"active": r.active, "connected": r.connected, "target": f"{r.ip}:{r.port}"} for nid, r in _relays.items()}
