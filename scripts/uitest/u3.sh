#!/usr/bin/env bash
# U3 — drag-misfire detection on node N-0006 (small-20).
#   U3a: press, move 3px, release  -> must be a CLICK: tree on disk identical to fixture.
#   U3b: press, move 12px down, release -> lands inside next sibling N-0007's frame,
#        so a real drag must reparent N-0006 under N-0007 (tree changes).
# Both verdicts compare the autosave slot JSON against the pristine fixture.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

FIX="$PROJ/scripts/fixtures/small-20.mindmap"
SLOT="$TABS/$SLOT_ID.mindmap"

# ---------- U3a: 3px ----------
uit_launch small-20 30 >/dev/null || { uit_report U3a 1 "app launch failed"; exit 1; }
sleep 0.5
DUMP=$(uit_axdump)
read -r CX6 CY6 <<<"$(uit_node_coords "$DUMP" N-0006)"
[[ -z "${CX6:-}" ]] && { uit_report U3a 1 "node N-0006 not found"; exit 1; }
"$UIT_DIR/mouse.jxa" drag "$CX6" "$CY6" "$((CX6 + 3))" "$CY6" 3 >/dev/null
sleep 0.4
uit_quit_flush
if DIFF=$(python3 "$UIT_DIR/treecompare.py" identical "$FIX" "$SLOT"); then
  uit_report U3a 0
else
  uit_report U3a 1 "tree changed after 3px drag: $DIFF (expect identical)"
fi

# ---------- U3b: 12px onto N-0007 ----------
uit_launch small-20 30 >/dev/null || { uit_report U3b 1 "relaunch failed"; exit 1; }
sleep 0.5
DUMP=$(uit_axdump)
read -r CX6 CY6 <<<"$(uit_node_coords "$DUMP" N-0006)"
read -r X7 Y7 W7 H7 <<<"$(awk -F'\t' '$1=="AXStaticText" && $6=="N-0007"{print $2,$3,$4,$5; exit}' <<<"$DUMP")"
[[ -z "${CX6:-}" || -z "${X7:-}" ]] && { uit_report U3b 1 "nodes not found in AX tree"; exit 1; }
TX=$((CX6)); TY=$((CY6 + 12))
GEO_OK=$(awk -v tx="$TX" -v ty="$TY" -v x="$X7" -v y="$Y7" -v w="$W7" -v h="$H7" \
  'BEGIN{m=(tx>=x-8 && tx<=x+w+8 && ty>=y-8 && ty<=y+h+8)?1:0; print m}')

"$UIT_DIR/mouse.jxa" drag "$CX6" "$CY6" "$TX" "$TY" 4 >/dev/null
sleep 0.4
uit_quit_flush
PARENT=$(python3 "$UIT_DIR/treecompare.py" parentof N-0006 "$SLOT" 2>/dev/null)
if [[ "$PARENT" == "N-0007" ]]; then
  uit_report U3b 0
else
  uit_report U3b 1 "after 12px drag parent(N-0006)='$PARENT' (expect N-0007); geo-ok=$GEO_OK"
fi
