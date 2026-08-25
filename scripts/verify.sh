#!/bin/bash
# One-shot quality gate: full logic checks + optimized release build.
set -e
cd "$(dirname "$0")/.."
echo "==> UI coverage check…"
bash "$(dirname "$0")/check-ui-coverage.sh"
echo "==> Running MindFlowChecks…"
swift run MindFlowChecks
echo "==> Release build…"
swift build -c release --product MindFlow 2>&1 | tail -1
echo "==> ALL GREEN"
