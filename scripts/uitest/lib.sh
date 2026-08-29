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

uit_require_frontmost(){
  local front
  front=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  if [[ "$front" == "MindFlow" ]]; then return 0; fi
  echo "ERROR: global input blocked: frontmost='${front:-unknown}', expected MindFlow" >&2
  exit 70
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
      # Wait for the CANVAS window specifically (ghost untitled windows appear first).
      w=$(osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to count (windows whose name contains " – ")' 2>/dev/null || echo 0)
      [[ "${w:-0}" -ge 1 ]] && break
    fi
    sleep 0.3
    (( $(date +%s) - t0 >= waitsec )) && { echo "ERROR: app window timeout after ${waitsec}s" >&2; return 1; }
  done
  osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1 || true
  sleep 1
  # Close ghost untitled windows (multi-window state can appear from stray tabs).
  osascript <<'AS' >/dev/null 2>&1 || true
tell application "System Events"
  tell (first process whose name is "MindFlow")
    repeat with i from (count of windows) to 1 by -1
      set w to window i
      try
        set t to name of w
      on error
        set t to ""
      end try
      if t is "" or t is missing value then
        try
          click (first button of w whose subrole is "AXCloseButton")
        end try
      end if
    end repeat
  end tell
end tell
AS
  sleep 0.5
  # Re-verify the canvas window survived ghost cleanup.
  w=$(osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to count (windows whose name contains " – ")' 2>/dev/null || echo 0)
  [[ "${w:-0}" -ge 1 ]] || { echo "ERROR: canvas window missing after ghost cleanup" >&2; return 1; }
  pgrep -x MindFlow | head -1
}

uit_quit_flush(){ # graceful Cmd+Q -> willTerminate autosave rewrites the tabs slot
  osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to set frontmost to true' >/dev/null 2>&1
  sleep 0.3
  uit_require_frontmost
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
  local name="$1" ok="$2" msg="${3:-}"
  if [[ "$ok" == "0" ]]; then
    echo "PASS $name"
  else
    screencapture -x "$ART_DIR/$name.png" 2>/dev/null || true
    echo "FAIL $name: $msg (shot=$ART_DIR/$name.png)"
  fi
}

uit_wingeom(){ # echoes: x y w h
  local s
  s=$(osascript -e 'tell application "System Events" to tell (first process whose name is "MindFlow") to get {position, size} of (first window whose name contains " – ")' 2>/dev/null || true)
  echo "$s" | tr -d ' ' | awk -F',' '{print $1, $2, $3, $4}'
}

uit_axdump(){ # TSV: role x y w h value (entire contents of the canvas window)
  # Canvas window = the one whose title contains " – " (e.g. "N-0000 – v3.8 · …").
  # Ghost untitled windows (empty title) must be ignored.
  osascript <<'AS'
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set tabCh to character id 9
    try
      set w to first window whose name contains " – "
    on error
      set w to window 1
    end try
    set els to entire contents of w
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

uit_click(){ # x y — coordinate click (cliclick posts CGEvents; SE fallback)
  uit_require_frontmost
  local cc="/opt/homebrew/bin/cliclick"
  if [[ -x "$cc" ]]; then
    "$cc" -e 60 "c:$1,$2" >/dev/null 2>&1
  else
    osascript -e "tell application \"System Events\" to tell (first process whose name is \"MindFlow\") to click at {$1, $2}" >/dev/null 2>&1
  fi
}

uit_drag(){ # x1 y1 x2 y2 — press, optional micro-move, release (cliclick)
  uit_require_frontmost
  local cc="/opt/homebrew/bin/cliclick"
  "$cc" -e 40 "dd:$1,$2" >/dev/null 2>&1
  local mx=$(( ( $1 + $3 ) / 2 )) my=$(( ( $2 + $4 ) / 2 ))
  "$cc" -e 40 "dm:$mx,$my" >/dev/null 2>&1
  "$cc" -e 40 "w:80" >/dev/null 2>&1
  "$cc" -e 40 "du:$3,$4" >/dev/null 2>&1
}

uit_menu(){ # <menu bar item name> <menu item name> — AX menu click (IME-proof)
  osascript -e "tell application \"System Events\" to tell (first process whose name is \"MindFlow\") to click menu item \"$2\" of menu 1 of menu bar item \"$1\" of menu bar 1" >/dev/null 2>&1
}

uit_export_svg(){ # <fixed-output-path> — nested File > Export menu + NSSavePanel
  local target="$1" dir base stem result
  dir=$(dirname "$target"); base=$(basename "$target"); stem="${base%.svg}"
  mkdir -p "$dir"; rm -f "$target"
  result=$(osascript <<'AS' 2>/dev/null
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set fileTitle to "File"
    if exists menu bar item "檔案" of menu bar 1 then set fileTitle to "檔案"
    click menu bar item fileTitle of menu bar 1
    delay 0.2
    click menu item "SVG 向量圖…" of menu 1 of menu item "匯出" of menu 1 of menu bar item fileTitle of menu bar 1
    return "opened"
  end tell
end tell
AS
) || true
  [[ "$result" == "opened" ]] || { echo "ERROR: SVG export menu did not open" >&2; return 1; }
  sleep 0.8

  uit_require_frontmost
  osascript -e 'tell application "System Events" to keystroke "g" using {command down, shift down}' >/dev/null 2>&1
  sleep 0.4
  uit_type "$dir"
  uit_key 36
  sleep 0.8

  result=$(osascript <<AS 2>/dev/null
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set value of text field 1 of window "Save" to "$stem"
    perform action "AXPress" of button "Save" of window "Save"
    return "saved"
  end tell
end tell
AS
) || true
  [[ "$result" == "saved" ]] || { echo "ERROR: SVG save panel failed ($result)" >&2; return 1; }
  for _ in $(seq 1 50); do [[ -s "$target" ]] && return 0; sleep 0.1; done
  echo "ERROR: SVG was not written to $target" >&2
  return 1
}

uit_key(){ # keycode (36=Return, 48=Tab, 53=Esc, 123-126=arrows)
  uit_require_frontmost
  osascript -e "tell application \"System Events\" to key code $1" 2>/dev/null
}

uit_ime_switch(){ # Ensure the ABC input source before typing/keys (harness need).
  # Owner keeps an English keyboard, so we never restore Zhuyin afterwards;
  # Ctrl+Space is a toggle, so only fire it when ABC is NOT already active.
  local cur
  cur=$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null || true)
  if [[ "$cur" != *"ABC"* && "$cur" != *"com.apple.keylayout.US"* ]]; then
    uit_require_frontmost
    osascript -e 'tell application "System Events" to keystroke " " using control down' >/dev/null 2>&1
    sleep 0.8
  fi
}

uit_label_from_dump(){ # <dump> — inspector label from one explicit AX snapshot
  local wx wy ww wh
  read -r wx wy ww wh <<<"$(uit_wingeom)"
  awk -F'\t' -v wx="$wx" -v wy="$wy" -v ww="$ww" -v wh="$wh" \
    '$1=="AXStaticText" && $2>wx+0.65*ww && $3<wy+0.35*wh && ($6=="中心主題"||$6=="主題") {print $6; exit}' <<<"$1"
}

uit_label(){ # echo inspector selection label: 中心主題 (root) or 主題 (non-root)
  # Window-relative filter: inspector = right 35% / top 35% (measured: label at
  # 72% width / 20% height across builds).
  uit_label_from_dump "$(uit_axdump)"
}

uit_canvas_editing(){ # echo canvas editing TextField value (empty string if none).
  # Window-relative filter: canvas = below top 25% / left of right 35%
  # (excludes tab-bar fields at y~10% and the inspector notes field at x~74%).
  local wx wy ww wh
  read -r wx wy ww wh <<<"$(uit_wingeom)"
  uit_axdump | awk -F'\t' -v wx="$wx" -v wy="$wy" -v ww="$ww" -v wh="$wh" \
    '$1=="AXTextField" && $3>wy+0.25*wh && $2<wx+0.65*ww {print $6; exit}'
}

uit_context_menu(){ # <N-xxxx> <menu item title> — AX right-click menu on a node,
  # then AXPress the item. Coordinate-free; works under any IME.
  osascript <<AS 2>/dev/null
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set w to first window whose name contains " – "
    set els to entire contents of w
    repeat with el in els
      try
        if (role of el as text) is "AXStaticText" and (value of el as text) is "$1" then
          perform action "AXShowMenu" of el
          exit repeat
        end if
      end try
    end repeat
    delay 0.8
    set els2 to entire contents of w
    repeat with el in els2
      try
        if (role of el as text) is "AXMenuItem" and (title of el as text) is "$2" then
          perform action "AXPress" of el
          return "pressed"
        end if
      end try
    end repeat
    return "missing"
  end tell
end tell
AS
}

uit_commit_field(){ # <expected-value> — AXConfirm the editing TextField holding it
  osascript <<AS 2>/dev/null
tell application "System Events"
  tell (first process whose name is "MindFlow")
    set w to first window whose name contains " – "
    set els to entire contents of w
    repeat with el in els
      try
        if (role of el as text) is "AXTextField" and (value of el as text) is "$1" then
          perform action "AXConfirm" of el
          return "confirmed"
        end if
      end try
    end repeat
    return "missing"
  end tell
end tell
AS
}

uit_type(){ # text — cliclick Unicode typing, guarded against wrong-app delivery
  uit_require_frontmost
  local cc="/opt/homebrew/bin/cliclick"
  if [[ -x "$cc" ]]; then
    "$cc" -e 60 "t:$1" >/dev/null 2>&1
  else
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" 2>/dev/null
  fi
}

uit_node_coords(){ # <dump> <N-xxxx> -> echoes "cx cy" (element center, global screen pts, integers)
  awk -F'\t' -v n="$2" '$1=="AXStaticText" && $6==n {print int($2+$4/2), int($3+$5/2); exit}' <<<"$1"
}
