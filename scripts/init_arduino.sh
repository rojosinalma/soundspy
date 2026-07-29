#!/bin/bash

# Initialize Arduino CLI with required cores and libraries for soundspy
# This script installs ESP32 core and all required libraries

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
echo "  ./scripts/build_firmware.sh 1"
