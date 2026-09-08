#!/usr/bin/env bash
# U16 (p1): INDEPENDENT verification of T-053 (delete keys must never beep).
#
# T-053 ships its own checks, but those exercise the pure decision function
# KeyboardMonitor.deleteOutcome(for:). That function can be perfectly correct
# while the monitor still never reaches it -- which is precisely the reported
# bug: the Command/Option/Control gates returned the event before the delete
# case ran, so the keyDown fell through to AppKit and it beeped.
#
# So this probe refuses to touch deleteOutcome. It drives the real key path
# through the real app with real modifier flags and asks the only question the
# pure function cannot answer: did the monitor actually claim the key?
#
# The beep itself is not observable from a script. Its cause is: the keyDown was
# not consumed. When the canvas consumes a delete, the node disappears. So
# "node gone" is the observable proxy for "key was claimed", and "node still
# there" is what an unclaimed (beeping) key looks like.
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

# $1 label  $2 osascript key phrase
run_phase(){
  uit_prepare_storage >/dev/null 2>&1 || return 1
  uit_launch small-20 30 >/dev/null 2>&1 || { echo "$1 ABORT launch"; return 1; }
  sleep 1.0
  ensure_front || { uit_quit_flush >/dev/null 2>&1; return 1; }
  uit_ime_switch
  select_node N-0005 || { echo "$1 ABORT: node not found"; uit_quit_flush >/dev/null 2>&1; return 1; }
  ensure_front || { uit_quit_flush >/dev/null 2>&1; return 1; }
  [[ -n "$2" ]] && osascript -e "tell application \"System Events\" to $2" >/dev/null 2>&1
  sleep 1.0
  uit_quit_flush >/dev/null 2>&1; sleep 1.2
  cp "$(doc_path)" "/tmp/u16-$1.mindmap" 2>/dev/null
  uit_cleanup_all >/dev/null 2>&1 || true
}

assert_deleted(){ # $1 label, $2 human name
  local f=/tmp/u16-$1.mindmap c n
  [[ -f "$f" ]] || { bad "$2: no document captured (probe failed, not evidence)"; return; }
  c=$(python3 $T count "$f"); n=$(python3 $T findtext N-0005 "$f")
  echo "    $2: count=$c  N-0005 present=$n"
  if [[ "$n" == "0" && "$c" -lt 20 ]]; then ok "$2 is claimed by the canvas (node deleted)"
  else bad "$2 did NOT delete -- key fell through to AppKit, i.e. it beeps"; fi
}

echo "=== control: select only, press nothing ==="
run_phase control ""
C=/tmp/u16-control.mindmap
cc=$(python3 $T count $C 2>/dev/null); cn=$(python3 $T findtext N-0005 $C 2>/dev/null)
echo "    count=$cc  N-0005 present=$cn"
if [[ "$cc" == "20" && "$cn" == "1" ]]; then ok "control: selecting alone deletes nothing"
else bad "control is dirty (count=$cc present=$cn); later phases are uninterpretable"; fi

echo "=== the modifier matrix that used to fall through ==="
run_phase plain    "key code 51";                      assert_deleted plain    "plain Backspace"
run_phase cmd      "key code 51 using command down";   assert_deleted cmd      "Command+Backspace"
run_phase opt      "key code 51 using option down";    assert_deleted opt      "Option+Backspace"
run_phase ctrl     "key code 51 using control down";   assert_deleted ctrl     "Control+Backspace"
run_phase fwd      "key code 117";                     assert_deleted fwd      "Forward Delete"

echo
echo "U16 result: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
