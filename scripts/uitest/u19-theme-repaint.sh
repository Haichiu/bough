#!/usr/bin/env bash
# u19 — T-055: does switching the theme actually repaint, and does the choice survive a relaunch?
#
# WHY THIS EXISTS: the theme system shipped with model-layer assertions only.
# Those prove the palette resolves to the intended values; they cannot see paint.
# The canvas reads colours from the static Palette.screen, so the open question
# is whether a @Published change reaches it at all.
#
# WHY IT IS NOT RUN YET: written while CGSSessionScreenIsLocked = Yes. Under a
# locked screen no window is created at all -- verified with a control build of
# unmodified code, which also produced zero windows. Run this once unlocked.
#
# ORACLE: the modal (most frequent) colour inside the window rectangle is the
# canvas background. Sampling a fixed point could land on a node; the modal
# colour is immune to where nodes happen to sit.
#   classic light canvas = #f2efe7   minimal light canvas = #ffffff
set -u
cd "$(dirname "$0")"
source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
instrument(){ echo "INSTRUMENT: $1"; FAIL=$((FAIL+1)); }

front(){ osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1; sleep 0.7; }

if ioreg -n Root -d1 -r 2>/dev/null | grep -q 'CGSSessionScreenIsLocked"=Yes'; then
  instrument "screen is locked; no window can be created. Unlock and re-run."
  exit 1
fi

# Start from a known theme rather than whatever was last chosen.
defaults delete com.agenthub.mindflow themeID >/dev/null 2>&1 || true

canvas_hex(){
  # Modal colour inside the window rect, as #rrggbb.
  local shot=/tmp/u19-shot.png
  screencapture -x -o "$shot" 2>/dev/null || { echo "CAPTUREFAIL"; return; }
  local imgw scrw scale px py pw ph
  imgw=$(magick identify -format '%w' "$shot" 2>/dev/null)
  scrw=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)' 2>/dev/null)
  [[ -z "$imgw" || -z "$scrw" ]] && { echo "CAPTUREFAIL"; return; }
  scale=$(python3 -c "print(max(1, round($imgw/$scrw)))")
  read -r WX WY WW WH <<<"$(uit_wingeom)"
  [[ -z "${WH:-}" ]] && { echo "NOWINDOW"; return; }
  # Inset past the title bar and the tab strip so the sample is canvas, not chrome.
  px=$(python3 -c "print(int(($WX+12)*$scale))")
  py=$(python3 -c "print(int(($WY+96)*$scale))")
  pw=$(python3 -c "print(max(8,int(($WW-24)*$scale)))")
  ph=$(python3 -c "print(max(8,int(($WH-140)*$scale)))")
  magick "$shot" -crop ${pw}x${ph}+${px}+${py} +repage -depth 8 -format %c histogram:info: 2>/dev/null \
    | sort -rn | head -1 | grep -o '#[0-9A-Fa-f]\{6\}' | head -1 | tr 'A-F' 'a-f'
}

pick_theme(){ # $1 = menu item title
  front
  osascript -e "tell application \"System Events\" to tell process \"MindFlow\" to click menu item \"$1\" of menu 1 of menu item \"主題\" of menu 1 of menu bar item \"顯示\" of menu bar 1" >/dev/null 2>&1
  sleep 1.5
}

uit_prepare_storage >/dev/null 2>&1
uit_launch small-20 30 >/dev/null 2>&1 || { instrument "launch failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
front

# Positive control: the sampler must read the known classic canvas before any
# switch. If this fails the instrument is wrong and nothing below means anything.
BASE=$(canvas_hex)
echo "classic canvas sample: $BASE"
if [[ "$BASE" == "#f2efe7" ]]; then ok "sampler reads the classic canvas (positive control)"
else instrument "expected #f2efe7, read '$BASE' -- sampler or region is wrong"; fi

pick_theme "極簡"
MIN=$(canvas_hex)
echo "minimal canvas sample: $MIN"
if [[ "$MIN" == "#ffffff" ]]; then ok "switching to 極簡 repaints the canvas"
elif [[ "$MIN" == "$BASE" ]]; then no "canvas did not repaint on theme switch (still $MIN)"
else no "canvas changed to an unexpected colour: $MIN"; fi

# Persistence across a relaunch.
uit_quit_flush >/dev/null 2>&1; sleep 2
uit_launch small-20 30 >/dev/null 2>&1 || { instrument "relaunch failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
front
AGAIN=$(canvas_hex)
echo "canvas after relaunch: $AGAIN"
if [[ "$AGAIN" == "#ffffff" ]]; then ok "the chosen theme survives a relaunch"
else no "theme did not persist (read $AGAIN)"; fi

# T-055 item 3: ⌘/ must do exactly one thing now. Before the fix it folded the
# branch AND opened the help sheet in the same keypress.
D=$(uit_axdump)
read -r cx cy <<<"$(uit_node_coords "$D" N-0001)"
if [[ -n "${cx:-}" ]]; then
  uit_click "$cx" "$cy"; sleep 0.8
  before=$(uit_axdump | grep -cE "N-00[0-9][0-9]")
  front; osascript -e 'tell application "System Events" to keystroke "/" using command down' >/dev/null 2>&1
  sleep 1.5
  after=$(uit_axdump | grep -cE "N-00[0-9][0-9]")
  helped=$(uit_axdump | grep -c "鍵盤快速鍵")
  echo "nodes $before -> $after, help sheet open: $helped"
  if [[ "$after" -lt "$before" && "$helped" -eq 0 ]]; then ok "⌘/ folds the branch and does not open help"
  elif [[ "$helped" -gt 0 ]]; then no "⌘/ still opens the help sheet as well"
  else no "⌘/ did not fold the branch"; fi
else
  instrument "N-0001 not locatable; skipped the ⌘/ assertion"
fi

defaults delete com.agenthub.mindflow themeID >/dev/null 2>&1 || true
uit_quit_flush >/dev/null 2>&1
uit_cleanup_all >/dev/null 2>&1
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
