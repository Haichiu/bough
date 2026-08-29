#!/usr/bin/env bash
# U5: large-1500 同 U4 + 量測「鍵→編輯欄出現」延遲。
# 備註：Tab 無法以合成事件遞送，延遲量測改用 Return（新模型：編輯選中節點；root 於啟動時已選取），
# 量 keydown → AXFocusedUIElement 變 AXTextField 的毫秒數。
# 大地圖（1500 節點）不做 full AX dump：以 focusedRole 取代畫布欄位檢查。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_ensure_backup
uit_launch large-1500 60 >/dev/null || { uit_report U5 1 "launch failed"; exit 1; }
sleep 0.5
uit_ime_switch
lat=$(osascript -l JavaScript tablatency.jxa 8000 36 2>&1)
sleep 0.5
role=$(osascript -l JavaScript focused.jxa 2>/dev/null)
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; sleep 1.0
# add-child on selected root via menu bar（主題 → 加入子主題），再輸入 HELLO → Esc
r=$(uit_menu 主題 加入子主題)
sleep 1.5
/opt/homebrew/bin/cliclick -e 60 t:HELLO >/dev/null 2>&1; sleep 0.7
role2=$(osascript -l JavaScript focused.jxa 2>/dev/null)
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; sleep 1.0
uit_quit_flush
count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
hello=$(python3 treecompare.py findtext HELLO "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
echo "U5 latency (Return→edit-field on root): $lat  (focused-role-after-type=$role)"
echo "U5 add-child: menu=$r focused-role='$role2' count=$count (want 1501) findtext-HELLO=$hello (want 1)"
if [[ "$lat" == MS=* && "$count" == "1501" && "$hello" == "1" ]]; then
  uit_report U5 0; exit 0
fi
uit_report U5 1 "latency=$lat; count=$count findtext-HELLO=$hello — Esc 未提交編輯（同 U4）"
exit 1
