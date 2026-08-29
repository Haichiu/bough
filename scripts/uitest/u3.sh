#!/usr/bin/env bash
# U3: 拖曳語義。a) 3px 拖曳 = 視同點擊：節點被選取（標籤翻轉）且樹不變。
#     b) 12px 拖曳 = 真拖曳：不應視為點擊（標籤不翻轉）；樹可變（回報 diff）。
# 兩階段各自重新 stage+launch 以求隔離。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_ensure_backup
FIX="$PROJ/scripts/fixtures/small-20.mindmap"
okA=1; okB=1; msgA=""; msgB=""

# ---- 3px ----
uit_launch small-20 30 >/dev/null || { uit_report U3 1 "launch failed (3px)"; exit 1; }
sleep 0.5
before=$(uit_label)
D=$(uit_axdump); read CX CY <<<"$(uit_node_coords "$D" N-0006)"
if [[ -z "$CX" ]]; then uit_report U3 1 "N-0006 not in AX tree"; uit_quit_flush; exit 1; fi
uit_drag "$CX" "$CY" "$CX" "$((CY+3))"; sleep 1.0
after=$(uit_label)
uit_quit_flush
ident=$(python3 treecompare.py identical "$FIX" "$TABS/$SLOT_ID.mindmap" 2>&1)
if [[ "$before" == "中心主題" && "$after" == "主題" && "$ident" == "IDENTICAL" ]]; then okA=0; else msgA="label '$before'->'$after', tree=$ident"; fi

# ---- 12px ----
uit_launch small-20 30 >/dev/null || { uit_report U3 1 "launch failed (12px)"; exit 1; }
sleep 0.5
beforeB=$(uit_label)
D=$(uit_axdump); read CX CY <<<"$(uit_node_coords "$D" N-0006)"
uit_drag "$CX" "$CY" "$CX" "$((CY+12))"; sleep 1.0
afterB=$(uit_label)
uit_quit_flush
p6=$(python3 treecompare.py parentof N-0006 "$TABS/$SLOT_ID.mindmap" 2>&1)
if [[ "$beforeB" == "中心主題" && "$afterB" == "中心主題" ]]; then okB=0; else msgB="label '$beforeB'->'$afterB' (12px drag was treated as click)"; fi

echo "U3a(3px=click) $([[ $okA -eq 0 ]] && echo PASS || echo "FAIL: $msgA") tree=$ident"
echo "U3b(12px=drag) $([[ $okB -eq 0 ]] && echo PASS || echo "FAIL: $msgB") parentof-N-0006=$p6 (fixture: N-0001)"
if [[ $okA -eq 0 && $okB -eq 0 ]]; then uit_report U3 0; exit 0; fi
uit_report U3 1 "see U3a/U3b lines"
exit 1
