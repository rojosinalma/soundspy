#!/bin/bash

# Deploy firmware via OTA to a specific node
# Usage: ./scripts/deploy_ota.sh <node_id> [firmware_bin]
#   node_id: Node to update (e.g., wall1, node1)
#   firmware_bin: Optional path to .bin file (auto-detects latest if not provided)

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
    echo "Usage: $0 <node_id> [firmware_bin]"
    echo ""
    echo "Examples:"
    echo "  $0 wall1                              # Auto-detect latest .bin"
    echo "  $0 wall1 builds/soundspy_node1_v0.8.3.bin"
    exit 1
fi

NODE_ID="$1"
DASHBOARD_URL="http://${FIRMWARE_MQTT_HOST}:${DASHBOARD_PORT}"

# Determine firmware binary
if [ -n "$2" ]; then
    FIRMWARE_BIN="$2"
else
    # Try to use the latest symlink for this node
    LATEST_LINK="builds/soundspy_${NODE_ID}.bin"
    if [ -L "$LATEST_LINK" ] && [ -f "$LATEST_LINK" ]; then
        FIRMWARE_BIN="$LATEST_LINK"
        REAL_FILE=$(readlink -f "$FIRMWARE_BIN")
        echo "Using latest firmware: $REAL_FILE"
    else
        # Fallback: find any matching .bin for this node
        FIRMWARE_BIN=$(ls -t builds/soundspy_${NODE_ID}_v*.bin 2>/dev/null | head -1)
        if [ -z "$FIRMWARE_BIN" ]; then
            echo "Error: No firmware found for node '$NODE_ID' in builds/"
            echo "Run: ./scripts/build_firmware.sh $NODE_ID"
            exit 1
        fi
        echo "Auto-detected firmware: $FIRMWARE_BIN"
    fi
fi

if [ ! -f "$FIRMWARE_BIN" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_BIN"
    exit 1
fi

FIRMWARE_SIZE=$(du -h "$FIRMWARE_BIN" | cut -f1)
echo "=========================================="
echo "OTA Deployment"
echo "=========================================="
echo "Node: $NODE_ID"
echo "Firmware: $FIRMWARE_BIN ($FIRMWARE_SIZE)"
echo "Dashboard: $DASHBOARD_URL"
echo "=========================================="
echo ""

# Step 1: Upload firmware
echo "Uploading firmware..."
UPLOAD_RESPONSE=$(curl -s -X POST -F "firmware=@$FIRMWARE_BIN" "$DASHBOARD_URL/api/ota/upload")
echo "Upload response: $UPLOAD_RESPONSE"

# Extract firmware URL from response
FIRMWARE_URL=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['url'])" 2>/dev/null)

if [ -z "$FIRMWARE_URL" ]; then
    echo "Error: Failed to upload firmware"
    exit 1
fi

echo "Firmware URL: $FIRMWARE_URL"
echo ""

# Step 2: Trigger OTA update
echo "Triggering OTA update for $NODE_ID..."
TRIGGER_RESPONSE=$(curl -s -X POST "$DASHBOARD_URL/api/ota/trigger" \
  -H "Content-Type: application/json" \
  -d "{\"node_id\": \"$NODE_ID\", \"firmware_url\": \"$FIRMWARE_URL\"}")

echo "Trigger response: $TRIGGER_RESPONSE"

SUCCESS=$(echo "$TRIGGER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null)

if [ "$SUCCESS" != "True" ]; then
    echo "Error: Failed to trigger OTA update"
    exit 1
fi

echo ""
echo "=========================================="
echo "OTA update initiated successfully!"
echo "=========================================="
echo ""
echo "The node will now:"
echo "  1. Download firmware (~30 seconds)"
echo "  2. Flash to memory (~10 seconds)"
echo "  3. Reboot and reconnect (~10 seconds)"
echo ""
echo "Monitor progress:"
echo "  Serial Monitor: 115200 baud (look for [IMPORTANT] messages)"
echo "  Dashboard: $DASHBOARD_URL"
echo "  Logs: docker logs -f soundspy_dashboard"
echo ""
echo "Check status in ~60 seconds:"
echo "  curl -s $DASHBOARD_URL/api/nodes | python3 -m json.tool"
