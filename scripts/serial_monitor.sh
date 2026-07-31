#!/bin/bash
# Open serial monitors for one or more USB ports.
# Usage: ./scripts/serial_monitor.sh [0] [1] [2] ...
# Example: ./scripts/serial_monitor.sh 0 1 2

BAUD=115200

if [ $# -eq 0 ]; then
    echo "Usage: $0 <port> [port ...]"
    echo "Example: $0 0 1 2   (opens /dev/ttyUSB0, ttyUSB1, ttyUSB2)"
    exit 1
fi

for N in "$@"; do
    PORT="/dev/ttyUSB${N}"
    if [ ! -e "$PORT" ]; then
        echo "[$PORT] not found, skipping"
        continue
    fi
    sudo chmod a+rw "$PORT"
    echo "[$PORT] opening at ${BAUD} baud..."
    stty -F "$PORT" "$BAUD" raw -echo
done

# Tail all ports with port label prefix
PORTS=()
for N in "$@"; do
    PORT="/dev/ttyUSB${N}"
    [ -e "$PORT" ] && PORTS+=("$PORT")
done

if [ ${#PORTS[@]} -eq 0 ]; then
    echo "No valid ports found."
    exit 1
fi

echo "--- Monitoring ${PORTS[*]} (Ctrl+C to stop) ---"
tail -f "${PORTS[@]}" 2>/dev/null | while IFS= read -r line; do
    echo "$line"
done
