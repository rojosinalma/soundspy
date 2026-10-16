#!/bin/bash

# Initialize Arduino CLI with required cores and libraries for soundspy
# This script installs the ESP32 core and the libraries both firmwares need.
#
# firmware/ (current) additionally builds against the Esp32Base library. Point ESP32_BASE_DIR
# at a checkout of that library (the folder holding its library.properties) and it is linked
# into the Arduino libraries folder; build_firmware.sh also accepts it directly.

set -e

echo "=========================================="
echo "Initializing Arduino CLI for soundspy"
echo "=========================================="

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Check if arduino-cli is available (project bin or system PATH)
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
    echo "Using project arduino-cli: $ARDUINO_CLI"
elif command -v arduino-cli &> /dev/null; then
    ARDUINO_CLI="arduino-cli"
    echo "Using system arduino-cli"
else
    echo "Error: arduino-cli not found."
    echo ""
    echo "Installation options:"
    echo "1. Install to project: cd bin && curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh"
    echo "2. Install system-wide: curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh"
    exit 1
fi

ARDUINO_CLI_VERSION=$("$ARDUINO_CLI" version | head -1)
echo "Found: $ARDUINO_CLI_VERSION"
echo ""

# Update index
echo "Updating board index..."
"$ARDUINO_CLI" core update-index

# Install ESP32 core
echo ""
echo "Installing ESP32 core..."
if "$ARDUINO_CLI" core list | grep -q "esp32:esp32"; then
    echo "ESP32 core already installed, updating..."
    "$ARDUINO_CLI" core upgrade esp32:esp32
else
    "$ARDUINO_CLI" core install esp32:esp32
fi

# Install required libraries
echo ""
echo "Installing required libraries..."

LIBRARIES=(
    "PubSubClient"      # MQTT client
    "WebSockets"        # WebSocket client for audio streaming
    "ArduinoJson"       # JSON parsing
)

for lib in "${LIBRARIES[@]}"; do
    echo "  - $lib"
    if "$ARDUINO_CLI" lib list | grep -q "^$lib"; then
        echo "    Already installed, upgrading..."
        "$ARDUINO_CLI" lib upgrade "$lib" || true
    else
        "$ARDUINO_CLI" lib install "$lib"
    fi
done

# Esp32Base (firmware/ only)
if [ -n "${ESP32_BASE_DIR:-}" ]; then
    if [ ! -f "$ESP32_BASE_DIR/library.properties" ]; then
        echo "Error: ESP32_BASE_DIR=$ESP32_BASE_DIR has no library.properties"
        exit 1
    fi
    LIB_DIR="$("$ARDUINO_CLI" config get directories.user 2>/dev/null)/libraries"
    mkdir -p "$LIB_DIR"
    echo ""
    echo "Linking Esp32Base from $ESP32_BASE_DIR into $LIB_DIR"
    ln -sfn "$(cd "$ESP32_BASE_DIR" && pwd)" "$LIB_DIR/Esp32Base"
else
    echo ""
    echo "ESP32_BASE_DIR not set: only the legacy node_firmware/ can be built."
    echo "firmware/ needs the Esp32Base library; see docs/firmware.md."
fi

echo ""
echo "=========================================="
echo "Initialization complete!"
echo "=========================================="
echo ""
echo "Installed components:"
"$ARDUINO_CLI" core list | grep esp32
echo ""
"$ARDUINO_CLI" lib list | grep -E "PubSubClient|WebSockets|ArduinoJson"
echo ""
echo "You can now build firmware with:"
echo "  ./scripts/build_firmware.sh            # firmware/ (needs Esp32Base)"
echo "  ./scripts/build_firmware.sh legacy     # node_firmware/ + recovery"
