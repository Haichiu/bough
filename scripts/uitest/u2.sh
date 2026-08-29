#!/usr/bin/env bash
# U2 — clicking the already-selected node again enters editing: an editable
# text field appears AND holds keyboard focus (AXFocusedUIElement becomes a
# text editor role).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

uit_launch small-20 30 >/dev/null || { uit_report U2 1 "app launch failed"; exit 1; }
sleep 0.5

DUMP=$(uit_axdump)
BASE_FIELDS=$(awk -F'\t' '$1=="AXTextField"' <<<"$DUMP" | wc -l | tr -d ' ')
read -r CX CY <<<"$(uit_node_coords "$DUMP" N-0007)"
if [[ -z "${CX:-}" ]]; then uit_report U2 1 "node N-0007 not found in AX tree"; exit 1; fi

uit_click "$CX" "$CY"      # first click: select
sleep 0.6
uit_click "$CX" "$CY"      # second click: enter editing

FIELD_OK=0; FOCUS_OK=0; LAST_ROLE=""
for _ in $(seq 1 12); do
  sleep 0.3
  DUMP2=$(uit_axdump)
  AFTER_FIELDS=$(awk -F'\t' '$1=="AXTextField"' <<<"$DUMP2" | wc -l | tr -d ' ')
  LAST_ROLE=$(osascript -l JavaScript "$UIT_DIR/focused.jxa" 2>/dev/null)
  [[ "$AFTER_FIELDS" -gt "$BASE_FIELDS" ]] && FIELD_OK=1
  [[ "$LAST_ROLE" == "AXTextArea" || "$LAST_ROLE" == "AXTextField" ]] && { FOCUS_OK=1; break; }
done

if [[ "$FIELD_OK" == "1" && "$FOCUS_OK" == "1" ]]; then
  uit_report U2 0
else
  uit_report U2 1 "edit-field=$FIELD_OK focused-role='$LAST_ROLE' (expect field + AXTextArea/AXTextField)"
fi
