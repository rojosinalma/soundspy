#!/bin/bash

# Build firmware with environment variables injected
# Usage: ./scripts/build_firmware.sh [NODE_NUMBER]
#   NODE_NUMBER: Optional number to append to NODE_PREFIX (e.g., 1, 2, 3)
#   If not provided, uses DEFAULT_NODE_ID from .env
#
# Examples:
#   ./scripts/build_firmware.sh 1    -> Builds node1 (if NODE_PREFIX=node)
#   ./scripts/build_firmware.sh 2    -> Builds node2
#   ./scripts/build_firmware.sh      -> Builds node1 (DEFAULT_NODE_ID)

set -e

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "Working from project root: $PROJECT_ROOT"

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found in project root. Copy .env.example to .env and configure it."
    exit 1
fi

source .env

# Determine NODE_ID
if [ -z "$1" ]; then
    # No argument provided, use default
    NODE_ID=$DEFAULT_NODE_ID
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    # Numeric argument, append to prefix
    NODE_ID="${NODE_PREFIX}${1}"
else
    # String argument, use as-is (for custom names)
    NODE_ID="$1"
fi

echo "=========================================="
echo "Building soundspy firmware"
echo "=========================================="
echo "Node ID: $NODE_ID"
echo "Firmware Version: $FIRMWARE_VERSION"
echo "WiFi SSID: $WIFI_SSID"
echo "MQTT Host: $MQTT_HOST:$MQTT_PORT"
echo "WebSocket: $WS_HOST:$WS_PORT"
echo "=========================================="

# Create temporary sketch directory (arduino-cli requires directory structure)
TEMP_DIR=$(mktemp -d /tmp/soundspy_build_XXXXXX)
TEMP_SKETCH_NAME="soundspy_temp"
TEMP_SKETCH_DIR="$TEMP_DIR/$TEMP_SKETCH_NAME"
mkdir -p "$TEMP_SKETCH_DIR"
TEMP_INO="$TEMP_SKETCH_DIR/${TEMP_SKETCH_NAME}.ino"
INPUT_INO="node_firmware/node_firmware.ino"

# Read template and inject values
sed -e "s/const char\* FIRMWARE_VERSION = \".*\"/const char* FIRMWARE_VERSION = \"$FIRMWARE_VERSION\"/" \
    -e "s/const char\* NODE_ID.*= \".*\"/const char* NODE_ID    = \"$NODE_ID\"/" \
    -e "s/const char\* WIFI_SSID.*= \".*\"/const char* WIFI_SSID  = \"$WIFI_SSID\"/" \
    -e "s/const char\* WIFI_PASS.*= \".*\"/const char* WIFI_PASS  = \"$WIFI_PASSWORD\"/" \
    -e "s/const char\* MQTT_HOST.*= \".*\"/const char* MQTT_HOST  = \"$MQTT_HOST\"/" \
    -e "s/const int.*MQTT_PORT.*= [0-9]*/const int   MQTT_PORT  = $MQTT_PORT/" \
    -e "s/const char\* WS_HOST.*= \".*\"/const char* WS_HOST    = \"$WS_HOST\"/" \
    -e "s/const int.*WS_PORT.*= [0-9]*/const int   WS_PORT    = $WS_PORT/" \
    "$INPUT_INO" > "$TEMP_INO"

echo "Generated temporary firmware file with injected values"

# Check if arduino-cli is available (project bin or system PATH)
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
    echo "Using project arduino-cli: $ARDUINO_CLI"
elif command -v arduino-cli &> /dev/null; then
    ARDUINO_CLI="arduino-cli"
    echo "Using system arduino-cli"
else
    echo "Error: arduino-cli not found. Install it first:"
    echo "  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh"
    echo "  or run: ./scripts/init_arduino.sh"
    exit 1
fi

# Compile firmware
OUTPUT_DIR="builds"
mkdir -p "$OUTPUT_DIR"

echo "Compiling firmware..."
echo "Note: Using temporary sketch, source is in node_firmware/"
"$ARDUINO_CLI" compile --fqbn esp32:esp32:esp32 "$TEMP_SKETCH_DIR" --output-dir "$OUTPUT_DIR"

# Rename output file (keep version history for recovery)
OUTPUT_BIN="$OUTPUT_DIR/soundspy_${NODE_ID}_v${FIRMWARE_VERSION}.bin"
LATEST_LINK="$OUTPUT_DIR/soundspy_${NODE_ID}.bin"

mv "$OUTPUT_DIR/${TEMP_SKETCH_NAME}.ino.bin" "$OUTPUT_BIN" 2>/dev/null || \
    mv "$OUTPUT_DIR"/*.bin "$OUTPUT_BIN" 2>/dev/null || true

# Create/update symlink to latest version for easy deployment
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
    echo "To upload via OTA:"
    echo "  ./scripts/deploy_ota.sh $NODE_ID"
    echo ""
    echo "Or manually:"
    echo "1. Open dashboard: http://$MQTT_HOST:$DASHBOARD_PORT"
    echo "2. Click 📡 Update button for node '$NODE_ID'"
    echo "3. Select file: $OUTPUT_BIN"
    echo ""
    echo "To flash via USB:"
    echo "  arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 --input-file $OUTPUT_BIN"
else
    echo "Error: Build failed, binary not found"
    exit 1
fi
