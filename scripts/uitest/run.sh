#!/usr/bin/env bash
# T-003 UI test harness — runs U1..U8 sequentially, aggregates results.
# Usage: ./run.sh [u1 u2 ...]   (default: all)
set -u
cd "$(dirname "$0")"
source ./lib.sh
# Every suite starts in a fresh marked root. Inherited product/storage variables
# are discarded; children inherit only this creator-owned root.
UIT_STORAGE_BASE="${UITEST_STORAGE_BASE:-/tmp/mindflow-uitest-storage}"
case "$UIT_STORAGE_BASE" in
  /tmp/mindflow-uitest-*) ;;
  *) UIT_STORAGE_BASE="/tmp/mindflow-uitest-storage" ;;
esac
UIT_STORAGE_ROOT=""
UIT_STORAGE_OWNER=""
UIT_STORAGE_CREATOR=0
MINDFLOW_STORAGE_ROOT=""
export UIT_STORAGE_BASE UIT_STORAGE_ROOT UIT_STORAGE_OWNER UIT_STORAGE_CREATOR MINDFLOW_STORAGE_ROOT
uit_prepare_storage || exit 1
PASS=0; FAIL=0; SKIP=0
COMMIT="${UITEST_COMMIT:-$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BINARY_SHA=$(shasum -a 256 "$APP/Contents/MacOS/MindFlow" 2>/dev/null | awk '{print substr($1,1,16)}')
SCEN="${*:-u1 u2 u3 u4 u5 u6 u7 u8}"
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
