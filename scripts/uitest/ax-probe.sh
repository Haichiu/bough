#!/usr/bin/env bash
# T-003 — Accessibility tree probe (DECISION PROBE, read-only: no clicks, no edits).
#
# Usage:  bash scripts/uitest/ax-probe.sh [pid]   # defaults to first Bough pid
#
# Answers exactly one question for the owner:
#   Are the mind-map canvas nodes (fixture text "N-0042") present in the macOS
#   accessibility tree, and addressable by name/role?
#   Output: flat AX dump on stdout. Summary/HIT lines carry position/size/actions
#   for each matched node element.
#
# Requires: Bough running with a fixture loaded (staging + launch are dev.sh's
# job), and Accessibility permission for the calling terminal.
set -euo pipefail

PID="${1:-$(pgrep -x Bough | head -1)}"
[[ -n "$PID" ]] || { echo "ERROR: Bough not running — load a fixture first (see scripts/dev.sh)" >&2; exit 1; }

osascript - "$PID" <<'AS'
on run argv
  set pidStr to item 1 of argv
  set oldDelims to AppleScript's text item delimiters
  set AppleScript's text item delimiters to linefeed
  tell application "System Events"
    tell (first process whose unix id is (pidStr as integer))
      set winTitle to ""
      try
        set winTitle to name of window 1 as text
      end try
      set els to entire contents of window 1
      set n to count of els
      set cap to 4000
      set dump to {"WINDOW_TITLE=" & winTitle, "TOTAL_ELEMENTS=" & n}
      set hitLines to {}
      set hitRefs to {}
      set i to 0
      repeat with el in els
        set i to i + 1
        if i > cap then exit repeat
        set r to ""
        set sr to ""
        set d to ""
        set t to ""
        set v to ""
        try
          set r to role of el as text
        end try
        try
          set sr to subrole of el as text
        end try
        try
          set d to description of el as text
        end try
        try
          set t to title of el as text
        end try
        try
          set vv to value of el
          if class of vv is text then set v to vv
        end try
        if (length of v) > 80 then set v to (text 1 thru 80 of v) & "…"
        set oneLine to r & (my joinIf("/", sr)) & " | d=" & d & " | t=" & t & " | v=" & v
        set end of dump to oneLine
        if (t starts with "N-") or (d starts with "N-") or (v starts with "N-") then
          if (count of hitLines) < 20 then
            set posTxt to "?"
            set sizeTxt to "?"
            set actTxt to "?"
            try
              set p to position of el
              set posTxt to (item 1 of p as text) & "," & (item 2 of p as text)
            end try
            try
              set s to size of el
              set sizeTxt to (item 1 of s as text) & "x" & (item 2 of s as text)
            end try
            try
              set ans to name of actions of el
              set AppleScript's text item delimiters to ","
              set actTxt to ans as text
              set AppleScript's text item delimiters to linefeed
            end try
            set end of hitLines to oneLine & " | pos=" & posTxt & " | size=" & sizeTxt & " | actions=" & actTxt
          end if
        end if
      end repeat
    end tell
  end tell
  set out to (dump as text) & linefeed & "HITS_COUNT=" & (count of hitLines) & linefeed & "HITS_START" & linefeed & (hitLines as text)
  set AppleScript's text item delimiters to oldDelims
  return out
end run

on joinIf(sep, s)
  if s is "" then return ""
  return sep & s
end joinIf
AS
