#!/usr/bin/env bash
# Fit check + STL/PNG render of the enclosure through the shared openscad service (scad-render).
# Usage: ./scripts/render_case.sh [-D 'param=value' ...]   (overrides passed to every render)
set -euo pipefail

CASE="$(cd "$(dirname "$0")/../case" && pwd)"
SCAD="$CASE/soundspy-case.scad"
OVERRIDES=("$@")

render() { scad-render "$SCAD" "${OVERRIDES[@]}" "$@"; }

mkdir -p "$CASE/stl" "$CASE/preview"

echo "Fit check..."
set +e
render -D 'part="fitcheck"' -o /tmp/soundspy-fitcheck.stl >/dev/null 2>&1
rc=$?
set -e
case $rc in
    3) echo "  OK: no collisions" ;;
    0) echo "  FAIL: case intersects board components (render part=\"fitcheck\" to see where)" >&2; exit 1 ;;
    *) echo "  ERROR: fit check render failed (exit $rc)" >&2; exit 1 ;;
esac

for part in base lid tray; do
    render -D "part=\"$part\"" -o "$CASE/stl/soundspy-case-$part.stl"
done

render -D 'part="assembly"'      --camera=0,0,0,60,0,35,0  -o "$CASE/preview/assembly.png"
render -D 'part="base"' --render --camera=0,0,0,45,0,200,0 -o "$CASE/preview/base.png"
render -D 'part="lid"'  --render --camera=0,0,0,40,0,20,0  -o "$CASE/preview/lid.png"
render -D 'part="tray"' --render --camera=0,0,0,50,0,210,0 -o "$CASE/preview/tray.png"
render -D 'part="tray_assembly"' --camera=0,0,0,55,0,30,0  -o "$CASE/preview/tray_assembly.png"
