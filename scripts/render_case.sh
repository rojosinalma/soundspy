#!/usr/bin/env bash
# Fit check + STL/PNG render of the enclosure with the OpenSCAD CLI.
# Usage: ./scripts/render_case.sh [-D 'param=value' ...]   (overrides passed to every render)
# OPENSCAD (default: openscad on PATH) selects the binary, e.g. a container:
#   OPENSCAD='docker run --rm -v $PWD:$PWD -w $PWD openscad/openscad:dev openscad'  (run from the repo root)
# The fit check relies on OpenSCAD exiting non-zero for empty geometry; the script treats
# "no geometry" (exit 3 on recent builds, or an empty STL) as "no collisions".
set -euo pipefail

CASE="$(cd "$(dirname "$0")/../case" && pwd)"
SCAD="$CASE/soundspy-case.scad"
OVERRIDES=("$@")
read -ra OPENSCAD_CMD <<< "${OPENSCAD:-openscad}"   # split on spaces: a plain binary or a container command line

render() { "${OPENSCAD_CMD[@]}" "$SCAD" "${OVERRIDES[@]}" "$@"; }

mkdir -p "$CASE/stl" "$CASE/preview"

echo "Fit check..."
FIT=/tmp/soundspy-fitcheck.stl
rm -f "$FIT"
set +e
render -D 'part="fitcheck"' -o "$FIT" >/dev/null 2>&1
rc=$?
set -e
if [ $rc -eq 3 ] || { [ $rc -eq 0 ] && ! grep -q 'vertex' "$FIT" 2>/dev/null; }; then
    echo "  OK: no collisions"
elif [ $rc -eq 0 ]; then
    echo "  FAIL: case intersects board components (render part=\"fitcheck\" to see where)" >&2; exit 1
else
    echo "  ERROR: fit check render failed (exit $rc)" >&2; exit 1
fi

for part in base lid tray test_usb tray_studs test_studs; do
    render -D "part=\"$part\"" -o "$CASE/stl/soundspy-case-$part.stl"
done

render -D 'part="assembly"'      --camera=0,0,0,60,0,35,0  -o "$CASE/preview/assembly.png"
render -D 'part="base"' --render --camera=0,0,0,45,0,200,0 -o "$CASE/preview/base.png"
render -D 'part="lid"'  --render --camera=0,0,0,40,0,20,0  -o "$CASE/preview/lid.png"
render -D 'part="tray"' --render --camera=0,0,0,50,0,210,0 -o "$CASE/preview/tray.png"
render -D 'part="tray_assembly"' --camera=0,0,0,55,0,30,0  -o "$CASE/preview/tray_assembly.png"
render -D 'part="test_usb"' --render --camera=0,0,0,55,0,25,0 -o "$CASE/preview/test_usb.png"
render -D 'part="test_studs"' --render --camera=0,0,0,50,0,30,0 -o "$CASE/preview/test_studs.png"
render -D 'part="test_studs"' --render --camera=3,65,1,55,0,25,22 --no-viewall -o "$CASE/preview/test_studs_closeup.png"
render -D 'part="test_studs_assembly"' --camera=0,0,0,55,0,30,0 -o "$CASE/preview/test_studs_assembly.png"
