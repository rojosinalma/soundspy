#!/bin/bash
# Flash soundspy full firmware image from WSL.
# Run from the project root on the Windows desktop PC.
# Usage: ./scripts/flash_wsl.sh [port]
#   port defaults to /dev/ttyUSB0 (check Device Manager for COM# then use /dev/ttyUSBx or /dev/ttyS<n>)

set -e

PORT="${1:-/dev/ttyUSB0}"

# Find the latest FULL_FLASH binary
FIRMWARE_BIN=$(ls -t builds/soundspy_v*_FULL_FLASH.bin 2>/dev/null | head -1)
if [ -z "$FIRMWARE_BIN" ]; then
    echo "Error: No FULL_FLASH binary found in builds/"
    echo "Expected: builds/soundspy_v*_FULL_FLASH.bin"
    exit 1
fi

# Find esptool
if command -v esptool &>/dev/null; then
    ESPTOOL="esptool"
elif python3 -m esptool version &>/dev/null 2>&1; then
    ESPTOOL="python3 -m esptool"
elif command -v esptool.py &>/dev/null; then
    ESPTOOL="esptool.py"
else
    echo "esptool not found. Install it with:"
    echo "  pip install esptool"
    exit 1
fi

echo "=========================================="
echo "soundspy WSL Flash"
echo "=========================================="
echo "Port:     $PORT"
echo "Firmware: $FIRMWARE_BIN"
echo "=========================================="
echo ""
# Check port access
if [ ! -e "$PORT" ]; then
    echo "Error: Port $PORT not found."
    echo "Check usbipd is attached and try: ls /dev/ttyUSB* /dev/ttyS*"
    exit 1
fi
if [ ! -w "$PORT" ]; then
    echo "Error: Permission denied on $PORT."
    echo "Fix with: sudo chmod a+rw $PORT"
    echo "Or permanently: sudo usermod -aG dialout \$USER  (then re-login)"
    exit 1
fi

read -rp "Press Enter when ready..."

$ESPTOOL \
    --chip esp32 \
    --port "$PORT" \
    --baud 921600 \
    --before default-reset \
    --after hard-reset \
    write-flash \
    --flash-mode dio \
    --flash-freq 80m \
    --flash-size 4MB \
    0x0 "$FIRMWARE_BIN"

echo ""
echo "=========================================="
echo "Flash complete — node will reboot now"
echo "=========================================="
