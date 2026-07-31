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

# Find esptool — try WSL pip install, system path, or Python module
if command -v esptool.py &>/dev/null; then
    ESPTOOL="esptool.py"
elif python3 -m esptool version &>/dev/null 2>&1; then
    ESPTOOL="python3 -m esptool"
elif command -v esptool &>/dev/null; then
    ESPTOOL="esptool"
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
echo "Put the ESP32 in flash mode:"
echo "  Hold BOOT, tap RST, release BOOT"
echo ""
read -rp "Press Enter when ready..."

$ESPTOOL \
    --chip esp32 \
    --port "$PORT" \
    --baud 921600 \
    --before default_reset \
    --after hard_reset \
    write_flash \
    --flash_mode dio \
    --flash_freq 80m \
    --flash_size 4MB \
    0x0 "$FIRMWARE_BIN"

echo ""
echo "=========================================="
echo "Flash complete — node will reboot now"
echo "=========================================="
