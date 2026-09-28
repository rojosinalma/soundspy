#!/usr/bin/env bash
# Render the enclosure STLs + previews and run the fit check, via the OpenSCAD Docker image.
# Usage: ./scripts/render_case.sh [-D 'param=value' ...]   (overrides passed to every render)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${OPENSCAD_IMAGE:-openscad/openscad:latest}"
OVERRIDES=("$@")

scad() {
    docker run --rm --init --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$ROOT/case:/work" -w /work "$IMAGE" "$@"
}

mkdir -p "$ROOT/case/stl" "$ROOT/case/preview"

echo "Fit check..."
fit_out="$(scad openscad "${OVERRIDES[@]}" -D 'part="fitcheck"' -o /tmp/fit.stl soundspy-case.scad 2>&1 || true)"
if grep -q "top level object is empty" <<<"$fit_out"; then
    echo "  OK: no collisions"
else
    echo "  FAIL: case intersects board components (render part=\"fitcheck\" to see where)" >&2
    exit 1
fi

for part in base lid; do
    echo "Rendering $part..."
    scad openscad "${OVERRIDES[@]}" -D "part=\"$part\"" -o "stl/soundspy-case-$part.stl" soundspy-case.scad 2>/dev/null
done

echo "Rendering previews..."
VIEW=(--imgsize=1400,1050 --colorscheme=Tomorrow --autocenter --viewall)
scad xvfb-run -a openscad "${VIEW[@]}" "${OVERRIDES[@]}" -D 'part="assembly"' \
    --camera=0,0,0,60,0,35,0 -o preview/assembly.png soundspy-case.scad 2>/dev/null
scad xvfb-run -a openscad "${VIEW[@]}" "${OVERRIDES[@]}" --render -D 'part="base"' \
    --camera=0,0,0,45,0,200,0 -o preview/base.png soundspy-case.scad 2>/dev/null
scad xvfb-run -a openscad "${VIEW[@]}" "${OVERRIDES[@]}" --render -D 'part="lid"' \
    --camera=0,0,0,40,0,20,0 -o preview/lid.png soundspy-case.scad 2>/dev/null

ls -la "$ROOT/case/stl"
