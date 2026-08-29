#!/usr/bin/env bash
# Offline tabs transaction probe. Uses a fake HOME and refuses to run while MindFlow is alive.
# Usage: ./test-backup-transaction.sh safe [uitest-source-dir]
#        ./test-backup-transaction.sh unsafe <historical-uitest-source-dir>
set -euo pipefail
MODE="${1:-safe}"
SOURCE="${2:-$(cd "$(dirname "$0")" && pwd)}"
BASE=/tmp/mindflow-backup-transaction-test
RUNNER="$BASE/runner"
HOME_FAKE="$BASE/home"
SUPPORT="$HOME_FAKE/Library/Application Support/MindFlow"
TABS="$SUPPORT/tabs"

[[ "$MODE" == safe || "$MODE" == unsafe ]] || { echo "usage: $0 safe|unsafe [source]" >&2; exit 2; }
pgrep -x MindFlow >/dev/null 2>&1 && { echo "ERROR: refuse transaction probe while MindFlow runs" >&2; exit 3; }
rm -rf "$BASE"; mkdir -p "$RUNNER"; cp -R "$SOURCE"/. "$RUNNER"/
cleanup(){ chmod 700 "$SUPPORT" 2>/dev/null || true; rm -rf "$BASE"; }
trap cleanup EXIT INT TERM

digest(){ shasum -a 256 "$TABS/data" | awk '{print $1}'; }
reset_home(){
  chmod 700 "$SUPPORT" 2>/dev/null || true
  rm -rf "$HOME_FAKE"; mkdir -p "$TABS"; printf 'owner-original\n' > "$TABS/data"
}

# Negative path: backup destination cannot be created, so the scenario must never run.
cat > "$RUNNER/mutate.sh" <<'SH'
#!/usr/bin/env bash
printf 'MUTATED-AFTER-BACKUP-FAILURE\n' > "$HOME/Library/Application Support/MindFlow/tabs/data"
echo 'PASS mutate-ran'
SH
chmod +x "$RUNNER/mutate.sh"
reset_home; before=$(digest); chmod 500 "$SUPPORT"
set +e
HOME="$HOME_FAKE" bash "$RUNNER/run.sh" mutate > "$BASE/failure.log" 2>&1
failure_rc=$?
set -e
chmod 700 "$SUPPORT"; after=$(digest)
if [[ "$MODE" == unsafe ]]; then
  [[ $failure_rc -eq 0 && "$before" != "$after" ]] || {
    cat "$BASE/failure.log"; echo "expected historical unsafe behavior" >&2; exit 1;
  }
  echo "EXPECTED_FAIL historical backup guarantee: rc=$failure_rc tabs_changed=yes"
  exit 0
fi
[[ $failure_rc -ne 0 && "$before" == "$after" ]] || {
  cat "$BASE/failure.log"; echo "backup failure did not fail closed" >&2; exit 1;
}
echo "PASS backup-failure rc=$failure_rc tabs_unchanged=yes"

# Suite path: run.sh discards stale inherited env, owns one fresh snapshot, and its
# child can neither restore nor delete it. Parent restores the original on exit.
cat > "$RUNNER/mutate.sh" <<'SH'
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_prepare_backup || exit 1
printf 'child owner=%s self=%s backup=%s\n' "$UIT_BACKUP_OWNER" "$$" "$UIT_BACKUP"
printf 'suite-mutated\n' > "$TABS/data"
uit_restore
[[ "$(cat "$TABS/data")" == suite-mutated ]]
echo 'PASS child-used-parent-transaction'
SH
chmod +x "$RUNNER/mutate.sh"
reset_home; before=$(digest)
HOME="$HOME_FAKE" UIT_BACKUP=/tmp/stale-uitest-backup UIT_BACKUP_OWNER=999999 \
  bash "$RUNNER/run.sh" mutate > "$BASE/suite.log" 2>&1
suite_rc=$?; after=$(digest)
owner=$(awk -F'[ =]' '/child owner=/{print $3}' "$BASE/suite.log")
self=$(awk -F'[ =]' '/child owner=/{print $5}' "$BASE/suite.log")
backups=$(find "$SUPPORT" -maxdepth 1 -type d -name 'tabs.pre-uitest-*' | wc -l | tr -d ' ')
[[ $suite_rc -eq 0 && "$before" == "$after" && -n "$owner" && "$owner" != "$self" && $backups -eq 0 ]] || {
  cat "$BASE/suite.log"; echo "suite transaction ownership failed" >&2; exit 1;
}
echo "PASS suite owner=$owner child=$self tabs_restored=yes residual_backups=0"

# Standalone scenario owns its snapshot and its EXIT trap restores/deletes it.
cat > "$RUNNER/standalone.sh" <<'SH'
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_prepare_backup || exit 1
printf 'standalone-mutated\n' > "$TABS/data"
echo 'PASS standalone-owned-transaction'
SH
chmod +x "$RUNNER/standalone.sh"
reset_home; before=$(digest)
env -u UIT_BACKUP -u UIT_BACKUP_OWNER HOME="$HOME_FAKE" \
  bash "$RUNNER/standalone.sh" > "$BASE/standalone.log" 2>&1
standalone_rc=$?; after=$(digest)
backups=$(find "$SUPPORT" -maxdepth 1 -type d -name 'tabs.pre-uitest-*' | wc -l | tr -d ' ')
[[ $standalone_rc -eq 0 && "$before" == "$after" && $backups -eq 0 ]] || {
  cat "$BASE/standalone.log"; echo "standalone transaction ownership failed" >&2; exit 1;
}
echo 'PASS standalone tabs_restored=yes residual_backups=0'
