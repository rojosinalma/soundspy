#!/usr/bin/env bash
# Usage: ./scripts/bump_version.sh <new-version|major|minor|patch>
# Updates the VERSION file, the firmware APP_VERSION and the dashboard DASHBOARD_VERSION.

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
        echo "Usage: $0 <new-version|major|minor|patch>  (e.g. 2.2.0 or patch)"
        exit 1
        ;;
    *)     NEW_VERSION="${1}" ;;
esac

FIRMWARE="$ROOT/firmware/soundspy.ino"
DASHBOARD="$ROOT/dashboard/app.py"

if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
    echo "Already at version $NEW_VERSION"
    exit 0
fi

echo "Bumping $OLD_VERSION -> $NEW_VERSION"

echo "$NEW_VERSION" > "$VERSION_FILE"
sed -i "s/#define APP_VERSION \"[^\"]*\"/#define APP_VERSION \"$NEW_VERSION\"/" "$FIRMWARE"
sed -i "s/DASHBOARD_VERSION = \"[^\"]*\"/DASHBOARD_VERSION = \"$NEW_VERSION\"/" "$DASHBOARD"

echo "Updated:"
echo "  VERSION"
echo "  firmware/soundspy.ino"
echo "  dashboard/app.py"
echo ""
echo "Add a ## [$NEW_VERSION] section to CHANGELOG.md, then commit:"
echo "  git add VERSION CHANGELOG.md firmware/soundspy.ino dashboard/app.py"
echo "  git commit -m \"v$NEW_VERSION: <description>\""
echo "  git push"
