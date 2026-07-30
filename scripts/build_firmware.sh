#!/bin/bash

# Build firmware — only injects FIRMWARE_VERSION from .env
# All other config (WiFi, MQTT, WS) is hardcoded in node_firmware.ino
#
# Usage: ./scripts/build_firmware.sh [NODE_ID]
#   NODE_ID: Optional override for output filename (default: reads from .ino)

set -e

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load environment for version
if [ ! -f .env ]; then
    echo "Error: .env file not found in project root."
    exit 1
fi

source .env

# Determine NODE_ID for output filename
if [ -n "$1" ]; then
    NODE_ID="$1"
else
    NODE_ID=$(grep 'const char\* NODE_ID' node_firmware/node_firmware.ino | sed 's/.*= "//;s/".*//')
fi

echo "=========================================="
echo "Building soundspy firmware"
echo "=========================================="
echo "Node ID: $NODE_ID"
echo "Firmware Version: $FIRMWARE_VERSION"
echo "=========================================="

# Create temporary sketch directory (arduino-cli requires directory structure)
TEMP_DIR=$(mktemp -d /tmp/soundspy_build_XXXXXX)
TEMP_SKETCH_NAME="soundspy_temp"
TEMP_SKETCH_DIR="$TEMP_DIR/$TEMP_SKETCH_NAME"
mkdir -p "$TEMP_SKETCH_DIR"
TEMP_INO="$TEMP_SKETCH_DIR/${TEMP_SKETCH_NAME}.ino"
INPUT_INO="node_firmware/node_firmware.ino"

# Inject version and WiFi password (secrets stay in .env, not in committed source)
sed -e "s/const char\* FIRMWARE_VERSION = \".*\"/const char* FIRMWARE_VERSION = \"$FIRMWARE_VERSION\"/" \
    -e "s/const char\* WIFI_PASS.*= \".*\"/const char* WIFI_PASS  = \"$WIFI_PASSWORD\"/" \
    "$INPUT_INO" > "$TEMP_INO"

# Check if arduino-cli is available (project bin or system PATH)
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
elif command -v arduino-cli &> /dev/null; then
    ARDUINO_CLI="arduino-cli"
else
    echo "Error: arduino-cli not found. Install it first:"
    echo "  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh"
    echo "  or run: ./scripts/init_arduino.sh"
    exit 1
fi

# Compile firmware
OUTPUT_DIR="builds"
mkdir -p "$OUTPUT_DIR"

echo "Compiling..."
"$ARDUINO_CLI" compile --fqbn esp32:esp32:esp32 "$TEMP_SKETCH_DIR" --output-dir "$OUTPUT_DIR"

# Rename output file
OUTPUT_BIN="$OUTPUT_DIR/soundspy_${NODE_ID}_v${FIRMWARE_VERSION}.bin"
LATEST_LINK="$OUTPUT_DIR/soundspy_${NODE_ID}.bin"

mv "$OUTPUT_DIR/${TEMP_SKETCH_NAME}.ino.bin" "$OUTPUT_BIN" 2>/dev/null || \
    mv "$OUTPUT_DIR"/*.bin "$OUTPUT_BIN" 2>/dev/null || true

rm -f "$LATEST_LINK"
ln -s "$(basename "$OUTPUT_BIN")" "$LATEST_LINK"

# Cleanup
rm -rf "$TEMP_DIR"

if [ -f "$OUTPUT_BIN" ]; then
    echo "=========================================="
    echo "Build successful!"
    echo "Output: $OUTPUT_BIN"
    echo "Version: v$FIRMWARE_VERSION"
    echo "Size: $(du -h "$OUTPUT_BIN" | cut -f1)"
    echo "=========================================="
    echo ""
    echo "Deploy: ./scripts/deploy_ota.sh $NODE_ID"
    echo "USB:    arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 --input-file $OUTPUT_BIN"
else
    echo "Error: Build failed, binary not found"
    exit 1
fi
