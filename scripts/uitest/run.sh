#!/usr/bin/env bash
# T-003 UI test harness — runs U1..U7 sequentially, aggregates results.
# Usage: ./run.sh [u1 u2 ...]   (default: all)
set -u
cd "$(dirname "$0")"
source ./lib.sh
# The suite owns one fresh snapshot. Children inherit this exact transaction;
# any UIT_BACKUP left in the caller environment is intentionally discarded.
uit_new_backup
uit_ensure_backup || exit 1
export UIT_BACKUP UIT_BACKUP_OWNER
trap uit_restore EXIT TERM INT
PASS=0; FAIL=0; SKIP=0
COMMIT="${UITEST_COMMIT:-$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BINARY_SHA=$(shasum -a 256 "$APP/Contents/MacOS/MindFlow" 2>/dev/null | awk '{print substr($1,1,16)}')
SCEN="${*:-u1 u2 u3 u4 u5 u6 u7}"
for s in $SCEN; do
  echo "===== $s ====="
  out=$(bash "./$s.sh" 2>&1); status=$?
  echo "$out"
  if [[ $status -eq 70 ]]; then
    echo "ABORT: foreground ownership lost during $s"
    exit 70
  fi
  last=$(printf '%s\n' "$out" | tail -1)
  if [[ $status -eq 0 && "$last" == PASS* ]]; then
    PASS=$((PASS+1))
  elif [[ $status -eq 77 && "$last" == SKIP* ]]; then
    SKIP=$((SKIP+1))
  else
    FAIL=$((FAIL+1))
  fi
done
echo "-----"
echo "SUMMARY pass=$PASS fail=$FAIL skip=$SKIP"
echo "commit=$COMMIT binary_sha256=${BINARY_SHA:-unknown} date=$(date '+%F %T') app=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
