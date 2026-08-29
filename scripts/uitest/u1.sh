#!/usr/bin/env bash
# U1 — click an unselected node once -> it becomes selected (breadcrumb shows it),
# and no editing text field appears (AXTextField count unchanged).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
trap uit_restore EXIT
uit_ensure_backup

uit_launch small-20 30 >/dev/null || { uit_report U1 1 "app launch failed"; exit 1; }
sleep 0.5

DUMP=$(uit_axdump)
BASE_FIELDS=$(awk -F'\t' '$1=="AXTextField"' <<<"$DUMP" | wc -l | tr -d ' ')
read -r CX CY <<<"$(uit_node_coords "$DUMP" N-0007)"
if [[ -z "${CX:-}" ]]; then uit_report U1 1 "node N-0007 not found in AX tree"; exit 1; fi

uit_click "$CX" "$CY"
sleep 0.6

DUMP2=$(uit_axdump)
AFTER_FIELDS=$(awk -F'\t' '$1=="AXTextField"' <<<"$DUMP2" | wc -l | tr -d ' ')
read -r WX WY WW WH <<<"$(uit_wingeom)"
BC=$(awk -F'\t' -v ymin="$((WY + WH - 90))" '$1=="AXStaticText" && ($3+0)>=ymin && $6 ~ /N-0007/' <<<"$DUMP2" | wc -l | tr -d ' ')

if [[ "$BC" -ge 1 && "$AFTER_FIELDS" -eq "$BASE_FIELDS" ]]; then
  uit_report U1 0
else
  uit_report U1 1 "breadcrumb-hit=$BC (expect >=1), AXTextField $BASE_FIELDS->$AFTER_FIELDS (expect unchanged)"
fi
