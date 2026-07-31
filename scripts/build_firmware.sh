#!/bin/bash

# Build main + recovery firmware for soundspy.
# Credentials are written to NVS by flash_initial.sh on first USB flash.
# Subsequent updates use OTA (deploy_ota.sh).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi
source .env

FIRMWARE_VERSION=$(grep 'const char\* FIRMWARE_VERSION' node_firmware/node_firmware.ino | sed 's/.*= "//;s/".*//')
RECOVERY_VERSION=$(grep 'RECOVERY_VERSION' node_firmware/recovery_firmware/recovery_firmware.ino | grep define | sed 's/.*"\(.*\)".*/\1/')

# Find arduino-cli
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
elif command -v arduino-cli &>/dev/null; then
    ARDUINO_CLI="arduino-cli"
else
    echo "Error: arduino-cli not found. Run: ./scripts/init_arduino.sh"
    exit 1
fi

OUTPUT_DIR="builds"
mkdir -p "$OUTPUT_DIR"

build_sketch() {
    local INPUT_INO="$1"
    local OUTPUT_BIN="$2"
    local INJECT="${3:-true}"

    TEMP_DIR=$(mktemp -d /tmp/soundspy_build_XXXXXX)
    TEMP_SKETCH_NAME="soundspy_temp"
    TEMP_SKETCH_DIR="$TEMP_DIR/$TEMP_SKETCH_NAME"
    mkdir -p "$TEMP_SKETCH_DIR"
    TEMP_INO="$TEMP_SKETCH_DIR/${TEMP_SKETCH_NAME}.ino"

    if [ "$INJECT" = "true" ]; then
        # Inject .env placeholders (still needed as NVS fallback defaults in firmware)
        sed -e "s/PLACEHOLDER_WIFI_SSID/$WIFI_SSID/" \
            -e "s/PLACEHOLDER_WIFI_PASS/$WIFI_PASSWORD/" \
            -e "s/PLACEHOLDER_MQTT_HOST/$FIRMWARE_MQTT_HOST/" \
            -e "s/PLACEHOLDER_MQTT_PORT/$FIRMWARE_MQTT_PORT/" \
            -e "s/PLACEHOLDER_WS_HOST/$FIRMWARE_WS_HOST/" \
            -e "s/PLACEHOLDER_WS_PORT/$FIRMWARE_WS_PORT/" \
            "$INPUT_INO" > "$TEMP_INO"
        cp "$TEMP_INO" "${INPUT_INO%.ino}.rendered.ino"
    else
        cp "$INPUT_INO" "$TEMP_INO"
    fi

    # Copy custom partition table into sketch dir (arduino-cli looks here for 'custom')
    cp "$PROJECT_ROOT/partitions.csv" "$TEMP_SKETCH_DIR/partitions.csv"

    "$ARDUINO_CLI" compile \
        --fqbn esp32:esp32:esp32 \
        --build-property "build.partitions=custom" \
        --build-property "upload.maximum_size=1441792" \
        "$TEMP_SKETCH_DIR" \
        --output-dir "$OUTPUT_DIR"

    mv "$OUTPUT_DIR/${TEMP_SKETCH_NAME}.ino.bin" "$OUTPUT_BIN" 2>/dev/null || \
        mv "$OUTPUT_DIR"/*.bin "$OUTPUT_BIN" 2>/dev/null || true

    rm -rf "$TEMP_DIR"
}

echo "=========================================="
echo "Building soundspy firmware v${FIRMWARE_VERSION}"
echo "=========================================="
echo "Compiling main firmware..."
build_sketch "node_firmware/node_firmware.ino" "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin" true

echo "Compiling recovery firmware v${RECOVERY_VERSION}..."
build_sketch "node_firmware/recovery_firmware/recovery_firmware.ino" "$OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin" false

# Update latest symlink
LATEST_LINK="$OUTPUT_DIR/soundspy_latest.bin"
rm -f "$LATEST_LINK"
ln -sf "$(basename "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin")" "$LATEST_LINK"

if [ -f "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin" ]; then
    echo "=========================================="
    echo "Build successful!"
    echo "Main:     $OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin ($(du -h "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin" | cut -f1))"
    echo "Recovery: $OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin ($(du -h "$OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin" | cut -f1))"
    echo "=========================================="
    echo ""
    echo "Initial USB flash: ./scripts/flash_initial.sh /dev/ttyUSB0"
    echo "OTA update:        ./scripts/deploy_ota.sh <chip_id>"
else
    echo "Error: Build failed"
    exit 1
fi
