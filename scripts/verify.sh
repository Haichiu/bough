#!/bin/bash
# One-shot quality gate: full logic checks + optimized release build.
set -e
cd "$(dirname "$0")/.."
echo "==> Storage isolation check…"
bash "$(dirname "$0")/uitest/test-storage-isolation.sh"
echo "==> UI coverage check…"
bash "$(dirname "$0")/check-ui-coverage.sh"
echo "==> No bare-key menu shortcuts…"
# macOS matches menu key equivalents before the first responder, so an unmodified
# menu shortcut hijacks the key while the user is typing into a node editor.
if grep -n 'modifiers: \[\]' Sources/MindFlow/MindFlowApp.swift; then
  echo "FAIL: menu shortcut without modifiers (see lines above)" >&2
  exit 1
fi

echo "==> Running MindFlowChecks…"
swift run MindFlowChecks
echo "==> Release build…"
swift build -c release --product Bough 2>&1 | tail -1
echo "==> ALL GREEN"
