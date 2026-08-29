#!/usr/bin/env bash
# T-003 uitest shared helpers. Sourced by u*.sh / run.sh. Not executed directly.
#
# Method: AX locate (System Events entire-contents dump) + coordinate click
# (System Events `click at`) + CGEvent drag (JXA) + CGEvent key timing probe.
# No screencapture diffing. Touches only scripts/ and docs/ (plus the app's
# autosave tabs dir, which is backed up and restored).
set -uo pipefail

UIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$UIT_DIR/../.." && pwd)"
APP="${UITEST_APP:-$HOME/Desktop/MindFlow.app}"
SLOT_ID="0D3F1CE0-0000-4000-8000-0000000000F1"
APP_SUPPORT="$HOME/Library/Application Support/MindFlow"
TABS="$APP_SUPPORT/tabs"
UIT_BACKUP="$APP_SUPPORT/tabs.pre-uitest-backup"
ART_DIR="/tmp/uitest-artifacts"
mkdir -p "$ART_DIR"

uit_ensure_backup(){
  mkdir -p "$APP_SUPPORT"
  [[ -d "$UIT_BACKUP" ]] || cp -R "$TABS" "$UIT_BACKUP" 2>/dev/null || true
}

uit_pkill(){
  pkill -x MindFlow 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x MindFlow >/dev/null 2>&1 || return 0; sleep 0.1; done
}

uit_stage(){ # <fixture-basename>
  local f="$PROJ/scripts/fixtures/$1.mindmap"
  [[ -f "$f" ]] || { echo "missing fixture $f" >&2; return 1; }
  mkdir -p "$TABS"
  cp "$f" "$TABS/$SLOT_ID.mindmap"
  touch "$TABS/$SLOT_ID.mindmap"
}

uit_launch(){ # <fixture-basename> [waitsec] -> echoes pid
  local f="$1" waitsec="${2:-30}" t0 w
  uit_pkill
  uit_stage "$f" || return 1
  open "$APP"
  t0=$(date +%s)
  while :; do
    if pgrep -x MindFlow >/dev/null 2>&1; then
      w=$(osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to count of windows' 2>/dev/null || echo 0)
      [[ "${w:-0}" -ge 1 ]] && break
    fi
    sleep 0.3
    (( $(date +%s) - t0 >= waitsec )) && { echo "ERROR: app window timeout after ${waitsec}s" >&2; return 1; }
  done
  osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1 || true
  sleep 1
  pgrep -x MindFlow | head -1
}

uit_quit_flush(){ # graceful Cmd+Q -> willTerminate autosave rewrites the tabs slot
  osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to set frontmost to true' >/dev/null 2>&1
  sleep 0.3
  osascript -e 'tell application "System Events" to keystroke "q" using command down' >/dev/null 2>&1
  local alive=1
  for _ in $(seq 1 100); do pgrep -x MindFlow >/dev/null 2>&1 || { alive=0; break; }; sleep 0.1; done
  if [[ "$alive" == "1" ]]; then
    echo "WARN: Cmd+Q did not quit; sending SIGTERM (autosave may be stale)" >&2
    pkill -x MindFlow 2>/dev/null || true
    sleep 1
  fi
  sleep 0.5
}

uit_restore(){
  uit_pkill
  if [[ -d "$UIT_BACKUP" ]]; then rm -rf "$TABS"; cp -R "$UIT_BACKUP" "$TABS"; fi
}

uit_report(){ # <name> <0|1> <msg-on-fail>
  local name="$1" ok="$2" msg="$3"
  if [[ "$ok" == "0" ]]; then
    echo "PASS $name"
  else
    screencapture -x "$ART_DIR/$name.png" 2>/dev/null || true
    echo "FAIL $name: $msg (shot=$ART_DIR/$name.png)"
  fi
}

uit_wingeom(){ # echoes: x y w h
  local s
  s=$(osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to get {position, size} of window 1' 2>/dev/null || true)
  echo "$s" | tr -d ' ' | awk -F',' '{print $1, $2, $3, $4}'
}

uit_axdump(){ # TSV: role x y w h value (entire contents of window 1)
  osascript <<'AS'
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set tabCh to character id 9
    set els to entire contents of window 1
    set out to {}
    repeat with el in els
      set r to ""
      set p to {0, 0}
      set s to {0, 0}
      set v to ""
      try
        set r to role of el as text
      end try
      try
        set p to position of el
      end try
      try
        set s to size of el
      end try
      try
        set vv to value of el
        if class of vv is text then set v to vv
      end try
      set end of out to r & tabCh & ((item 1 of p) as text) & tabCh & ((item 2 of p) as text) & tabCh & ((item 1 of s) as text) & tabCh & ((item 2 of s) as text) & tabCh & v
    end repeat
  end tell
end tell
set AppleScript's text item delimiters to linefeed
return out as text
AS
}

uit_click(){ # x y — System Events synthesized click
  osascript -e "tell application \"System Events\" to tell (first process whose name is \"MindFlow\") to click at {$1, $2}" >/dev/null 2>&1
}

uit_key(){ # keycode (48=Tab, 53=Esc)
  osascript -e "tell application \"System Events\" to key code $1" 2>/dev/null
}

uit_type(){ # text
  osascript -e "tell application \"System Events\" to keystroke \"$1\"" 2>/dev/null
}

uit_node_coords(){ # <dump> <N-xxxx> -> echoes "cx cy" (element center, global screen pts)
  awk -F'\t' -v n="$2" '$1=="AXStaticText" && $6==n {print $2+$4/2, $3+$5/2; exit}' <<<"$1"
}
