#!/usr/bin/env bash
# T-035-W1: six GUI truth checks for the free canvas.
# The parent run.sh owns the backup transaction and restores the owner tabs.
set -u
cd "$(dirname "$0")"
source ./lib.sh
uit_prepare_backup || exit 1

cleanup(){
  if pgrep -x MindFlow >/dev/null 2>&1; then
    uit_quit_flush >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT TERM INT

# uit_stage overlays a slot; clear the backed-up directory first so the fixture
# cannot load alongside the owner’s real tabs.
uit_pkill
rm -rf "$TABS"
mkdir -p "$TABS"

uit_launch small-20 30 >/dev/null || {
  uit_report T035 1 "small-20 fixture launch failed"
  exit 1
}
sleep 0.5

T035_LIB="$UIT_DIR/lib.sh" \
T035_SLOT="$TABS/$SLOT_ID.mindmap" \
T035_ART="$ART_DIR" \
python3 /tmp/t035_probe.py
status=$?
if [[ "$status" -eq 0 ]]; then
  echo "PASS T035 six GUI checks"
else
  echo "FAIL T035 six GUI checks"
fi
exit "$status"
