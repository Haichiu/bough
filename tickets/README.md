# MindFlow Tickets

> 依據：`docs/DECISIONS.md`。依序執行，不跳階段。
> 每張 ticket 完成定義：〔可觀察結果〕欄位被直接驗證，不是「建置成功」。

---

## S0 — 回饋迴路（最優先；沒有這層，後面全部無法證實）

### T-001 一鍵重建與啟動
**問題**：每次驗證需手動 build → 關 App → 重開 → 手建測試圖。
**交付**：`scripts/dev.sh` — build → 終止舊行程 → 啟動 → 自動載入固定 fixture 圖。
**〔可觀察結果〕**：`bash scripts/dev.sh` 一行指令，15 秒內出現已載入測試圖的 App 視窗。

### T-002 fixture 地圖產生器
**交付**：`scripts/make-fixture.swift` 或 Checks target 子命令，產生 20 / 200 / 1500 節點的 `.mindmap`。
**〔可觀察結果〕**：三個檔案存在且能被 App 成功開啟。

### T-003 Accessibility 自動化 harness
**依賴**：T-001、T-002。
**交付**：`scripts/uitest/` — 以 `osascript` + System Events（必要時引入 `axcli`）驅動真 App。
**必須能自動執行的場景**：
1. 點一個節點 → 量測從送出點擊到選取環出現的毫秒數
2. 連續點五個不同節點 → 記錄每次廲遲
3. 選取後按 Return → 確認進入編輯
4. Tab → 打字 → Tab → 打字，連續建立 10 層 → 確認無掉字、焦點未跑掉
5. 小幅度拖曳（3px）→ 確認**不**觸發移動（誤操作檢測）
**〔可觀察結果〕**：一行指令輸出一張含毫秒數的報告 + 失敗步驟的截圖。
**風險**：SwiftUI 畫布節點可能在 AX tree 上不可尋址。若如此 → 降級為座標點擊 + `screencapture` 影像差異比對，並在 ticket 記錄。

### T-004 基線量測
**依賴**：T-003。
**交付**：在**修任何東西之前**跑一次，存成 `docs/baseline-2026-08-28.md`。
**〔可觀察結果〕**：有一組數字可供 S1 完成後對照。

---

## S1 — 互動模型全面重設

### T-010 歼滅所有雙擊
**位置**：`MapCanvasView.swift:128`、`:755`；`ContentView.swift:269`、`:653`。
**動作**：全數刪除 `.onTapGesture(count: 2)`；將其行為改掛到新鍵盤模型或右鍵選單。分頁列改為**單擊切換**。
**〔可觀察結果〕**：`grep -rn "count: 2" Sources/` 零結果；T-003 場景 1 的毫秒數相對 T-004 基線下降至少 150ms。

### T-011 節點點擊與拖曳分離
**問題**：`MapCanvasView.swift:285`（tap）與 `:300`（drag）同 view。
**動作**：改用單一 `DragGesture(minimumDistance: 0)` 狀態機：位移 < 4pt 且 < 250ms → 視為點擊；否則進入拖曳。不再使用 `.onTapGesture`。
**〔可觀察結果〕**：T-003 場景 5（3px 拖曳）不觸發移動；場景 1 毫秒數 < 50ms。

### T-012 鍵盤模型重寫
**動作**：依 D2 表格重寫 `KeyboardMonitor` 與 `NodeView` 編輯進出。重點：`Return` 在未編輯時進入編輯（全選）；選取後直接打字取代文字；移除 `DispatchQueue.main.async` 焦點 hop。
**〔可觀察結果〕**：T-003 場景 3、4 全過；手測連續建 30 個節點全程不碰滑鼠。

### T-013 更新 README / 說明面板
**〔可觀察結果〕**：README、⌘/ 說明、TESTING.md 中無任何「連點兩下」字樣；快鍵表與 D2 一致。

---

## S2 — 大幅精簡

### T-020 下架畫布競爭手勢
**動作**：移除框選、Shift-click 批次、Option 自由移動、⌘方向鍵微調。
**〔可觀察結果〕**：`MapCanvasView` 上手勢數量從 8 降到 3 以下（pan、zoom、node pointer）。

### T-021 下架功能模組
**動作**：依 D3 清單移除。一項一 commit，訊息寫明可從哪個 commit 取回。
**〔可觀察結果〕**：`swift run MindFlowChecks` 全過；`wc -l Sources/` 相對 7,593 行顯著下降；`scripts/verify.sh` 通過。

### T-022 文件同步
**〔可觀察結果〕**：README / ROADMAP / TESTING / FORMAT 中不再描述已下架功能；FORMAT.md 說明舊檔中的已下架欄位會被忽略而非損毀。

---

## S3 — 效能地基（條件性）

### T-030 版面移出 body + 文字量測快取
**觸發條件**：S1 完成後，T-003 在 1500 節點 fixture 上仍測到廲遲。
**動作**：`LayoutEngine.layout` 移到 ViewModel 快取，僅 document 變動時失效；文字量測以 `text+depth+hasImage` 做鍵快取。
**〔可觀察結果〕**：1500 節點下平移不再觸發 layout 重算（以 signpost 計數證明）。

### T-031 Canvas 混合渲染
**觸發條件**：T-030 仍不足。
**動作**：非互動內容改單一 `Canvas` + viewport culling；僅選取中/編輯中/拖曳中節點以真 View 疊層。

---

## S4 — 樣式系統（封存，等 S1–S3）

字型、節點形狀、線條樣式、間距、背景、節點級 override、Theme Editor。需先完成「同一張圖在 XMind 與 MindFlow 並排比對」的差距清單作為規格。

---

## 已知阻礙

- `~/.pi/agent/extensions/guard.ts:804` 與 `:782` 重複宣告 `const decision` → **所有新 pi session 無法啟動**。需 Owner 授權才能修。
