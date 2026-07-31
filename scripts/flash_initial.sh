#!/bin/bash

# Initial USB flash for soundspy nodes.
# Flashes: custom partition table, bootloader, recovery firmware (factory),
#          main firmware (ota_0), and writes WiFi/MQTT credentials to NVS.
#
# Usage: ./scripts/flash_initial.sh [port]
#   port defaults to /dev/ttyUSB0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PORT="${1:-/dev/ttyUSB0}"

if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi
source .env

# Find arduino-cli
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
elif command -v arduino-cli &>/dev/null; then
    ARDUINO_CLI="arduino-cli"
else
    echo "Error: arduino-cli not found"
    exit 1
fi

# Find esptool (bundled with ESP32 arduino core)
ESPTOOL=$(find ~/.arduino15/packages/esp32 -name "esptool.py" 2>/dev/null | head -1)
if [ -z "$ESPTOOL" ]; then
    ESPTOOL=$(command -v esptool.py 2>/dev/null || true)
fi
if [ -z "$ESPTOOL" ]; then
    echo "Error: esptool.py not found"
    exit 1
fi

# Find bootloader and boot_app0 from arduino core
CORE_PATH=$(find ~/.arduino15/packages/esp32/hardware/esp32 -maxdepth 1 -type d | sort -V | tail -1)
BOOTLOADER="$CORE_PATH/tools/sdk/esp32/bin/bootloader_qio_80m.bin"
BOOT_APP0="$CORE_PATH/tools/partitions/boot_app0.bin"

# Find built binaries
FIRMWARE_VERSION=$(grep 'const char\* FIRMWARE_VERSION' node_firmware/node_firmware.ino | sed 's/.*= "//;s/".*//')
RECOVERY_VERSION=$(grep 'define RECOVERY_VERSION' node_firmware/recovery_firmware/recovery_firmware.ino | sed 's/.*"//;s/".*//')
MAIN_BIN="builds/soundspy_v${FIRMWARE_VERSION}.bin"
RECOVERY_BIN="builds/soundspy_recovery_v${RECOVERY_VERSION}.bin"
PARTITIONS_BIN=$(find ~/.arduino15/packages/esp32 -name "gen_esp32part.py" 2>/dev/null | head -1)

echo "=========================================="
echo "soundspy Initial Flash"
echo "=========================================="
echo "Port:     $PORT"
echo "Main:     $MAIN_BIN"
echo "Recovery: $RECOVERY_BIN"
echo "=========================================="

# Generate binary partition table from CSV
PARTITIONS_CSV="$PROJECT_ROOT/partitions.csv"
PARTITIONS_OUT="$PROJECT_ROOT/builds/partitions.bin"
python3 "$PARTITIONS_BIN" -q "$PARTITIONS_CSV" "$PARTITIONS_OUT"
echo "Partition table generated: $PARTITIONS_OUT"

echo ""
echo "Flashing... (chip must be in download mode)"
echo ""

python3 "$ESPTOOL" \
    --chip esp32 \
    --port "$PORT" \
    --baud 921600 \
    --before default_reset \
    --after hard_reset \
    write_flash \
    --flash_mode dio \
    --flash_freq 80m \
    --flash_size 4MB \
    0x1000  "$BOOTLOADER" \
    0x8000  "$PARTITIONS_OUT" \
    0xe000  "$BOOT_APP0" \
    0x10000 "$RECOVERY_BIN" \
    0x90000 "$MAIN_BIN"

echo ""
echo "=========================================="
echo "Flash complete!"
echo "=========================================="
echo ""
echo "Writing credentials to NVS..."

# Write credentials using arduino-cli's NVS tool, or via a small sketch
# We use a Python nvs generator if available, otherwise print manual instructions
NVS_GEN=$(find ~/.arduino15/packages/esp32 -name "nvs_flash_gen.py" 2>/dev/null | head -1)
if [ -n "$NVS_GEN" ]; then
    # Generate NVS partition image
    NVS_CSV=$(mktemp /tmp/soundspy_nvs_XXXXXX.csv)
    cat > "$NVS_CSV" << EOF
key,type,encoding,value
soundspy,namespace,,
wifi_ssid,data,string,$WIFI_SSID
wifi_pass,data,string,$WIFI_PASSWORD
mqtt_host,data,string,$FIRMWARE_MQTT_HOST
mqtt_port,data,i32,$FIRMWARE_MQTT_PORT
ws_host,data,string,$FIRMWARE_WS_HOST
ws_port,data,i32,$FIRMWARE_WS_PORT
EOF
    NVS_BIN=$(mktemp /tmp/soundspy_nvs_XXXXXX.bin)
    python3 "$NVS_GEN" "$NVS_CSV" "$NVS_BIN" 0x5000
    python3 "$ESPTOOL" --chip esp32 --port "$PORT" --baud 921600 \
        write_flash 0x9000 "$NVS_BIN"
    rm -f "$NVS_CSV" "$NVS_BIN"
    echo "Credentials written to NVS."
else
    echo ""
    echo "NOTE: nvs_flash_gen.py not found."
    echo "The firmware will use compiled-in defaults on first boot."
    echo "Open the recovery portal after first boot to set credentials:"
    echo "  http://<device-ip>  (if WiFi connects)"
    echo "  http://192.168.4.1  (if AP mode, connect to '$WIFI_SSID_AP')"
fi

echo ""
echo "Node will boot into recovery on first start."
echo "Open http://<device-ip> or http://192.168.4.1 to configure."
