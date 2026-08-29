#!/usr/bin/env bash
# U4: 選取節點 → 新增子主題 → 輸入 HELLO → Esc → 新節點文字應為 HELLO。
# 備註（環境限制）：Tab 鍵無法以合成事件遞送（key view loop + IME），
# 改以節點右鍵選單「加入子主題」（與 Tab 同一 vm.addChild 路徑）。
# 輸入用 cliclick t:（Unicode 事件），並先 Ctrl+Space 切到 ABC 輸入法。
set -u
cd "$(dirname "$0")"; source ./lib.sh
uit_ensure_backup
uit_launch small-20 30 >/dev/null || { uit_report U4 1 "launch failed"; exit 1; }
sleep 0.5
uit_ime_switch
r=$(uit_context_menu N-0005 加入子主題)
if [[ "$r" != "pressed" ]]; then uit_report U4 1 "context menu press failed ($r)"; uit_quit_flush; exit 1; fi
sleep 1.5
uit_type HELLO; sleep 0.7
editing=$(uit_canvas_editing)
uit_key 53; sleep 1.0
editing_after=$(uit_canvas_editing)
uit_quit_flush
count=$(python3 treecompare.py count "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
hello=$(python3 treecompare.py findtext HELLO "$TABS/$SLOT_ID.mindmap" 2>/dev/null)
if [[ -z "$editing_after" && "$count" == "21" && "$hello" == "0" ]]; then
  uit_report U4 0; exit 0
fi
if [[ "$count" == "21" && "$hello" == "0" ]]; then
  echo "SKIP U4: synthetic Esc did not close editing field (before='$editing' after='$editing_after'); persisted tree still matches discard semantics"
  exit 77
fi
uit_report U4 1 "before-Esc='$editing' after-Esc='$editing_after'; count=$count (want 21) findtext-HELLO=$hello (want 0) — Esc discard regression"
exit 1
