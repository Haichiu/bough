#!/usr/bin/env bash
# T-003 harness entry point.
#   bash scripts/uitest/run.sh
# Runs U1..U5 (each is also standalone-runnable), aggregates one PASS/FAIL line
# per scenario, prints a summary, and restores the app + autosave state on exit.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

COMMIT=$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "# MindFlow uitest run $(date '+%F %T') app=$(basename "$APP") commit=$COMMIT"

for s in u1 u2 u3 u4 u5; do
  echo "--- $s ---"
  bash "$UIT_DIR/$s.sh" 2>&1
done | tee /tmp/uitest-run.log

echo "--- summary ---"
grep -E '^(PASS|FAIL) ' /tmp/uitest-run.log
P=$(grep -cE '^PASS ' /tmp/uitest-run.log)
F=$(grep -cE '^FAIL ' /tmp/uitest-run.log)
echo "SUMMARY pass=$P fail=$F"
