#!/usr/bin/env bash
# U17 (p1): undo must restore the document EXACTLY.
#
# Nothing guards this today. Undo is the thing a user leans on hardest and
# thinks about least: it is the reason they feel safe experimenting. A partial
# undo -- one that leaves a stray node, or re-parents a child on the way back --
# is worse than no undo, because the corruption is silent and the user has
# already moved on.
#
# Deliberately keystroke-only. An earlier attempt drove typing through
# uit_type and its results were not reproducible (focus drifted mid-phrase and
# keystrokes landed elsewhere), so it was discarded rather than believed. One
# key per phase is what this harness can actually do reliably.
#
# Structural comparison via treecompare `identical`, not byte compare: the
# question is whether the tree came back, not whether the file serialised
# identically.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

T=treecompare.py
doc_path(){ ls "$UIT_STORAGE_ROOT"/tabs/*.mindmap 2>/dev/null | head -1; }

ensure_front(){
  osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1; sleep 0.5
  local f; f=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  [[ "$f" == "MindFlow" ]] || { echo "  INSTRUMENT: frontmost='$f'"; return 1; }
}

select_node(){
  local d cx cy
  d=$(uit_axdump); read -r cx cy <<<"$(uit_node_coords "$d" "$1")"
  [[ -z "${cx:-}" ]] && return 1
  uit_click "$cx" "$cy"; sleep 0.8
}

key(){ ensure_front || return 1; osascript -e "tell application \"System Events\" to $1" >/dev/null 2>&1; sleep 0.8; }
undo(){ key 'keystroke "z" using command down'; }
redo(){ key 'keystroke "z" using {command down, shift down}'; }

run_phase(){ # $1 label, $2... key phrases
  local label=$1; shift
  uit_prepare_storage >/dev/null 2>&1 || return 1
  uit_launch small-20 30 >/dev/null 2>&1 || { echo "$label ABORT launch"; return 1; }
  sleep 1.0
  ensure_front || { uit_quit_flush >/dev/null 2>&1; return 1; }
  uit_ime_switch
  select_node N-0005 || { echo "$label ABORT: node not found"; uit_quit_flush >/dev/null 2>&1; return 1; }
  for k in "$@"; do
    case "$k" in
      UNDO) undo ;;
      REDO) redo ;;
      *)    key "$k" ;;
    esac
  done
  sleep 0.8
  uit_quit_flush >/dev/null 2>&1; sleep 1.2
  cp "$(doc_path)" "/tmp/u17-$label.mindmap" 2>/dev/null
  uit_cleanup_all >/dev/null 2>&1 || true
}

cnt(){ python3 $T count "/tmp/u17-$1.mindmap" 2>/dev/null; }
# treecompare's `identical` prints NOTHING and exits 0 on a match; it prints a
# diff and exits 1 otherwise. Comparing its stdout against the string
# "IDENTICAL" therefore fails always -- an earlier draft of this probe did
# exactly that and reported four phantom regressions.
same(){ python3 $T identical "/tmp/u17-$1.mindmap" "/tmp/u17-$2.mindmap" >/dev/null 2>&1; }

echo "=== phase 1: baseline ==="
run_phase base
echo "  baseline count=$(cnt base)"
[[ "$(cnt base)" == "20" ]] || bad "baseline is not 20 nodes; everything below is uninterpretable"

echo "=== phase 2: Tab creates a child (positive control) ==="
run_phase tab "key code 48"
echo "  count=$(cnt tab)"
if [[ "$(cnt tab)" == "21" ]]; then ok "control burns: Tab really adds a node"
else bad "control dead: Tab did not add a node (count=$(cnt tab)); undo results below mean nothing"; fi

echo "=== phase 3: Tab then undo ==="
run_phase tabundo "key code 48" UNDO
echo "  count=$(cnt tabundo)"
if same base tabundo; then ok "undo after create restores the tree exactly"
else bad "undo after create did NOT restore exactly"; python3 $T identical /tmp/u17-base.mindmap /tmp/u17-tabundo.mindmap | head -2; fi

echo "=== phase 4: Delete a parent then undo ==="
run_phase delundo "key code 51" UNDO
echo "  count=$(cnt delundo)"
if same base delundo; then ok "undo after delete restores the subtree exactly"
else bad "undo after delete did NOT restore exactly"; python3 $T identical /tmp/u17-base.mindmap /tmp/u17-delundo.mindmap | head -2; fi

echo "=== phase 5: Tab, undo, redo returns to the created state ==="
# NOT compared against phase 2 by identity: each launch mints a fresh random
# UUID for the created node, so a cross-launch id comparison would fail even
# when redo is perfect. Only the deterministic fixture ids survive across
# launches. The redo assertion is therefore structural.
run_phase tabredo "key code 48" UNDO REDO
echo "  count=$(cnt tabredo)  parentof=$(python3 $T parentof 子主題 /tmp/u17-tabredo.mindmap 2>/dev/null)"
if [[ "$(cnt tabredo)" == "21" && "$(python3 $T parentof 子主題 /tmp/u17-tabredo.mindmap 2>/dev/null)" == "N-0005" ]]; then
  ok "redo puts the child back under the same parent"
else bad "redo did not restore the created child"; fi

echo "=== phase 6: undo past the beginning must not corrupt ==="
run_phase undofloor UNDO UNDO UNDO UNDO UNDO
echo "  count=$(cnt undofloor)"
if same base undofloor; then ok "undoing past the first edit is a safe no-op"
else bad "undoing past the beginning changed the document"; python3 $T identical /tmp/u17-base.mindmap /tmp/u17-undofloor.mindmap | head -2; fi

echo
echo "U17 result: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
