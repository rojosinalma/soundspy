#!/usr/bin/env bash
# Usage: ./scripts/bump_version.sh <new-version|major|minor|patch>
# Updates VERSION file, firmware, and dashboard.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
OLD_VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

IFS='.' read -r MAJOR MINOR PATCH <<< "$OLD_VERSION"

case "${1}" in
    patch) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
    "")
        echo "Usage: $0 <new-version|major|minor|patch>  (e.g. 1.5.0 or patch)"
        exit 1
        ;;
    *)     NEW_VERSION="${1}" ;;
esac

FIRMWARE="$ROOT/node_firmware/node_firmware.ino"
DASHBOARD="$ROOT/dashboard/app.py"

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
