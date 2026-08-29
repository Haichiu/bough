#!/usr/bin/env bash
# U6: 選取非根節點 → 加入子主題 → 輸入 HELLO → AXConfirm 提交 → flush。
# 目的：替 owner 回報的兩個現行 bug 取得自動化證據（決策者 wD:p1 指示）。
#   a) 提交後節點總數應恰好 +1（bug 時 +2：多生一個兄弟節點）。
#   b) 提交後焦點不應自動跳進右側備註欄（AXFocusedUIElement 變 AXTextArea）。
# 判別：AXConfirm 是否觸發 SwiftUI TextField 的 .onSubmit —
#   count +1/+2 → 有走 onSubmit，證據成立；
#   count +0   → AXConfirm 繞過 onSubmit = HARNESS 限制（非 app bug），
#                以 FAIL 回報並記入 baseline「無法自動驗證」清單。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_ensure_backup
uit_launch small-20 30 >/dev/null || { uit_report U6 1 "launch failed"; exit 1; }
sleep 0.5
uit_ime_switch
r=$(uit_context_menu N-0005 加入子主題)
if [[ "$r" != "pressed" ]]; then uit_report U6 1 "context menu press failed ($r)"; uit_quit_flush; exit 1; fi
sleep 1.5
/opt/homebrew/bin/cliclick -e 60 t:HELLO >/dev/null 2>&1; sleep 0.7
editing=$(uit_canvas_editing)
c=$(uit_commit_field HELLO)   # AXConfirm on the TextField holding HELLO
sleep 1.0
frole=$(osascript -l JavaScript focused.jxa 2>/dev/null)
uit_quit_flush
count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
hello=$(python3 treecompare.py findtext HELLO "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
echo "U6 confirm=$c typed-into='$editing' focused-role-after-commit='$frole' count=$count findtext-HELLO=$hello"
if [[ "$c" != "confirmed" ]]; then uit_report U6 1 "AXConfirm did not reach field (confirm=$c, typed-into='$editing')"; exit 1; fi
if [[ "$count" == "20" ]]; then
  uit_report U6 1 "count 20->20: AXConfirm bypassed .onSubmit — HARNESS-LIMITATION (owner 回報的 +2 bug 無法自動驗證)"; exit 1
fi
if [[ "$count" != "21" || "$hello" != "1" ]]; then
  uit_report U6 1 "count=$count (want 21; 22 = owner 回報的兄弟節點 bug) findtext-HELLO=$hello (want 1)"; exit 1
fi
if [[ "$frole" == "AXTextArea" ]]; then
  uit_report U6 1 "commit OK (count+1) but focus jumped into notes AXTextArea (owner 回報的備註焦點 bug)"; exit 1
fi
uit_report U6 0; exit 0
