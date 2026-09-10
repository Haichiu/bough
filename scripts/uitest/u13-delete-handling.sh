#!/usr/bin/env bash
# U13 (Walker/p6): runtime oracle for the "delete beeps" report.
#
# Pathology: AppKit plays the system alert sound for a keyDown that reaches the
# end of the responder chain unhandled. The symptom is the beep; the cause is an
# unconsumed Delete/Backspace. The app carries an env-gated instrument
# (MINDFLOW_KEY_PROBE, see KeyboardMonitor.probeAppend) that logs, per keyDown,
# whether the monitor consumed it ("handled") or handed it to AppKit ("passed"),
# plus the state at decision time (editing/selection/link/nodes/editor).
#
# A keyDown is acceptable only when the monitor handled it, or when an editable
# text view owns the first responder (editor=1 — AppKit routes the key to the
# field editor, which handles it; that is the correct pass-through).
#
# Positive control: ⌘J is not bound by the app, so the monitor must hand it to
# AppKit. The instrument MUST show passed/editor=0 for it, otherwise a
# "nothing beeped" result would be uninterpretable.
#
# State control uses the monitor's own arrow navigation (Right = select child,
# Down = next sibling) instead of AX clicks: a second click on a selected node
# starts editing (handleNodeClick), and AX dumps drop elements under load.
# Delete removes a node *and its subtree*, so every destructive phase targets a
# leaf and undoes afterwards to keep the later phases interpretable.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PROBE="/tmp/mindflow-keyprobe-$$.tsv"
rm -f "$PROBE"; : > "$PROBE"
UIT_APP_ENV=("MINDFLOW_KEY_PROBE=$PROBE")

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
CLICLICK="/opt/homebrew/bin/cliclick"

activate(){ # focus failures are instrument failures, never product findings
  osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1; sleep 0.3
  local front
  front=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  if [[ "$front" != "Bough" ]]; then
    echo "ABORT: instrument failure — frontmost='${front:-unknown}', keys would land elsewhere" >&2
    uit_quit_flush >/dev/null 2>&1
    exit 70
  fi
}
esc_key(){ uit_key 53; sleep 0.3; }
sel_root(){ esc_key; uit_key 124; sleep 0.4; }        # Right with no selection -> root
sel_child(){ sel_root; uit_key 124; sleep 0.4; }      # Right -> N-0001
sel_leaf(){ sel_child; uit_key 124; sleep 0.4; }      # Right -> N-0005 (leaf)
down_key(){ uit_key 125; sleep 0.3; }
undo_key(){ activate; osascript -e 'tell application "System Events" to key code 6 using command down' >/dev/null 2>&1; sleep 0.7; }
sel_n0005(){ esc_key; uit_key 124; sleep 0.3; uit_key 124; sleep 0.3; uit_key 124; sleep 0.4; }
send_phrase(){ # label osascript-action — for modifier combos uit_key cannot send
  local label="$1" action="$2" before after
  before=$(wc -l < "$PROBE" | tr -d ' ')
  activate
  osascript -e "tell application \"System Events\" to $action" >/dev/null 2>&1
  sleep 0.5
  after=$(wc -l < "$PROBE" | tr -d ' ')
  echo "  [$label] probe lines +$((after-before))"
  tail -n $((after-before)) "$PROBE" | sed 's/^/      /'
  LAST=$(tail -1 "$PROBE")
}
send(){ # label keycode...
  local label="$1"; shift
  local before after k
  before=$(wc -l < "$PROBE" | tr -d ' ')
  activate
  for k in "$@"; do uit_key "$k"; done
  sleep 0.5
  after=$(wc -l < "$PROBE" | tr -d ' ')
  echo "  [$label] probe lines +$((after-before))"
  tail -n $((after-before)) "$PROBE" | sed 's/^/      /'
  LAST=$(tail -1 "$PROBE")
}
field(){ awk -F'\t' -v k="$1" '{for(i=5;i<=NF;i++) if($i==k) print "1"}' <<<"$LAST"; }
value_of(){ awk -F'\t' -v k="$1" '{for(i=5;i<=NF;i++) if($i ~ "^"k"=") {sub("^"k"=","",$i); print $i}}' <<<"$LAST"; }
verdict(){ awk -F'\t' '{print $4}' <<<"$LAST"; }

assert_handled(){ # label
  if [[ "$(verdict)" == "handled" ]]; then ok "$1: monitor handled the key (no beep)"
  elif [[ "$(verdict)" == "passed" && "$(field editor=1)" == "1" ]]; then ok "$1: field editor owns the key (no beep)"
  else bad "$1: keyDown unclaimed by app (beep) — line: $LAST"; fi
}

uit_prepare_storage >/dev/null || exit 1
uit_launch small-20 30 >/dev/null || { echo "ABORT launch"; exit 1; }
APP_PID=$(pgrep -x Bough | head -1)
ps eww -o command= -p "$APP_PID" | tr ' ' '\n' | grep -q "MINDFLOW_KEY_PROBE=$PROBE" \
  || { echo "ABORT: instrument not armed on pid $APP_PID"; uit_quit_flush >/dev/null; exit 1; }
echo "app pid=$APP_PID probe=$PROBE"
sleep 1.2; uit_ime_switch

echo "=== 0. positive control: ⌘J is unbound and must reach AppKit ==="
activate
osascript -e 'tell application "System Events" to key code 38 using command down' >/dev/null 2>&1
sleep 0.6
LAST=$(tail -1 "$PROBE")
echo "      $LAST"
if [[ "$(verdict)" == "passed" && -z "$(field editor=1)" ]]; then
  ok "instrument sees an unclaimed keyDown (control has teeth)"
else
  bad "control did not reproduce a pass-through: $LAST"
fi
BASE_NODES=$(value_of nodes)

echo "=== 1. plain selection (⌫) ==="
sel_leaf
send "Delete" 51
[[ "$(field selection=1)" == "1" && -z "$(field editor=1)" ]] && ok "state reached: leaf selected, not editing" \
  || bad "selection state not reached: $LAST"
assert_handled "selection ⌫"
undo_key
esc_key   # a keyDown after the undo: its snapshot carries the restored count
LAST=$(tail -1 "$PROBE")
[[ "$(value_of nodes)" == "$BASE_NODES" ]] && ok "undo restored the fixture ($BASE_NODES nodes)" \
  || bad "undo did not restore node count: $(value_of nodes) != $BASE_NODES"

echo "=== 2. root selected (⌫) ==="
# The root is auto-selected at launch (ContentView:254) and is deliberately
# undeletable. A claimed-but-refused delete here is correct and silent — p1's
# u16 cmd phase hit exactly this state after a coordinate click missed its node.
sel_root
send "Delete" 51
assert_handled "root ⌫"
root_before=$(value_of nodes)
esc_key; LAST=$(tail -1 "$PROBE")
[[ "$(value_of nodes)" == "$root_before" ]] && ok "root ⌫ leaves the document untouched" \
  || bad "root ⌫ mutated the document: $(value_of nodes) != $root_before"

echo "=== 3. no selection (⌫) ==="
esc_key
send "Delete" 51
assert_handled "no selection ⌫"

echo "=== 4. connection selected (⌫) ==="
sel_child
r=$(uit_context_menu N-0009 "從選取主題建立關聯線"); sleep 1.0
if [[ "$r" != "pressed" ]]; then bad "could not create a link (ctx='$r') — link phase uninterpretable"
else
  # The AX dump can drop elements on a busy window; retry until both endpoints show.
  d=""; for _ in 1 2 3 4; do
    d=$(uit_axdump)
    [[ -n "$(uit_node_coords "$d" N-0001)" && -n "$(uit_node_coords "$d" N-0009)" ]] && break
    sleep 0.6
  done
  read -r x0 y0 <<<"$(uit_node_coords "$d" N-0001)"
  read -r x1 y1 <<<"$(uit_node_coords "$d" N-0009)"
  if [[ -z "${x0:-}" || -z "${x1:-}" ]]; then
    bad "link endpoints not in AX dump ($x0,$y0 -> $x1,$y1) — link phase uninterpretable"
  else
    # linkCanvas: dot sits at curveMid = straight midpoint + 0.09*length along the
    # perpendicular, because the quadratic control point bulges by 0.18*length.
    read -r lx ly <<<"$(awk -v x0="$x0" -v y0="$y0" -v x1="$x1" -v y1="$y1" 'BEGIN{
      dx=x1-x0; dy=y1-y0; len=sqrt(dx*dx+dy*dy); if (len<1) len=1;
      print int((x0+x1)/2 - 0.09*dy), int((y0+y1)/2 + 0.09*dx) }')"
    echo "      link dot at ($lx,$ly) (endpoints $x0,$y0 -> $x1,$y1)"
    uit_click "$lx" "$ly"; sleep 0.8
    send "Delete" 51
    [[ "$(field link=1)" == "1" ]] && ok "state reached: link selected" \
      || bad "link not selected before Delete — link phase uninterpretable: $LAST"
    assert_handled "connection ⌫"
    undo_key
  fi
fi

echo "=== 5. editing handoff (Space then ⌫ as fast as the harness can) ==="
sel_leaf
send "Space+Delete" 49 51
[[ "$(field editing=1)" == "1" ]] && ok "state reached: Delete landed while editing" \
  || bad "Delete did not land in editing state: $LAST"
assert_handled "editing handoff ⌫"
esc_key

echo "=== 6. editing steady state (editor owns the keyboard) ==="
sel_leaf
send "Space" 49
sleep 1.5
send "Delete" 51
[[ "$(field editing=1)" == "1" ]] && ok "state reached: still editing after 1.5s" \
  || bad "steady editing state not reached: $LAST"
assert_handled "editing steady ⌫"
esc_key

echo "=== 7. after deleting the last child (selection becomes empty) ==="
sel_root            # N-0000
uit_key 124; sleep 0.4   # Right -> N-0001
down_key; down_key; down_key   # N-0002, N-0003, N-0004
uit_key 124; sleep 0.4   # Right -> N-0017 (first child of N-0004)
down_key; down_key       # N-0018, N-0019 (last child of N-0004, leaf)
send "Delete" 51
last_child_before=$(value_of nodes)
assert_handled "last child ⌫"
uit_key 53; sleep 0.4; LAST=$(tail -1 "$PROBE")
[[ "$(value_of nodes)" == $((last_child_before-1)) ]] && ok "deleted exactly one leaf (the last child)" \
  || bad "last-child phase hit a subtree: $(value_of nodes) != $((last_child_before-1))"
send "Delete" 51; assert_handled "empty selection ⌫"
undo_key

echo "=== 8. cursor off the canvas (⌫) ==="
sel_leaf
"$CLICLICK" -e 20 "m:10,6" >/dev/null 2>&1; sleep 0.3
send "Delete" 51; assert_handled "cursor off canvas ⌫"
undo_key

echo "=== 9. forward-delete key ⌦ ==="
sel_leaf
send "ForwardDelete" 117; assert_handled "forward delete ⌦"
undo_key

echo "=== 10. behaviour guards: each delete key removes exactly one leaf ==="
sel_leaf
send "Delete" 51
before_nodes=$(value_of nodes)
uit_key 53; sleep 0.4; LAST=$(tail -1 "$PROBE")
after_nodes=$(value_of nodes)
echo "  ⌫: before=$before_nodes after=$after_nodes"
[[ -n "$before_nodes" && "$after_nodes" == $((before_nodes-1)) ]] && ok "⌫ removes exactly one leaf" \
  || bad "⌫ node count $before_nodes -> $after_nodes (expected -1)"
undo_key
sel_leaf
send "ForwardDelete" 117
before_nodes=$(value_of nodes)
uit_key 53; sleep 0.4; LAST=$(tail -1 "$PROBE")
after_nodes=$(value_of nodes)
echo "  ⌦: before=$before_nodes after=$after_nodes"
[[ -n "$before_nodes" && "$after_nodes" == $((before_nodes-1)) ]] && ok "⌦ removes exactly one leaf" \
  || bad "⌦ node count $before_nodes -> $after_nodes (expected -1)"

echo "=== 11. modifier matrix: every delete modifier is claimed (p1/u16 overlap) ==="
# u16 (p1) measured ⌘⌫ as a no-op. Root cause was its coordinate click missing
# the node, leaving the launch-selected root: the monitor claims the key and
# delete() correctly refuses the root, so nothing moves. Arrow selection is
# deterministic, and the instrument records the disposition directly.
for spec in "plain ⌫|key code 51" "⌘⌫|key code 51 using command down" "⌥⌫|key code 51 using option down" "⌃⌫|key code 51 using control down"; do
  label=${spec%%|*}; action=${spec#*|}
  sel_n0005
  send_phrase "$label" "$action"
  assert_handled "$label"
  mod_before=$(value_of nodes)
  esc_key; LAST=$(tail -1 "$PROBE")
  [[ -n "$mod_before" && "$(value_of nodes)" == $((mod_before-1)) ]] \
    && ok "$label deletes exactly one leaf" \
    || bad "$label node count $mod_before -> $(value_of nodes) (expected -1)"
  undo_key
done

echo
echo "U13 RESULT: PASS=$PASS FAIL=$FAIL"
uit_quit_flush >/dev/null
[[ "$FAIL" -eq 0 ]]
