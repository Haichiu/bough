#!/usr/bin/env bash
# U9 (T-052): Shift+Tab outdents; Space still edits without replacing; Tab still indents.
#
# Four phases, each with its own launch (uit_launch re-stages the fixture, so
# every phase starts from the same 20-node tree):
#   A  Space on N-0005     -> enters editing AND leaves the node text intact
#                             (T-049 regression guard, ITERATION-LOG row 20)
#   B1 Shift+Tab on N-0005 -> N-0005 is a grandchild (root -> N-0001 -> N-0005);
#                             its parent must become the former grandparent
#                             (N-0001 -> N-0000), exactly one parent edge changes,
#                             count unchanged: a move, not an add/delete
#   B2 Shift+Tab on N-0002 -> N-0002 is a root-level child with no grandparent;
#                             NO parent edge may change at all (text-keyed
#                             parent diff, immune to save-time id renormalisation)
#   C  Tab                 -> POSITIVE CONTROL: creates a node (count 21);
#                             without it "tree unchanged" is indistinguishable
#                             from a broken probe
#
# Selection is verified inside phase() by the Space path (A's own proven
# mechanism): a phase only proceeds past a click it has proven selected the
# intended node. osascript re-activates Bough before every synthetic
# keystroke and uit_require_frontmost gates it.
set -u
cd "$(dirname "$0")"; source ./lib.sh

TARGET=N-0005
B2_TARGET=N-0002
FIXTURE="$PROJ/scripts/fixtures/small-20.mindmap"
rc=0

phase(){ # <label> <node> -> verifies click selected that node via Space; sets P_EDITING
  uit_launch small-20 30 >/dev/null || { echo "fail:launch"; return; }
  sleep 0.6
  # Ghost panes steal focus back after the previous phase quits Bough; the
  # shared helpers gate on frontmost and exit(70) the subshell, so reclaim
  # focus here before touching the keyboard.
  local front i
  for i in 1 2 3 4 5; do
    osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1 || true
    sleep 0.5
    front=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
    [[ "$front" == "Bough" ]] && break
  done
  if [[ "$front" != "Bough" ]]; then echo "fail:frontmost got '${front:-unknown}'"; return; fi
  uit_ime_switch
  local dump cx cy
  dump=$(uit_axdump)
  read -r cx cy <<<"$(uit_node_coords "$dump" "$2")"
  if [[ -z "${cx:-}" || -z "${cy:-}" ]]; then echo "fail:node-not-found"; return; fi
  # Click-to-selection is racy on a cold launch: prove it with Space and retry.
  P_EDITING=""
  for attempt in 1 2 3; do
    uit_click "$cx" "$cy"
    sleep 0.6
    uit_key 49               # Space proves the click selected the node
    sleep 1.0
    P_EDITING=$(uit_canvas_editing)
    uit_key 53               # Esc, leave editing (Space/Esc never change the tree)
    sleep 0.5
    [[ "$P_EDITING" == "$2" ]] && break
    osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1 || true
    sleep 0.3
  done
  if [[ "$P_EDITING" != "$2" ]]; then echo "fail:selection got '$P_EDITING' want '$2'"; return; fi
  osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1 || true
  sleep 0.3
  # phase runs in a command-substitution subshell, so return the editing value
  # through stdout instead of relying on a variable surviving the subshell.
  echo "ok|$P_EDITING"
}

parentdiff(){ # <before-file> <after-file> -> prints text-keyed parent-edge diffs, rc 1 if any
  python3 - "$1" "$2" <<'PY'
import sys
sys.path.insert(0, '.')
import treecompare as t

def pmap(path):
    rows = list(t.walk(t.load(path)))  # walk is a generator: materialise once
    id2t = {t.canonical_id(i): tx for i, tx, _ in rows}
    return {id2t[t.canonical_id(i)]: (id2t.get(t.canonical_id(p), '?') if p else 'ROOT')
            for i, tx, p in rows}

pa, pb = pmap(sys.argv[1]), pmap(sys.argv[2])
diff = sorted(k for k in set(pa) | set(pb) if pa.get(k) != pb.get(k))
for k in diff:
    print(f'parent {k}: {pa.get(k)} -> {pb.get(k)}')
sys.exit(1 if diff else 0)
PY
}

uit_prepare_storage || exit 1

# ---------- Phase A: Space on a grandchild ----------
r=$(phase A "$TARGET") || true
if [[ "${r%%|*}" != ok ]]; then uit_report U9A 1 "setup $r"; exit 1; fi
A_editing=${r#ok|}
uit_quit_flush
A_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
A_text=$(python3 treecompare.py findtext "$TARGET" "$TABS/$SLOT_ID.mindmap" 2>/dev/null)

# ---------- Phase B1: Shift+Tab on a grandchild ----------
r=$(phase B1 "$TARGET")
if [[ "${r%|*}" != ok ]]; then uit_report U9B1 1 "setup $r"; exit 1; fi
uit_require_frontmost
B1_BEFORE=$(mktemp -d /tmp/u9b1.XXXXXX)
cp "$FIXTURE" "$B1_BEFORE/before.mindmap"
osascript -e 'tell application "System Events" to key code 48 using shift down' 2>/dev/null
sleep 1.0
uit_quit_flush
B1_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
B1_diff=$(parentdiff "$B1_BEFORE/before.mindmap" "$TABS/$SLOT_ID.mindmap" 2>&1); B1_diff_rc=$?
B1_lines=$(printf '%s' "$B1_diff" | grep -c '^parent ' || true)
rm -rf "$B1_BEFORE"

# ---------- Phase B2: Shift+Tab on a root-level child (must be a no-op) ----------
r=$(phase B2 "$B2_TARGET")
if [[ "${r%|*}" != ok ]]; then uit_report U9B2 1 "setup $r"; exit 1; fi
uit_require_frontmost
B2_BEFORE=$(mktemp -d /tmp/u9b2.XXXXXX)
cp "$FIXTURE" "$B2_BEFORE/before.mindmap"
osascript -e 'tell application "System Events" to key code 48 using shift down' 2>/dev/null
sleep 1.0
uit_quit_flush
B2_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
B2_diff=$(parentdiff "$B2_BEFORE/before.mindmap" "$TABS/$SLOT_ID.mindmap" 2>&1); B2_diff_rc=$?
rm -rf "$B2_BEFORE"

# ---------- Phase C: Tab (positive control) ----------
r=$(phase C "$TARGET")
if [[ "${r%|*}" != ok ]]; then uit_report U9C 1 "setup $r"; exit 1; fi
uit_require_frontmost
uit_key 48                 # Tab
sleep 1.0
uit_quit_flush
C_count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)

echo "U9 RESULT baseline=20"
echo "  A space:      editing='$A_editing' count=$A_count text-$TARGET-present=$A_text"
echo "  B1 shifttab:  parent-diffs=$B1_lines rc=$B1_diff_rc count=$B1_count"
echo "    $B1_diff"
echo "  B2 shifttab:  parent-diffs-rc=$B2_diff_rc count=$B2_count"
echo "  C tab(ctrl):  count=$C_count"

# The control must fire first; if Tab did not create a node the whole run is void.
if [[ "$C_count" != "21" ]]; then
  uit_report U9 1 "POSITIVE CONTROL FAILED: Tab produced count=$C_count (want 21). Phases B1/B2 are uninterpretable."
  exit 1
fi

if [[ "$A_editing" == "$TARGET" && "$A_count" == "20" && "$A_text" == "1" ]]; then
  echo "U9A PASS: Space entered editing on $TARGET, kept its text, created nothing"
else
  echo "U9A FAIL: want editing=$TARGET count=20 text=1"; rc=1
fi

if [[ "$B1_diff_rc" == "1" && "$B1_lines" == "1" && "$B1_diff" == "parent N-0005: N-0001 -> N-0000" && "$B1_count" == "20" ]]; then
  echo "U9B1 PASS: Shift+Tab outdented $TARGET (exactly one parent edge: N-0001 -> N-0000), tree size unchanged"
else
  echo "U9B1 FAIL: want exactly one parent edge N-0005: N-0001 -> N-0000, count=20; got rc=$B1_diff_rc lines=$B1_lines: $B1_diff"; rc=1
fi

if [[ "$B2_diff_rc" == "0" && "$B2_count" == "20" ]]; then
  echo "U9B2 PASS: Shift+Tab on a root-level child changed no parent edge at all"
else
  echo "U9B2 FAIL: root-level child outdent changed parent edges (rc=$B2_diff_rc): $B2_diff"; rc=1
fi

uit_cleanup_all 2>/dev/null || true
exit $rc
