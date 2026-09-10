#!/usr/bin/env bash
# Offline storage-isolation harness test. It never reads or writes owner tabs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/scripts/uitest/lib.sh"
RUN="$REPO/scripts/uitest/run.sh"
pgrep -x Bough >/dev/null 2>&1 && {
  echo "ERROR: refuse storage-isolation test while Bough runs" >&2
  exit 3
}

BASE="$(mktemp -d /tmp/mindflow-uitest-storage-test.XXXXXX)"
case "$BASE" in
  /tmp/mindflow-uitest-storage-test.*) ;;
  *) echo "ERROR: unexpected test root $BASE" >&2; exit 1 ;;
esac
cleanup(){
  if [[ -d "$BASE" && "$BASE" == /tmp/mindflow-uitest-storage-test.* ]]; then
    rm -rf "$BASE"
  fi
}
trap cleanup EXIT INT TERM

MARKER_FILE='.mindflow-uitest-root'
MARKER_CONTENT='mindflow-uitest-storage-v1'

digest(){ shasum -a 256 "$1" | awk '{print $1}'; }
assert_file(){ [[ -f "$1" ]] || { echo "FAIL missing file $1" >&2; exit 1; }; }
assert_absent(){ [[ ! -e "$1" ]] || { echo "FAIL path remains $1" >&2; exit 1; }; }

# A failing extra callback must not skip the creator's core storage cleanup.
cat > "$BASE/callback-child.sh" <<'SH'
#!/usr/bin/env bash
set -u
LIB_PATH="$1"; STORAGE_BASE="$2"; ROOT_OUT="$3"
export UITEST_STORAGE_BASE="$STORAGE_BASE"
source "$LIB_PATH"
uit_prepare_storage || exit 1
printf '%s' "$UIT_STORAGE_ROOT" > "$ROOT_OUT"
failing_extra_cleanup(){ return 41; }
uit_register_cleanup failing_extra_cleanup
exit 0
SH
chmod +x "$BASE/callback-child.sh"
OWNER_SENTINEL="$BASE/fake-owner-sentinel"
printf 'owner-sentinel-before\n' > "$OWNER_SENTINEL"
OWNER_DIGEST_BEFORE="$(digest "$OWNER_SENTINEL")"
CALLBACK_BASE="$BASE/callback-base"
mkdir -p "$CALLBACK_BASE"
CALLBACK_ROOT_FILE="$BASE/callback-root"
set +e
bash "$BASE/callback-child.sh" "$LIB" "$CALLBACK_BASE" "$CALLBACK_ROOT_FILE" > "$BASE/callback.log" 2>&1
CALLBACK_RC=$?
set -e
assert_file "$CALLBACK_ROOT_FILE"
CALLBACK_ROOT="$(cat "$CALLBACK_ROOT_FILE")"
[[ "$CALLBACK_RC" -ne 0 ]] || { cat "$BASE/callback.log" >&2; echo 'FAIL callback failure was swallowed' >&2; exit 1; }
assert_absent "$CALLBACK_ROOT"
[[ "$(digest "$OWNER_SENTINEL")" == "$OWNER_DIGEST_BEFORE" ]] || {
  echo 'FAIL fake owner sentinel changed' >&2; exit 1;
}
echo "PASS failing extra cleanup still removes creator root (rc=$CALLBACK_RC)"

# Mutation control: skip the core cleanup in a temporary copy. The same
# assertion must then fail, proving the green result is not vacuous.
MUTATED_LIB="$BASE/mutated-lib.sh"
sed 's/^  uit_cleanup_storage$/  : # MUTATION: skip core storage cleanup/' "$LIB" > "$MUTATED_LIB"
MUT_ROOT_FILE="$BASE/mutated-root"
MUT_BASE="$BASE/mutation-base"
mkdir -p "$MUT_BASE"
set +e
bash "$BASE/callback-child.sh" "$MUTATED_LIB" "$MUT_BASE" "$MUT_ROOT_FILE" > "$BASE/mutation.log" 2>&1
MUT_CHILD_RC=$?
set -e
assert_file "$MUT_ROOT_FILE"
MUT_ROOT="$(cat "$MUT_ROOT_FILE")"
[[ "$MUT_CHILD_RC" -ne 0 ]] || { cat "$BASE/mutation.log" >&2; echo 'FAIL cleanup mutation did not exercise callback failure' >&2; exit 1; }
if [[ -e "$MUT_ROOT" ]]; then
  MUTATION_RC=1
  echo "MUTATION_RC=1 first=callback cleanup did not remove core storage root"
else
  echo 'FAIL mutation unexpectedly retained cleanup invariant' >&2
  exit 1
fi

# run.sh must discard stale inherited storage variables and create a fresh root.
STALE_ROOT="$BASE/stale-inherited"
mkdir -p "$STALE_ROOT"
printf 'stale-sentinel\n' > "$STALE_ROOT/sentinel"
STALE_DIGEST_BEFORE="$(digest "$STALE_ROOT/sentinel")"
RUNNER="$BASE/runner/scripts/uitest"
mkdir -p "$RUNNER"
cp "$LIB" "$RUNNER/lib.sh"
cp "$RUN" "$RUNNER/run.sh"
chmod +x "$RUNNER/lib.sh" "$RUNNER/run.sh"
cat > "$RUNNER/probe.sh" <<'SH'
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
source ./lib.sh
uit_prepare_storage || exit 1
if [[ "$UIT_STORAGE_ROOT" == "$STALE_ROOT" ]]; then
  echo 'FAIL run.sh retained stale storage root'
  exit 1
fi
printf '%s' "$UIT_STORAGE_ROOT" > "$ROOT_OUT"
echo 'PASS run replaced stale inherited storage root'
SH
chmod +x "$RUNNER/probe.sh"
RUN_BASE="$BASE/run-base"
RUN_ROOT_FILE="$BASE/run-root"
set +e
env \
  UITEST_STORAGE_BASE="$RUN_BASE" \
  UIT_STORAGE_ROOT="$STALE_ROOT" \
  UIT_STORAGE_OWNER=999999999 \
  MINDFLOW_STORAGE_ROOT="$STALE_ROOT" \
  STALE_ROOT="$STALE_ROOT" \
  ROOT_OUT="$RUN_ROOT_FILE" \
  bash "$RUNNER/run.sh" probe > "$BASE/run.log" 2>&1
RUN_RC=$?
set -e
[[ "$RUN_RC" -eq 0 ]] || { cat "$BASE/run.log" >&2; echo 'FAIL run.sh stale-env replacement' >&2; exit 1; }
assert_file "$RUN_ROOT_FILE"
RUN_ROOT="$(cat "$RUN_ROOT_FILE")"
[[ "$RUN_ROOT" != "$STALE_ROOT" ]] || { echo 'FAIL run root equals stale root' >&2; exit 1; }
assert_absent "$RUN_ROOT"
[[ "$(digest "$STALE_ROOT/sentinel")" == "$STALE_DIGEST_BEFORE" ]] || {
  echo 'FAIL stale inherited sentinel changed' >&2; exit 1;
}
echo 'PASS stale inherited storage remains untouched'

# Cleanup must refuse an unmarked path even when a caller labels itself creator.
UNMARKED_BASE="$BASE/unmarked-base"
mkdir -p "$UNMARKED_BASE"
UNMARKED="$BASE/unmarked-root"
mkdir -p "$UNMARKED"
printf 'unmarked-sentinel\n' > "$UNMARKED/sentinel"
UNMARKED_DIGEST_BEFORE="$(digest "$UNMARKED/sentinel")"
cat > "$BASE/unmarked-child.sh" <<'SH'
#!/usr/bin/env bash
set -u
LIB_PATH="$1"; STORAGE_BASE="$2"; ROOT="$3"
export UITEST_STORAGE_BASE="$STORAGE_BASE"
source "$LIB_PATH"
UIT_STORAGE_ROOT="$ROOT"
UIT_STORAGE_OWNER=$$
UIT_STORAGE_CREATOR=1
if uit_cleanup_storage; then
  echo 'FAIL unmarked cleanup was allowed'
  exit 1
fi
echo 'PASS unmarked cleanup refused'
SH
chmod +x "$BASE/unmarked-child.sh"
set +e
bash "$BASE/unmarked-child.sh" "$LIB" "$UNMARKED_BASE" "$UNMARKED" > "$BASE/unmarked.log" 2>&1
UNMARKED_RC=$?
set -e
[[ "$UNMARKED_RC" -eq 0 ]] || { cat "$BASE/unmarked.log" >&2; exit 1; }
[[ "$(digest "$UNMARKED/sentinel")" == "$UNMARKED_DIGEST_BEFORE" ]] || {
  echo 'FAIL unmarked sentinel changed' >&2; exit 1;
}
echo 'PASS unmarked storage remains untouched'

# A valid root owns tabs/recovery/autosave together and is removed by its creator.
VALID_BASE="$BASE/valid-base"
mkdir -p "$VALID_BASE"
VALID_ROOT_FILE="$BASE/valid-root"
cat > "$BASE/valid-child.sh" <<'SH'
#!/usr/bin/env bash
set -u
LIB_PATH="$1"; STORAGE_BASE="$2"; ROOT_OUT="$3"
export UITEST_STORAGE_BASE="$STORAGE_BASE"
source "$LIB_PATH"
uit_prepare_storage || exit 1
printf '%s' "$UIT_STORAGE_ROOT" > "$ROOT_OUT"
printf 'fixture\n' > "$TABS/fixture.mindmap"
printf 'recovery\n' > "$UIT_STORAGE_ROOT/recovery/copy.mindmap"
printf 'autosave\n' > "$UIT_STORAGE_ROOT/autosave.mindmap"
echo 'PASS valid marker routes all stores'
exit 0
SH
chmod +x "$BASE/valid-child.sh"
set +e
bash "$BASE/valid-child.sh" "$LIB" "$VALID_BASE" "$VALID_ROOT_FILE" > "$BASE/valid.log" 2>&1
VALID_RC=$?
set -e
[[ "$VALID_RC" -eq 0 ]] || { cat "$BASE/valid.log" >&2; exit 1; }
assert_file "$VALID_ROOT_FILE"
VALID_ROOT="$(cat "$VALID_ROOT_FILE")"
assert_absent "$VALID_ROOT"
echo 'PASS valid marked storage root cleaned after child exit'

# Retention pruning is 24-hour bounded and conservative about ownership/markers.
PRUNE_BASE="$BASE/prune-base"
mkdir -p "$PRUNE_BASE"
OLD="$(date -v-2d '+%Y%m%d%H%M.%S')"
seed_marked(){
  local name="$1" dir="$PRUNE_BASE/$1"
  mkdir -p "$dir"
  printf '%s' "$MARKER_CONTENT" > "$dir/$MARKER_FILE"
  touch -t "$OLD" "$dir"
}
seed_marked 'run-999999999-1000000000-1'
seed_marked 'run-999999999-1000000001-2'
seed_marked "run-$$-1000000002-3"
UNMARKED_OLD="$PRUNE_BASE/run-999999999-1000000003-4"
mkdir -p "$UNMARKED_OLD"
printf 'not-marked' > "$UNMARKED_OLD/sentinel"
touch -t "$OLD" "$UNMARKED_OLD"
UITEST_STORAGE_BASE="$PRUNE_BASE"
export UITEST_STORAGE_BASE
# Source the same production harness functions; this only touches the fresh test base.
source "$LIB"
UIT_STORAGE_BASE="$PRUNE_BASE"
uit_prune_storage
assert_absent "$PRUNE_BASE/run-999999999-1000000000-1"
assert_absent "$PRUNE_BASE/run-999999999-1000000001-2"
[[ -d "$PRUNE_BASE/run-$$-1000000002-3" ]] || { echo 'FAIL live-owner root was pruned' >&2; exit 1; }
[[ -d "$UNMARKED_OLD" ]] || { echo 'FAIL unmarked root was pruned' >&2; exit 1; }
echo 'PASS 24-hour pruning removes only stale dead-owner marked roots'

echo 'PASS storage-isolation offline controls'
