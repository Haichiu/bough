#!/usr/bin/env bash
# U18 (p1): the inspector's only remaining entrance must actually work.
#
# The window toolbar was removed in T-043. Before that change the inspector
# toggle had exactly one entrance in the whole product -- the toolbar button --
# so the removal added a menu item and ⌥⌘I in its place. A source-level check
# can only prove the shortcut was *typed into the file*. If the binding does not
# actually fire, the inspector becomes permanently unreachable and the source
# check would still be green. That is precisely the failure this probe exists
# to catch.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

ensure_front(){
  osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1; sleep 0.6
  local f; f=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  [[ "$f" == "Bough" ]] || { echo "  INSTRUMENT: frontmost='$f'"; return 1; }
}

uit_prepare_storage >/dev/null 2>&1
uit_launch small-20 30 >/dev/null 2>&1 || { echo "ABORT: launch failed"; exit 1; }
ensure_front || { echo "ABORT: cannot focus"; uit_quit_flush >/dev/null 2>&1; exit 1; }
sleep 1.0

# Inspector markers: the segmented picker inside the inspector panel.
inspector_present(){ uit_axdump | grep -qE "備註|大綱"; }

before=closed; inspector_present && before=open
echo "  inspector before: $before"

ensure_front && osascript -e 'tell application "System Events" to keystroke "i" using {command down, option down}' >/dev/null 2>&1
sleep 1.2
after=closed; inspector_present && after=open
echo "  inspector after ⌥⌘I: $after"

if [[ "$before" != "$after" ]]; then ok "⌥⌘I actually toggles the inspector at runtime"
else bad "⌥⌘I did NOT change the inspector state -- its only entrance is dead"; fi

# Toggling back proves it is a real toggle rather than a one-way open.
ensure_front && osascript -e 'tell application "System Events" to keystroke "i" using {command down, option down}' >/dev/null 2>&1
sleep 1.2
back=closed; inspector_present && back=open
echo "  inspector after second ⌥⌘I: $back"
if [[ "$back" == "$before" ]]; then ok "the shortcut toggles both ways"
else bad "the shortcut does not return to the original state"; fi

# ⌘0 fit-to-window: assert it does not crash the app and the window survives.
# Fit changes only the canvas transform, which this harness cannot read, so the
# claim here is deliberately narrow: the command is bound and non-fatal.
ensure_front && osascript -e 'tell application "System Events" to keystroke "0" using command down' >/dev/null 2>&1
sleep 1.0
if uit_axdump | grep -q AXWindow; then ok "⌘0 fit-to-window leaves the app alive and responsive"
else bad "the window disappeared after ⌘0"; fi

uit_quit_flush >/dev/null 2>&1
uit_cleanup_all >/dev/null 2>&1
echo
echo "U18 result: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
