#!/usr/bin/env bash
# U12 (p1): INDEPENDENT verification of T-052 (Shift+Tab = outdent).
#
# Deliberately does not reuse u9, which the implementing worker rewrote as part
# of the same commit. An oracle that ships with the thing it measures is not a
# control. This asserts the tree directly through treecompare.
#
# Fixture geometry (small-20): N-0005's parent is N-0001, whose parent is the
# root N-0000. So promoting N-0005 must reparent it to N-0000, and promoting
# N-0001 (already a root child) must do nothing at all.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

doc_path(){ ls "$UIT_STORAGE_ROOT"/tabs/*.mindmap 2>/dev/null | head -1; }

tab_key(){ uit_key 48; }
shift_tab(){ osascript -e 'tell application "System Events" to key code 48 using shift down' >/dev/null 2>&1; }

select_node(){ # $1 = node text
  local d cx cy
  d=$(uit_axdump); read -r cx cy <<<"$(uit_node_coords "$d" "$1")"
  [[ -z "${cx:-}" ]] && return 1
  uit_click "$cx" "$cy"; sleep 0.8; return 0
}

phase(){ # $1 label, $2 target, $3 action(fn), returns doc after quit
  uit_prepare_storage >/dev/null || return 1
  uit_launch small-20 30 >/dev/null || { echo "$1 ABORT launch"; return 1; }
  sleep 1.0; uit_ime_switch
  select_node "$2" || { echo "$1 ABORT: $2 not found"; uit_quit_flush >/dev/null; return 1; }
  "$3"
  sleep 1.0
  uit_quit_flush >/dev/null; sleep 1.2
  cp "$(doc_path)" "/tmp/u12-$1.mindmap" 2>/dev/null
  uit_cleanup_all >/dev/null 2>&1 || true
}

echo "=== phase 1: baseline, no keystroke ==="
phase base N-0005 true
B=/tmp/u12-base.mindmap
echo "  count=$(python3 treecompare.py count $B)  parentof(N-0005)=$(python3 treecompare.py parentof N-0005 $B)  parentof(N-0001)=$(python3 treecompare.py parentof N-0001 $B)"

echo "=== phase 2: Shift+Tab on grandchild N-0005 ==="
phase grand N-0005 shift_tab
G=/tmp/u12-grand.mindmap
gp=$(python3 treecompare.py parentof N-0005 $G); gc=$(python3 treecompare.py count $G)
echo "  count=$gc  parentof(N-0005)=$gp"
[[ "$gp" == "N-0000" ]] && ok "N-0005 reparented to former grandparent N-0000" || bad "N-0005 parent is '$gp', expected N-0000"
[[ "$gc" == "$(python3 treecompare.py count $B)" ]] && ok "node count unchanged ($gc)" || bad "node count changed: $gc"

echo "=== phase 3: Shift+Tab on root child N-0001 must be a no-op ==="
phase rootchild N-0001 shift_tab
R=/tmp/u12-rootchild.mindmap
if python3 treecompare.py parents "$B" "$R" >/dev/null 2>&1; then ok "tree unchanged for root child"; else bad "tree CHANGED for root child: $(python3 treecompare.py parents $B $R 2>&1 | head -3)"; fi

echo "=== phase 4: positive control, plain Tab must add a child ==="
phase tab N-0005 tab_key
T=/tmp/u12-tab.mindmap
tc=$(python3 treecompare.py count $T)
[[ "$tc" -gt "$(python3 treecompare.py count $B)" ]] && ok "control fired: count $tc > baseline" || bad "CONTROL DEAD: count $tc, probe cannot observe tree change"

echo
echo "U12 result: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
