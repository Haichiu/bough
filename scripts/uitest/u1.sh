#!/usr/bin/env bash
# U1: 單擊未選取節點 → 節點被選取（inspector 標籤 中心主題→主題）且不進入編輯。
# 備註：root 選取時標籤為「中心主題」；非 root 節點選取時為「主題」。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_prepare_storage || exit 1
uit_launch small-20 30 >/dev/null || { uit_report U1 1 "launch failed"; exit 1; }
sleep 0.5
D=$(uit_axdump)
printf '%s\n' "$D" > "$ART_DIR/U1-before.tsv"
before=$(uit_label_from_dump "$D")
read CX CY <<<"$(uit_node_coords "$D" N-0005)"
if [[ -z "$CX" ]]; then uit_report U1 1 "N-0005 not in AX tree"; uit_quit_flush; exit 1; fi
uit_click "$CX" "$CY"; sleep 0.9
D2=$(uit_axdump)
printf '%s\n' "$D2" > "$ART_DIR/U1-after.tsv"
after=$(uit_label_from_dump "$D2")
before_candidates=$(awk -F'\t' '$1=="AXStaticText" && ($6=="中心主題"||$6=="主題") {printf "%s@%s,%s ", $6,$2,$3}' <<<"$D")
after_candidates=$(awk -F'\t' '$1=="AXStaticText" && ($6=="中心主題"||$6=="主題") {printf "%s@%s,%s ", $6,$2,$3}' <<<"$D2")
echo "U1 label-candidates before=[$before_candidates] after=[$after_candidates]"
editing=$(uit_canvas_editing)
uit_quit_flush
if [[ "$before" == "中心主題" && "$after" == "主題" && -z "$editing" ]]; then
  uit_report U1 0; exit 0
fi
uit_report U1 1 "label '$before'->'$after' (expect 中心主題->主題), editing='$editing' (expect empty)"
exit 1
