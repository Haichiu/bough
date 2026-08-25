#!/bin/bash
# UI 覆蓋率檢查：ViewModel 的公開方法必須能從介面層觸達。
# 「測試全綠 ≠ 使用者摸得到」——v20.1 曾發現色標/網址功能完全沒有 UI 入口。
# 例外名單：僅供 ViewModel 內部串接、不需直接綁 UI 的方法。

set -euo pipefail
SRC="$(dirname "$0")/../Sources/MindFlowKit"
APP="$(dirname "$0")/../Sources/MindFlow"
VM="$SRC/ViewModel.swift"

UI_FILES=(
  "$SRC/ContentView.swift"
  "$SRC/MapCanvasView.swift"
  "$SRC/NodeView.swift"
  "$SRC/KeyboardMonitor.swift"
  "$APP/MindFlowApp.swift"
)

ALLOWED=(
  addSummary           # 經由 addSummaryWithNextSibling（右鍵選單）間接觸達
  newDocument          # 測試夾具；App 流程走範本選擇器
  openInNewTab         # 內部串接：開檔/範本/URL 都經它
  expandTo            # performSearch 內部跳轉用
  insertChildUnder    # paste/drop 內部組樹用
  commitNodeText      # NodeView 編輯提交
  autosaveAllSessions # 由 App 生命週期與 debounce 呼叫
  startSnapshotTimer  # App 啟動時排程
  openFromURL         # onOpenURL 場景
  focusSet            # 大綱/畫布共用查詢
  breadcrumbPath      # 麵包屑列查詢
  notify              # 各層共用提示
)

is_allowed() {
  local fn="$1"
  for a in "${ALLOWED[@]}"; do [[ "$a" == "$fn" ]] && return 0; done
  return 1
}

orphan_count=0
while read -r fn; do
  [[ -z "$fn" ]] && continue
  found=0
  for f in "${UI_FILES[@]}"; do
    if grep -q "vm\.$fn(\|\.vm\.$fn(" "$f" 2>/dev/null; then found=1; break; fi
  done
  if [[ $found -eq 0 ]]; then
    if is_allowed "$fn"; then
      echo "SKIP (internal): $fn"
    else
      echo "ORPHAN: $fn 沒有任何 UI 入口"
      orphan_count=$((orphan_count+1))
    fi
  fi
done < <(grep -oE "public func [a-zA-Z]+" "$VM" | awk '{print $3}' | sort -u)

if [[ $orphan_count -gt 0 ]]; then
  echo "✗ 發現 $orphan_count 個孤兒 API——使用者無法觸達的功能！"
  echo "  若為內部串接請加入腳本頂端的 ALLOWED 名單並註明原因。"
  exit 1
fi
echo "✓ UI 覆蓋率檢查通過：所有公開方法皆可觸達"