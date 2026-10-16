#!/bin/bash

# Build the soundspy firmware.
#
# Usage: ./scripts/build_firmware.sh [current|legacy]
#   current (default)  firmware/ — the Esp32Base-based sketch. Needs the Esp32Base library:
#                      either ESP32_BASE_DIR=<path to the library folder> or an Esp32Base
#                      folder in the Arduino libraries directory (init_arduino.sh links it).
#                      Output: builds/soundspy_v<APP_VERSION>.bin (+ soundspy_latest.bin) for OTA and
#                      soundspy_v<APP_VERSION>_FULL_FLASH.bin (bootloader + partitions + app, write at 0x0)
#                      for the first USB flash (./scripts/flash_wsl.sh or esptool).
#                      WiFi/MQTT settings are not baked in: the node takes them from NVS
#                      through its captive portal, so no .env is needed.
#   legacy             node_firmware/ + node_firmware/recovery_firmware/ (1.7.x). Reads .env to
#                      fill the PLACEHOLDER_* defaults and uses partitions.csv.
#                      Output: builds/soundspy_v<FIRMWARE_VERSION>.bin and soundspy_recovery_v*.bin.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

TARGET="${1:-current}"
FQBN="${FQBN:-esp32:esp32:esp32:FlashMode=dio}"

# Find arduino-cli
if [ -x "$PROJECT_ROOT/bin/arduino-cli" ]; then
    ARDUINO_CLI="$PROJECT_ROOT/bin/arduino-cli"
elif command -v arduino-cli &>/dev/null; then
    ARDUINO_CLI="arduino-cli"
else
    echo "Error: arduino-cli not found. Run: ./scripts/init_arduino.sh"
    exit 1
fi

OUTPUT_DIR="${BUILD_DIR:-builds}"   # BUILD_DIR overrides the output folder
mkdir -p "$OUTPUT_DIR"

# compile_sketch <sketch dir> <output bin> [extra arduino-cli args...]
# The sketch is copied to a temp dir named after its .ino so arduino-cli accepts it, and the
# repository partition table is dropped in when the caller asks for build.partitions=custom.
compile_sketch() {
    local SRC_DIR="$1" OUTPUT_BIN="$2"
    shift 2
    local NAME TEMP_DIR SKETCH_DIR RAW
    NAME="$(basename "$(ls "$SRC_DIR"/*.ino | head -1)" .ino)"
    TEMP_DIR=$(mktemp -d /tmp/soundspy_build_XXXXXX)
    SKETCH_DIR="$TEMP_DIR/$NAME"
    RAW="$TEMP_DIR/out"
    cp -r "$SRC_DIR" "$SKETCH_DIR"
    rm -rf "$SKETCH_DIR/recovery_firmware"          # nested sketch, built separately
    cp "$PROJECT_ROOT/partitions.csv" "$SKETCH_DIR/partitions.csv"

    "$ARDUINO_CLI" compile --fqbn "$FQBN" "$@" --output-dir "$RAW" "$SKETCH_DIR"

    cp "$RAW"/*.ino.bin "$OUTPUT_BIN"
    # Merged image (bootloader + partition table + app) for a first flash at 0x0
    [ -f "$RAW/$NAME.ino.merged.bin" ] && cp "$RAW/$NAME.ino.merged.bin" "${OUTPUT_BIN%.bin}_FULL_FLASH.bin"
    rm -rf "$TEMP_DIR"
}

build_current() {
    local VERSION LIB_ARGS=()
    VERSION=$(grep -m1 -oP '#define\s+APP_VERSION\s+"\K[^"]+' firmware/soundspy.ino)
    if [ -n "${ESP32_BASE_DIR:-}" ]; then
        [ -f "$ESP32_BASE_DIR/library.properties" ] || { echo "Error: ESP32_BASE_DIR=$ESP32_BASE_DIR has no library.properties"; exit 1; }
        LIB_ARGS=(--library "$ESP32_BASE_DIR")
    elif ! "$ARDUINO_CLI" lib list 2>/dev/null | grep -q '^Esp32Base'; then
        echo "Error: the Esp32Base library is not installed and ESP32_BASE_DIR is not set."
        echo "firmware/ needs it; see docs/firmware.md. The legacy sketch builds without it:"
        echo "  ./scripts/build_firmware.sh legacy"
        exit 1
    fi

    echo "=========================================="
    echo "Building soundspy firmware v${VERSION} (firmware/)"
    echo "=========================================="
    local BIN="$OUTPUT_DIR/soundspy_v${VERSION}.bin"
    # upload.maximum_size = the ota_0 slot of the 4 MB single-slot layout the nodes run (0x290000)
    compile_sketch firmware "$BIN" "${LIB_ARGS[@]}" --build-property "upload.maximum_size=2686976" \
        --build-property "compiler.optimization_flags=-Os -fno-exceptions -fno-asynchronous-unwind-tables -fno-unwind-tables"
    ln -sfn "$(basename "$BIN")" "$OUTPUT_DIR/soundspy_latest.bin"
    echo "=========================================="
    echo "Build successful: $BIN ($(du -h "$BIN" | cut -f1))"
    echo "First flash:  esptool --chip esp32 -p /dev/ttyUSB0 -b 921600 write-flash 0x0 ${BIN%.bin}_FULL_FLASH.bin"
    echo "OTA update:   upload $BIN through the node's system portal (/sys); see docs/firmware.md."
    echo "=========================================="
}

build_legacy() {
    if [ ! -f .env ]; then
        echo "Error: .env file not found (the legacy firmware takes its defaults from it)"
        exit 1
    fi
    # shellcheck disable=SC1091
    source .env

    local FIRMWARE_VERSION RECOVERY_VERSION
    FIRMWARE_VERSION=$(grep 'const char\* FIRMWARE_VERSION' node_firmware/node_firmware.ino | sed 's/.*= "//;s/".*//')
    RECOVERY_VERSION=$(grep 'RECOVERY_VERSION' node_firmware/recovery_firmware/recovery_firmware.ino | grep define | sed 's/.*"\(.*\)".*/\1/')

    # Render the PLACEHOLDER_* defaults from .env into a copy of the sketch (kept next to the
    # source as *.rendered.ino for Arduino IDE flashing; git-ignored because it holds secrets).
    local RENDERED_DIR
    RENDERED_DIR=$(mktemp -d /tmp/soundspy_render_XXXXXX)
    mkdir -p "$RENDERED_DIR/node_firmware"
    sed -e "s/PLACEHOLDER_WIFI_SSID/$WIFI_SSID/" \
        -e "s/PLACEHOLDER_WIFI_PASS/$WIFI_PASSWORD/" \
        -e "s/PLACEHOLDER_MQTT_HOST/$FIRMWARE_MQTT_HOST/" \
        -e "s/PLACEHOLDER_MQTT_PORT/$FIRMWARE_MQTT_PORT/" \
        -e "s/PLACEHOLDER_WS_HOST/$FIRMWARE_WS_HOST/" \
        -e "s/PLACEHOLDER_WS_PORT/$FIRMWARE_WS_PORT/" \
        node_firmware/node_firmware.ino > "$RENDERED_DIR/node_firmware/node_firmware.ino"
    cp "$RENDERED_DIR/node_firmware/node_firmware.ino" node_firmware/node_firmware.rendered.ino

    local PART_ARGS=(--build-property "build.partitions=custom" --build-property "upload.maximum_size=1441792")

    echo "=========================================="
    echo "Building legacy soundspy firmware v${FIRMWARE_VERSION} (node_firmware/)"
    echo "=========================================="
    echo "Compiling main firmware..."
    compile_sketch "$RENDERED_DIR/node_firmware" "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin" "${PART_ARGS[@]}"
    rm -rf "$RENDERED_DIR"

    echo "Compiling recovery firmware v${RECOVERY_VERSION}..."
    compile_sketch node_firmware/recovery_firmware "$OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin" "${PART_ARGS[@]}"

    ln -sfn "soundspy_v${FIRMWARE_VERSION}.bin" "$OUTPUT_DIR/soundspy_latest.bin"

    echo "=========================================="
    echo "Build successful!"
    echo "Main:     $OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin ($(du -h "$OUTPUT_DIR/soundspy_v${FIRMWARE_VERSION}.bin" | cut -f1))"
    echo "Recovery: $OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin ($(du -h "$OUTPUT_DIR/soundspy_recovery_v${RECOVERY_VERSION}.bin" | cut -f1))"
    echo "=========================================="
    echo ""
    echo "Initial USB flash: ./scripts/flash_initial.sh /dev/ttyUSB0"
    echo "OTA update:        ./scripts/deploy_ota.sh <chip_id>"
}

case "$TARGET" in
    current) build_current ;;
    legacy)  build_legacy ;;
    *) echo "Usage: $0 [current|legacy]"; exit 1 ;;
esac
