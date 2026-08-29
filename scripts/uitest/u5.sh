#!/usr/bin/env bash
# U5 — same as U4 but on large-1500, plus measuring Tab -> edit-field latency.
# Root is selected by default at launch, so Tab adds a child of the root.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

T0=$(python3 -c 'import time; print(int(time.time()*1000))')
uit_launch large-1500 90 >/dev/null || { uit_report U5 1 "app launch failed"; exit 1; }
LOAD=$(( $(python3 -c 'import time; print(int(time.time()*1000))') - T0 ))
sleep 1

LAT=$($UIT_DIR/tablatency.jxa 6000 2>/dev/null)   # MS=<n> | TIMEOUT before=<role> | PRE_EDITED
uit_type "HELLO"
sleep 0.2
uit_key 53                                        # Esc
sleep 0.5
uit_quit_flush

SLOT="$TABS/$SLOT_ID.mindmap"
CNT=$(python3 "$UIT_DIR/treecompare.py" count "$SLOT")
NEW=$(python3 "$UIT_DIR/treecompare.py" lastchild N-0000 "$SLOT")

LATVAL="${LAT:-none}"
if [[ "$LAT" == MS=* && "$NEW" == "HELLO" && "$CNT" == "1501" ]]; then
  echo "PASS U5 (tab2edit=${LAT#MS=}ms load=${LOAD}ms)"
else
  screencapture -x "$ART_DIR/U5.png" 2>/dev/null || true
  echo "FAIL U5: new-root-child='$NEW' (expect HELLO), nodes=$CNT (expect 1501), tab2edit=$LATVAL, load=${LOAD}ms (shot=$ART_DIR/U5.png)"
fi
