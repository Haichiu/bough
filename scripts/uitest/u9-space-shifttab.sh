#!/usr/bin/env bash
# U9 (p1): does the keyboard model already do what the Owner asked for?
#
# Owner's request: after creating a node the default is node-level action; Enter /
# Tab / Shift+Tab keep adjusting nodes, and only Space starts editing.
#
# Source reading says Space is already bound to beginEditing(id:) with no
# replacement, and that Shift+Tab has no case at all. Source reading is not
# evidence for runtime behaviour in this project, so this probe measures it.
#
# Three phases, each with its own launch:
#   A  Space      -> enters editing AND leaves the node text intact
#   B  Shift+Tab  -> does it mutate the tree?
#   C  Tab        -> POSITIVE CONTROL. Without proving the harness can observe a
#                    node being created, phase B's "nothing happened" is
#                    indistinguishable from a broken probe.
set -u
cd "$(dirname "$0")"; source ./lib.sh

TARGET=N-0005
rc=0

phase(){ # <label> -> launches and selects TARGET, echoes "ok" or "fail:<why>"
  uit_launch small-20 30 >/dev/null || { echo "fail:launch"; return; }
  sleep 0.6
  uit_ime_switch
  local dump cx cy
  dump=$(uit_axdump)
  read -r cx cy <<<"$(uit_node_coords "$dump" "$TARGET")"
  if [[ -z "${cx:-}" || -z "${cy:-}" ]]; then echo "fail:node-not-found"; return; fi
  uit_click "$cx" "$cy"
  sleep 0.6
  echo ok
}

uit_prepare_storage || exit 1

# ---------- Phase A: Space ----------
r=$(phase A)
if [[ "$r" != ok ]]; then uit_report U9A 1 "setup $r"; exit 1; fi
uit_key 49                 # Space
sleep 1.0
A_editing=$(uit_canvas_editing)
uit_key 53                 # Esc, leave editing
sleep 0.5
uit_quit_flush
A_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
A_text=$(python3 treecompare.py findtext "$TARGET" "$TABS/$SLOT_ID.mindmap" 2>/dev/null)

# ---------- Phase B: Shift+Tab ----------
r=$(phase B)
if [[ "$r" != ok ]]; then uit_report U9B 1 "setup $r"; exit 1; fi
uit_require_frontmost
osascript -e 'tell application "System Events" to key code 48 using shift down' 2>/dev/null
sleep 1.0
B_editing=$(uit_canvas_editing)
uit_quit_flush
B_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)

# ---------- Phase C: Tab (positive control) ----------
r=$(phase C)
if [[ "$r" != ok ]]; then uit_report U9C 1 "setup $r"; exit 1; fi
uit_key 48                 # Tab
sleep 1.0
uit_quit_flush
C_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)

echo "U9 RESULT baseline=20"
echo "  A space:     editing='$A_editing' count=$A_count text-$TARGET-present=$A_text"
echo "  B shifttab:  editing='$B_editing' count=$B_count"
echo "  C tab(ctrl): count=$C_count"

# The control must fire first; if Tab did not create a node the whole run is void.
if [[ "$C_count" != "21" ]]; then
  uit_report U9 1 "POSITIVE CONTROL FAILED: Tab produced count=$C_count (want 21). Phase B is uninterpretable."
  exit 1
fi

if [[ "$A_editing" == "$TARGET" && "$A_count" == "20" && "$A_text" == "1" ]]; then
  echo "U9A PASS: Space entered editing on $TARGET, kept its text, created nothing"
else
  echo "U9A FAIL: want editing=$TARGET count=20 text=1"; rc=1
fi

if [[ "$B_count" == "20" ]]; then
  echo "U9B MEASURED: Shift+Tab changed nothing (count stayed 20) while the control proves creation is observable => Shift+Tab is UNBOUND"
else
  echo "U9B MEASURED: Shift+Tab changed the tree (count=$B_count) => it IS bound to something"
fi

uit_cleanup_all 2>/dev/null || true
exit $rc
