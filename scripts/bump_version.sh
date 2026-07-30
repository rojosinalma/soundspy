#!/usr/bin/env bash
# Usage: ./scripts/bump_version.sh <new-version>
# Updates VERSION file, firmware, and dashboard, then commits.

set -e

NEW_VERSION="${1}"

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <new-version>  (e.g. 1.5.0)"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
FIRMWARE="$ROOT/node_firmware/node_firmware.ino"
DASHBOARD="$ROOT/dashboard/dashboard.py"

OLD_VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
    echo "Already at version $NEW_VERSION"
    exit 0
fi

echo "Bumping $OLD_VERSION -> $NEW_VERSION"

# VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Firmware
sed -i "s/const char\* FIRMWARE_VERSION = \"$OLD_VERSION\"/const char* FIRMWARE_VERSION = \"$NEW_VERSION\"/" "$FIRMWARE"

# Dashboard
sed -i "s/DASHBOARD_VERSION = \"$OLD_VERSION\"/DASHBOARD_VERSION = \"$NEW_VERSION\"/" "$DASHBOARD"

echo "Updated:"
echo "  VERSION"
echo "  node_firmware/node_firmware.ino"
echo "  dashboard/dashboard.py"
echo ""
echo "Review changes, then commit with:"
echo "  git add VERSION node_firmware/node_firmware.ino dashboard/dashboard.py"
echo "  git commit -m \"v$NEW_VERSION: <description>\""
echo "  git push"
