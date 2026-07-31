#!/bin/bash
# Open serial monitors for one or more USB ports.
# Usage: ./scripts/serial_monitor.sh [0] [1] [2] ...
# Example: ./scripts/serial_monitor.sh 0 1 2

BAUD=115200

# Default to all available ttyUSB ports if none specified
if [ $# -eq 0 ]; then
    ARGS=$(ls /dev/ttyUSB* 2>/dev/null | grep -o '[0-9]*$')
    if [ -z "$ARGS" ]; then
        echo "No /dev/ttyUSB* devices found."
        exit 1
    fi
    set -- $ARGS
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
