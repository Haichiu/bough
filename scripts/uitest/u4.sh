#!/usr/bin/env bash
# U4 — select node, Tab (add child), immediately type HELLO, Esc.
# The new node's text must be exactly "HELLO" — catches leading keystrokes
# being swallowed as canvas shortcuts during the edit-focus window.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

uit_launch small-20 30 >/dev/null || { uit_report U4 1 "app launch failed"; exit 1; }
sleep 0.5

DUMP=$(uit_axdump)
read -r CX CY <<<"$(uit_node_coords "$DUMP" N-0007)"
[[ -z "${CX:-}" ]] && { uit_report U4 1 "node N-0007 not found"; exit 1; }
uit_click "$CX" "$CY"      # select
sleep 0.6

uit_key 48                   # Tab -> addChild + editing on the new node
sleep 0.2
uit_type "HELLO"
sleep 0.2
uit_key 53                   # Esc
sleep 0.5
uit_quit_flush

SLOT="$TABS/$SLOT_ID.mindmap"
CNT=$(python3 "$UIT_DIR/treecompare.py" count "$SLOT")
NEW=$(python3 "$UIT_DIR/treecompare.py" lastchild N-0007 "$SLOT")
HELLO_N=$(python3 "$UIT_DIR/treecompare.py" findtext HELLO "$SLOT")

if [[ "$NEW" == "HELLO" && "$CNT" == "21" ]]; then
  uit_report U4 0
else
  uit_report U4 1 "new-node-under-N-0007='$NEW' (expect HELLO), HELLO-count=$HELLO_N, nodes=$CNT (expect 21)"
fi
