#!/bin/bash

# Build firmware — injects secrets and network config from .env into placeholders
# Version is hardcoded in the .ino source.
#
# Usage: ./scripts/build_firmware.sh [NODE_ID]
#   NODE_ID: Optional override (default: from .env)

set -e

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load environment
if [ ! -f .env ]; then
    echo "Error: .env file not found in project root."
    exit 1
fi

source .env

# Extract version from .ino source (it's the one hardcoded value)
FIRMWARE_VERSION=$(grep 'const char\* FIRMWARE_VERSION' node_firmware/node_firmware.ino | sed 's/.*= "//;s/".*//')

# NODE_ID comes from .env, CLI arg overrides
if [ -n "$1" ]; then
    NODE_ID="$1"
elif [ -z "$NODE_ID" ]; then
    echo "Error: NODE_ID not set in .env and not passed as argument."
    exit 1
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

# Inject all config from .env into placeholders
sed -e "s/PLACEHOLDER_NODE_ID/$NODE_ID/" \
    -e "s/PLACEHOLDER_WIFI_SSID/$WIFI_SSID/" \
    -e "s/PLACEHOLDER_WIFI_PASS/$WIFI_PASSWORD/" \
    -e "s/PLACEHOLDER_MQTT_HOST/$FIRMWARE_MQTT_HOST/" \
    -e "s/PLACEHOLDER_MQTT_PORT/$FIRMWARE_MQTT_PORT/" \
    -e "s/PLACEHOLDER_WS_HOST/$FIRMWARE_WS_HOST/" \
    -e "s/PLACEHOLDER_WS_PORT/$FIRMWARE_WS_PORT/" \
    "$INPUT_INO" > "$TEMP_INO"

# Also write a rendered .ino for manual Arduino IDE flashing
cp "$TEMP_INO" "${INPUT_INO%.ino}.rendered.ino"

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
