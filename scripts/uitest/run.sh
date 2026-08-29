#!/usr/bin/env bash
# T-003 UI test harness — runs U1..U5 sequentially, aggregates results.
# Usage: ./run.sh [u1 u2 ...]   (default: all)
set -u
cd "$(dirname "$0")"
source ./lib.sh
uit_ensure_backup
trap uit_restore EXIT TERM INT
PASS=0; FAIL=0
SCEN="${*:-u1 u2 u3 u4 u5 u6}"
for s in $SCEN; do
  echo "===== $s ====="
  out=$(bash "./$s.sh" 2>&1); status=$?
  echo "$out"
  last=$(printf '%s\n' "$out" | tail -1)
  if [[ $status -eq 0 && "$last" == PASS* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
done
echo "-----"
echo "SUMMARY pass=$PASS fail=$FAIL"
COMMIT=$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "commit=$COMMIT date=$(date '+%F %T') app=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
