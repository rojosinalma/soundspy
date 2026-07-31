#!/bin/bash

# Deploy firmware via OTA to a specific node
# Usage: ./scripts/deploy_ota.sh <chip_id> [firmware_bin]
#   chip_id: Node's chip ID (shown in dashboard or serial on boot)
#   firmware_bin: Optional path to .bin file (uses latest if not provided)

set -e

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load environment
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi
source .env

# Parse arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <chip_id> [firmware_bin]"
    echo ""
    echo "Examples:"
    echo "  $0 a1b2c3                              # Deploy latest build"
    echo "  $0 a1b2c3 builds/soundspy_v1.3.0.bin   # Deploy specific build"
    echo ""
    echo "The chip_id is shown in the dashboard or on serial during boot."
    exit 1
fi

CHIP_ID="$1"
DASHBOARD_URL="http://${FIRMWARE_MQTT_HOST}:${DASHBOARD_PORT}"

# Determine firmware binary
if [ -n "$2" ]; then
    FIRMWARE_BIN="$2"
else
    # Always resolve to the actual versioned file, never use the symlink directly
    FIRMWARE_BIN=$(ls -t builds/soundspy_v*.bin 2>/dev/null | head -1)
    if [ -z "$FIRMWARE_BIN" ]; then
        echo "Error: No firmware found in builds/"
        echo "Run: ./scripts/build_firmware.sh"
        exit 1
    fi
    echo "Using latest firmware: $FIRMWARE_BIN"
fi

if [ ! -f "$FIRMWARE_BIN" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_BIN"
    exit 1
fi

FIRMWARE_SIZE=$(du -h "$FIRMWARE_BIN" | cut -f1)
echo "=========================================="
echo "OTA Deployment"
echo "=========================================="
echo "Node (chip ID): $CHIP_ID"
echo "Firmware: $FIRMWARE_BIN ($FIRMWARE_SIZE)"
echo "Dashboard: $DASHBOARD_URL"
echo "=========================================="
echo ""

# Step 1: Upload firmware
echo "Uploading firmware..."
UPLOAD_RESPONSE=$(curl -s -X POST -F "firmware=@$FIRMWARE_BIN" "$DASHBOARD_URL/api/ota/upload")
echo "Upload response: $UPLOAD_RESPONSE"

# Extract firmware URL from response
FIRMWARE_URL_PATH=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['url'])" 2>/dev/null)
# Make absolute if the server returned a relative path
case "$FIRMWARE_URL_PATH" in
  http://*|https://*) FIRMWARE_URL="$FIRMWARE_URL_PATH" ;;
  *) FIRMWARE_URL="${DASHBOARD_URL}${FIRMWARE_URL_PATH}" ;;
esac

if [ -z "$FIRMWARE_URL" ]; then
    echo "Error: Failed to upload firmware"
    exit 1
fi

echo "Firmware URL: $FIRMWARE_URL"
echo ""

# Step 2: Trigger OTA update
echo "Triggering OTA update for $CHIP_ID..."
TRIGGER_RESPONSE=$(curl -s -X POST "$DASHBOARD_URL/api/ota/trigger" \
  -H "Content-Type: application/json" \
  -d "{\"node_id\": \"$CHIP_ID\", \"firmware_url\": \"$FIRMWARE_URL\"}")

echo "Trigger response: $TRIGGER_RESPONSE"

SUCCESS=$(echo "$TRIGGER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null)

if [ "$SUCCESS" != "True" ]; then
    echo "Error: Failed to trigger OTA update"
    exit 1
fi

echo ""
echo "=========================================="
echo "OTA triggered — waiting for confirmation..."
echo "=========================================="

# Wait for OTA success confirmation and version reconnect
# Snapshot current log line count so we only watch new entries
LOG_OFFSET=$(docker logs soundspy_dashboard 2>&1 | wc -l)
CONFIRMED=false
TIMEOUT=120
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))

    NEW_LOGS=$(docker logs soundspy_dashboard 2>&1 | tail -n +$LOG_OFFSET)

    OTA_LOG=$(echo "$NEW_LOGS" | grep "\[ota\] $CHIP_ID" | tail -1)
    VERSION_LOG=$(echo "$NEW_LOGS" | grep "\[version\] $CHIP_ID" | grep "build=" | tail -1)

    if echo "$OTA_LOG" | grep -q "success"; then
        echo "[${ELAPSED}s] OTA download confirmed by device"
        CONFIRMED=true
    fi

    if [ "$CONFIRMED" = true ] && [ -n "$VERSION_LOG" ]; then
        BUILD=$(echo "$VERSION_LOG" | grep -o 'build=.*' | cut -d= -f2-)
        echo "[${ELAPSED}s] Device reconnected: $VERSION_LOG"
        echo ""
        echo "=========================================="
        echo "OTA successful!"
        echo "Build: $BUILD"
        echo "=========================================="
        exit 0
    fi

    printf "\r[${ELAPSED}s] Waiting..."
done

echo ""
echo "Timeout — check dashboard logs manually:"
echo "  docker logs -f soundspy_dashboard"
