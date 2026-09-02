#!/usr/bin/env bash
# U8: a restored document must open fully inside the AX-derived map canvas.
# Fixed artifact overwrites U8-ax.tsv; no unbounded accumulation.
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_prepare_storage || exit 1
AX_OUT="$ART_DIR/U8-ax.tsv"
FIX="$PROJ/scripts/fixtures/u7-style.mindmap"

uit_launch u7-style 30 >/dev/null || { uit_report U8 1 "launch failed"; exit 1; }
sleep 1
uit_axdump > "$AX_OUT"
uit_quit_flush
python3 ax_canvas_fit.py "$AX_OUT" "$FIX" \
  --tolerance "${U8_TOLERANCE:-1.0}" \
  --center-tolerance "${U8_CENTER_TOLERANCE:-3.1}"
