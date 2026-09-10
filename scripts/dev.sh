#!/usr/bin/env bash
# T-001 — one-command rebuild & launch with a fixture map loaded.
#
# Usage:
#   bash scripts/dev.sh                # build + relaunch with small-20 fixture
#   bash scripts/dev.sh medium-200     # …with a specific fixture
#   bash scripts/dev.sh restore        # put the pre-dev user tabs back
#
# HOW FIXTURE LOADING WORKS (investigated, do not "fix" without re-reading Sources):
#   * MindFlowApp.swift has NO command-line-argument or open-file handling.
#   * FileIO.swift restores startup tabs from
#       ~/Library/Application Support/MindFlow/tabs/<UUID>.mindmap
#     (MindMapViewModel.init -> FileIO.loadTabs; filename stem MUST be a UUID,
#     newest mtime first becomes the active tab).
#   Therefore this script: backs up the user's tabs/ once (kept at
#   tabs.pre-dev-backup), swaps in a single slot holding the chosen fixture,
#   then launches the freshly built binary. `restore` puts the original back.
#   Nothing under Sources/ is modified.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="${1:-small-20}"
FIXTURE="scripts/fixtures/$NAME.mindmap"
APP_SUPPORT="$HOME/Library/Application Support/MindFlow"
TABS="$APP_SUPPORT/tabs"
BACKUP="$APP_SUPPORT/tabs.pre-dev-backup"
SLOT_ID="0D3F1CE0-0000-4000-8000-0000000000F1"   # fixed test session UUID

if [[ "$NAME" == "restore" ]]; then
  [[ -d "$BACKUP" ]] || { echo "no backup at $BACKUP — nothing to restore"; exit 0; }
  pkill -x Bough 2>/dev/null || true
  sleep 1
  rm -rf "$TABS"
  cp -R "$BACKUP" "$TABS"
  rm -rf "$BACKUP"
  echo "tabs/ restored from $BACKUP"
  exit 0
fi

# --- 1. fixture (auto-generate the standard sizes if missing) ---
if [[ ! -f "$FIXTURE" ]]; then
  echo "==> fixture missing, generating standard sizes"
  bash scripts/make-fixture.sh
fi
[[ -f "$FIXTURE" ]] || { echo "ERROR: fixture $FIXTURE not found" >&2; exit 1; }

# --- 2. build ---
# The owner may be mid-edit in Sources/ (build can transiently fail). If a
# previously built binary exists, run it with a LOUD warning so the feedback
# loop stays alive; otherwise fail hard.
echo "==> swift build"
BIN="$ROOT/.build/debug/Bough"
if ! swift build; then
  if [[ -x "$BIN" ]]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "!! WARNING: swift build FAILED — running LAST SUCCESSFUL binary" >&2
    echo "!! ($(stat -f '%Sm' "$BIN"))   Measurements apply to that build, not HEAD." >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
  else
    echo "ERROR: build failed and no existing binary at $BIN" >&2
    exit 1
  fi
fi
[[ -x "$BIN" ]] || { echo "ERROR: $BIN not found" >&2; exit 1; }

# --- 3. terminate old instance, let its quit-autosave finish ---
pkill -x Bough 2>/dev/null || true
for _ in $(seq 1 50); do pgrep -x Bough >/dev/null 2>&1 || break; sleep 0.1; done

# --- 4. stage fixture as the only restore slot (backup first, once) ---
mkdir -p "$APP_SUPPORT"
if [[ ! -d "$BACKUP" && -d "$TABS" ]]; then
  cp -R "$TABS" "$BACKUP"
  echo "==> user tabs backed up to: $BACKUP (restore with: bash scripts/dev.sh restore)"
fi
rm -rf "$TABS"
mkdir -p "$TABS"
cp "$FIXTURE" "$TABS/$SLOT_ID.mindmap"
touch "$TABS/$SLOT_ID.mindmap"   # newest mtime => becomes the active tab

# --- 5. launch ---
nohup "$BIN" >/tmp/mindflow-dev.log 2>&1 &
disown || true
for _ in $(seq 1 100); do
  pgrep -x Bough >/dev/null 2>&1 && break
  sleep 0.1
done
sleep 1
PID="$(pgrep -x Bough | head -1 || true)"
if [[ -z "$PID" ]]; then
  echo "ERROR: Bough did not start; log tail:" >&2
  tail -5 /tmp/mindflow-dev.log >&2 || true
  exit 1
fi
echo "==> Bough running (pid $PID), fixture loaded: $NAME"
echo "    app log: /tmp/mindflow-dev.log"
