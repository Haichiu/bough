#!/usr/bin/env bash
# U7: exported SVG must match screen-relative geometry and NodeStyle values.
# Fixed artifacts overwrite U7-ax.tsv/U7.svg; no unbounded accumulation.
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_prepare_backup || exit 1
SVG_OUT="$ART_DIR/U7.svg"; AX_OUT="$ART_DIR/U7-ax.tsv"
FIX="$PROJ/scripts/fixtures/u7-style.mindmap"

uit_launch u7-style 30 >/dev/null || { uit_report U7 1 "launch failed"; exit 1; }
sleep 0.5
uit_axdump > "$AX_OUT"
if ! uit_export_svg "$SVG_OUT"; then
  uit_quit_flush; uit_report U7 1 "SVG export failed"; exit 1
fi
uit_quit_flush
python3 svg_compare.py "$AX_OUT" "$SVG_OUT" "$FIX" \
  --fonts "${U7_FONTS:-18,15,13}" --radii "${U7_RADII:-14,11,9}" \
  --root-fill "${U7_ROOT_FILL:-#3c4c62}" --deep-fill-opacity "${U7_DEEP_FILL_OPACITY:-0.12}" \
  --deep-stroke-opacity "${U7_DEEP_STROKE_OPACITY:-0.38}" \
  --deep-stroke-width "${U7_DEEP_STROKE_WIDTH:-1}" \
  --position-tolerance "${U7_POSITION_TOLERANCE:-0.016}" \
  --width-tolerance "${U7_WIDTH_TOLERANCE:-0.083}" \
  --height-tolerance "${U7_HEIGHT_TOLERANCE:-0.02}"
