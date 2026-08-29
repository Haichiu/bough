#!/usr/bin/env bash
# U2: 再擊同一節點 → 進入編輯（畫布出現帶節點原文字的 TextField）。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_ensure_backup
uit_launch small-20 30 >/dev/null || { uit_report U2 1 "launch failed"; exit 1; }
sleep 0.5
D=$(uit_axdump); read CX CY <<<"$(uit_node_coords "$D" N-0005)"
if [[ -z "$CX" ]]; then uit_report U2 1 "N-0005 not in AX tree"; uit_quit_flush; exit 1; fi
uit_click "$CX" "$CY"; sleep 0.8
uit_click "$CX" "$CY"; sleep 0.9
editing=$(uit_canvas_editing)
uit_quit_flush
if [[ "$editing" == "N-0005" ]]; then
  uit_report U2 0; exit 0
fi
uit_report U2 1 "canvas editing field='$editing' (expect 'N-0005')"
exit 1
