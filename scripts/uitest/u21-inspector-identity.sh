#!/bin/bash
# u21 — the inspector says which topic you are editing.
#
# The header used to read 「主題」 for every node, which carries no information:
# when search, focus mode or a scrolled canvas leaves the selection off screen,
# the inspector could not tell you what you were about to edit. It now shows the
# topic's own text.
#
# Reading text out of pixels needs OCR we do not have, so the oracle is
# differential: the header strip must REPAINT when the selection moves, and must
# NOT repaint when nothing happens. A header hard-coded to a constant passes the
# second and fails the first, which is exactly the regression worth catching.
set -uo pipefail
cd "$(dirname "$0")"
source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
inst(){ echo "INSTRUMENT: $1"; FAIL=$((FAIL+1)); }

# Header strip in window points. The first version of this crop sat too far
# right and too low: it caught the tail of the label plus a divider whose
# position depends on which optional inspector sections the selected node shows.
# A constant header still "changed" by 0.07 because the divider moved, so the
# probe passed for the wrong reason. The strip must start where the text starts
# and must not reach any divider.
HDR_LEFT_FRAC=0.72; HDR_H=20; HDR_DY=110

shot_header(){ # $1 = output png. Echoes OK, or a sentinel this script must not
                # mistake for a product failure.
  osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1
  sleep 0.6
  local front
  front=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  [ "$front" = "MindFlow" ] || { echo NOTFRONT; return; }
  local wx wy ww wh
  read -r wx wy ww wh <<<"$(uit_wingeom)"
  [ -n "${wh:-}" ] || { echo NOWINDOW; return; }
  screencapture -x -o /tmp/u21-full.png 2>/dev/null || { echo CAPTUREFAIL; return; }
  local hx hw
  hx=$(awk -v w="$wx" -v ww="$ww" -v f="$HDR_LEFT_FRAC" 'BEGIN{printf "%d", (w+ww*f)*2}')
  hw=$(awk -v ww="$ww" -v f="$HDR_LEFT_FRAC" 'BEGIN{printf "%d", ww*(1-f)*2 - 24}')
  magick /tmp/u21-full.png -crop \
    ${hw}x$((HDR_H*2))+${hx}+$(( (wy+HDR_DY)*2 )) \
    +repage "$1" 2>/dev/null || { echo CAPTUREFAIL; return; }
  echo OK
}

rmse(){ # normalized 0..1 difference between two same-size crops
  magick compare -metric RMSE "$1" "$2" null: 2>&1 | grep -oE '\(([0-9.]+)\)' | tr -d '()' | head -1
}

ink(){ # standard deviation of the crop: a blank strip has none
  magick "$1" -format '%[fx:standard_deviation]' info: 2>/dev/null
}

# A blank header means nothing is selected, which is an instrument failure (the
# click missed) and not a product failure. Without this guard the probe happily
# compares "text" against "nothing" and reports the header as working.
require_ink(){
  local v; v=$(ink "$1"); v=${v:-0}
  awk -v v="$v" 'BEGIN{exit !(v > 0.01)}' && return 0
  inst "$2 is blank — the selection was lost, so this sample proves nothing"
  return 1
}

bad(){ case "$1" in OK) return 1;; *) inst "$2 ($1)"; return 0;; esac; }

trap 'uit_cleanup_all >/dev/null 2>&1' EXIT
uit_cleanup_all >/dev/null 2>&1; sleep 1
uit_prepare_storage >/dev/null 2>&1
uit_launch small-20 30 >/dev/null 2>&1 || { inst "app did not launch"; exit 1; }
osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1; sleep 1.5

# Open the inspector FIRST. It takes about a third of the window, so every node
# moves; coordinates read before it opens land on empty canvas and silently
# clear the selection.
osascript -e 'tell application "System Events" to keystroke "i" using {command down, option down}' >/dev/null 2>&1
sleep 2

D=$(uit_axdump)
read -r ax ay <<<"$(uit_node_coords "$D" N-0002)"
read -r bx by <<<"$(uit_node_coords "$D" N-0016)"
if [ -z "${ax:-}" ] || [ -z "${bx:-}" ]; then
  inst "fixture nodes N-0002 / N-0016 not found with the inspector open"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

uit_click "$ax" "$ay"; sleep 1.2

s=$(shot_header /tmp/u21-a.png);  bad "$s" "header sample A" || true
s2=$(shot_header /tmp/u21-a2.png); bad "$s2" "header sample A again" || true

if [ "$s" = OK ] && [ "$s2" = OK ] && require_ink /tmp/u21-a.png "header sample A"; then
  NOISE=$(rmse /tmp/u21-a.png /tmp/u21-a2.png)
  NOISE=${NOISE:-0}
  awk -v n="$NOISE" 'BEGIN{exit !(n < 0.01)}' \
    && ok "the header is stable when nothing changes (noise floor ${NOISE})" \
    || no "the header repaints on its own — the differential oracle is unusable (${NOISE})"

  uit_click "$bx" "$by"; sleep 1.5
  s3=$(shot_header /tmp/u21-b.png)
  if ! bad "$s3" "header sample B" && require_ink /tmp/u21-b.png "header sample B"; then
    MOVED=$(rmse /tmp/u21-a.png /tmp/u21-b.png)
    MOVED=${MOVED:-0}
    THRESH=$(awk -v n="$NOISE" 'BEGIN{t=n*10; if(t<0.02) t=0.02; print t}')
    awk -v m="$MOVED" -v t="$THRESH" 'BEGIN{exit !(m > t)}' \
      && ok "the header names the selected topic — it repaints when the selection moves (${MOVED} > ${THRESH})" \
      || no "the header did not change when the selection moved (${MOVED} <= ${THRESH}) — it is back to a constant label"
  fi
fi

uit_quit_flush >/dev/null 2>&1
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
