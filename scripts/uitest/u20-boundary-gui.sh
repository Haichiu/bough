#!/usr/bin/env bash
# u20 — Boundary v1, the half the unit checks cannot reach.
#
# MindFlowChecks covers the model, pruning, undo/redo, Codable and SVG export
# with 26 named assertions. What it cannot answer is whether ⇧⌘B actually
# reaches the app and whether anything is drawn on the real canvas. This probe
# answers exactly those two, with two independent oracles:
#
#   visual   — pixel difference inside the window rect before and after ⇧⌘B
#   function — the persisted document contains one boundary after a flush
#
# A visual-only result would not distinguish "drew a frame" from "repainted for
# an unrelated reason"; a function-only result would not distinguish "stored a
# boundary" from "stored it and drew nothing". Both must agree.
#
# Controls, because a differ that always reports change proves nothing:
#   stability  — two captures with no action in between must differ by ~0
#   sensitivity— a known-visible action (fold) must produce a non-zero diff
#
# Reports INSTRUMENT: for probe faults and FAIL: for product faults. They are
# not the same finding and must not be reported as one.
set -uo pipefail
cd "$(dirname "$0")" && source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
instrument(){ echo "INSTRUMENT: $1"; FAIL=$((FAIL+1)); }

front(){ osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1; sleep 0.7; }
frontmost_is_mindflow(){
  [[ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)" == "Bough" ]]
}

# Full-screen capture cropped to the window. Frontmost is re-asserted and
# verified before every capture, because a capture taken while another app is
# stacked above silently measures that app (u19 once measured Ghostty's
# #282c34 exactly this way).
shot(){ # $1 = destination path
  front
  if ! frontmost_is_mindflow; then
    front
    frontmost_is_mindflow || return 1
  fi
  local full=/tmp/u20-full.png imgw scrw scale WX WY WW WH
  screencapture -x -o "$full" 2>/dev/null || return 1
  imgw=$(magick identify -format '%w' "$full" 2>/dev/null)
  scrw=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)' 2>/dev/null)
  [[ -z "$imgw" || -z "$scrw" ]] && return 1
  scale=$(python3 -c "print(max(1, round($imgw/$scrw)))")
  read -r WX WY WW WH <<<"$(uit_wingeom)"
  [[ -z "${WH:-}" ]] && return 1
  magick "$full" -crop \
    "$(python3 -c "print(max(8,int(($WW-24)*$scale)))")x$(python3 -c "print(max(8,int(($WH-140)*$scale)))")+$(python3 -c "print(int(($WX+12)*$scale))")+$(python3 -c "print(int(($WY+96)*$scale))")" \
    +repage "$1" 2>/dev/null
}

# Normalised RMSE (0..1), not AE. AE is reported in scientific notation for
# large differences, and an earlier version of this probe read "1.04807e+08" as
# the integer 1 and concluded nothing had been drawn. A fraction is also
# scale-free, so the thresholds below do not depend on the window size.
diffrmse(){ magick compare -metric RMSE "$1" "$2" null: 2>&1 | grep -oE '\([0-9.e+-]+\)' | tr -d '()' | head -1; }

# The idle capture measures this machine's noise floor. A real change has to
# clear it by an order of magnitude, so the threshold calibrates itself instead
# of being a constant someone tuned until the test passed.
exceeds(){ python3 -c "import sys; print('yes' if float('${1:-0}') > max(10*float('${2:-0}'), 0.005) else 'no')" 2>/dev/null; }

uit_prepare_storage >/dev/null 2>&1
uit_launch small-20 30 >/dev/null 2>&1 || { instrument "launch failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
front

# --- entrance: the menu row exists and carries XMind's shortcut --------------
MENU=$(osascript -e 'tell application "System Events" to tell process "Bough" to get name of every menu item of menu 1 of menu bar item "主題" of menu bar 1' 2>/dev/null)
if [[ "$MENU" == *"加入外框"* ]]; then ok "加入外框 is present in the 主題 menu"
else no "加入外框 is absent from the 主題 menu (got: ${MENU:0:160})"; fi

# --- select a branch node ----------------------------------------------------
D=$(uit_axdump)
read -r cx cy <<<"$(uit_node_coords "$D" N-0002)"
if [[ -z "${cx:-}" ]]; then
  instrument "N-0002 not locatable; cannot exercise the boundary"
  uit_cleanup_all >/dev/null 2>&1; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
uit_click "$cx" "$cy"; sleep 0.8

# --- stability control: no action must mean no pixels ------------------------
shot /tmp/u20-a.png  || { instrument "capture A failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
sleep 0.5
shot /tmp/u20-a2.png || { instrument "capture A2 failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
IDLE=$(diffrmse /tmp/u20-a.png /tmp/u20-a2.png)
echo "idle diff (normalised RMSE): ${IDLE:-?}"
# A caret blink or an incidental redraw moves a little; a large idle reading
# means the instrument cannot tell a boundary from noise and nothing below is
# safe to conclude.
if [[ -n "$IDLE" ]] && [[ "$(python3 -c "print('ok' if float('$IDLE') < 0.005 else 'bad')")" == ok ]]; then
  ok "the differ is stable when nothing happens (control)"
else instrument "idle diff ${IDLE:-?} is too large to distinguish a boundary from noise"; fi

# --- the measurement: ⇧⌘B must draw -----------------------------------------
front
osascript -e 'tell application "System Events" to keystroke "b" using {command down, shift down}' >/dev/null 2>&1
sleep 1.5
shot /tmp/u20-b.png || { instrument "capture B failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
DREW=$(diffrmse /tmp/u20-a2.png /tmp/u20-b.png)
echo "diff after ⇧⌘B: ${DREW:-?}"
if [[ "$(exceeds "$DREW" "$IDLE")" == yes ]]; then ok "⇧⌘B draws something on the canvas"
else no "⇧⌘B changed ${DREW:-?} — no frame appeared"; fi

# --- sensitivity control: the differ can see a known change ------------------
front
osascript -e 'tell application "System Events" to keystroke "/" using command down' >/dev/null 2>&1
sleep 1.5
shot /tmp/u20-c.png || { instrument "capture C failed"; uit_cleanup_all >/dev/null 2>&1; exit 1; }
SEEN=$(diffrmse /tmp/u20-b.png /tmp/u20-c.png)
echo "diff after a known fold: ${SEEN:-?}"
if [[ "$(exceeds "$SEEN" "$IDLE")" == yes ]]; then ok "the differ detects a known visible change (control)"
else instrument "a known fold moved ${SEEN:-?} — the differ is blind, so the ⇧⌘B verdict means nothing"; fi

# --- functional oracle: the boundary reached the document --------------------
uit_quit_flush >/dev/null 2>&1; sleep 2
# Documents are saved as .mindmap, not .json. The first version of this oracle
# globbed *.json, found nothing, and reported a product failure while the
# boundary was sitting correctly in the file. The storage root is created fresh
# per run, so no time filter is needed to avoid stale files.
DOC=$(find "${UIT_STORAGE_ROOT:-/tmp/mindflow-uitest-storage}/tabs" -name '*.mindmap' 2>/dev/null | head -1)
if [[ -z "$DOC" ]]; then
  no "no persisted document contains a boundaries field"
else
  N=$(python3 -c "
import json
b=json.load(open('$DOC')).get('boundaries') or []
print(len(b), (b[0].get('rootID','') if b else ''))
" 2>/dev/null)
  COUNT=${N%% *}; ROOTID=${N#* }
  echo "persisted boundaries: ${COUNT:-?} anchored on ${ROOTID:-none}"
  if [[ "${COUNT:-0}" -eq 1 ]]; then ok "exactly one boundary is persisted in the document"
  elif [[ "${COUNT:-0}" -eq 0 ]]; then no "the document stores boundaries: [] — ⇧⌘B never reached the model"
  else no "the document stores $COUNT boundaries — one keypress created more than one"; fi
fi

uit_cleanup_all >/dev/null 2>&1
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
