# MindFlow Tickets

> 依據：`docs/DECISIONS.md`。依序執行，不跳階段。
> 每張 ticket 完成定義：〔可觀察結果〕欄位被直接驗證，不是「建置成功」。

---

## 協作慣例

每則跨 agent 訊息開頭必須署名，格式 `【<角色> / <pane>】`，例如
`【主 agent / wD:p1】`、`【assistant / wD:p4】`。多方同時對同一份 repo 下指令時，
收訊方必須能一眼看出這是誰的決策，否則無法判斷該不該照做。

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

## S5 — 外殼與圖標（進行中）

> **此節只留未完成的票。**完成後移除，改記入 `docs/ITERATION-LOG.md`。
> 兩份檔各有一個職務：本檔 = 待辦與協作慣例，ITERATION-LOG = 已完成記錄。
> 不要兩邊都寫 —— T-032–T-036 就是因為只進了 ITERATION-LOG，本檔停在 T-031 而漂開。

### T-041 儲存失敗的持續信號（C4a）
**問題**：`ViewModel.swift:162` 丟掉 `writeRecoveryCopy` 的 `Bool`，每 5 分鐘的復原快照可靜默失敗；autosave 失敗僅 2.4 秒 toast，之後 `saveSubtitle` 拿過期的「已自動保存 HH:mm」遮蔽現存失敗。
**交付**：`Set<StorageFailureKind>` 持續狀態；`performRecoverySnapshot()` 抽出並注入 writer（測試替身）。
**規則**：各機制只 insert／remove 自己；僅 absent→present 才 toast（episode semantics）；每次失敗都 NSLog；warning 存在時**不得顯示任何時間戳**。
**文案**：僅 autosave「⚠︎ 自動保存失敗」／僅 recovery「⚠︎ 復原快照失敗」／兩者「⚠︎ 儲存失敗（自動保存・復原快照）」。
**〔可觀察結果〕**：注入失敗後 persistent warning 出現且不隨時間消失；兩種失敗互不覆蓋；交替 fail→success→fail 行為被測試定義；把 `Bool` 再丟掉必 FAIL。

### T-042 外殼語意色（C4）
**問題**：tab active 背景、dirty dot、outline selection 直接讀 Palette A —— 畫布色滞到外殼。
**交付**：shell 改用 AppKit／SwiftUI 語意色；active tab 用原生 controlBackground + separator 邊界，**不用 accent 填滿**；dirty 改 secondaryLabel；不在 App 根全局 tint（避免系統 accent 污染畫布狀態訊號）。
**顏色職務**：中性 = 狀態陳述；controlAccent = 需強調的可操作控制；橘／紅 = **持續存在的失敗**。**不得單靠顏色編碼狀態。**
**〔可觀察結果〕**：MapCanvasView／NodeView／匯出仍讀 Palette A；shell 不再出現 Palette A 色值。

### T-043 工具列精簡（C1）
**問題**：11 類等重直達按鈕、無分組；刪除緊鄰新增（誤擊風險）。
**判準**：能收的證據是**替代入口**，不是猜頻率（本專案無 telemetry，不得假稱「常用」）。
**交付**：主列只留【子主題、兄弟｜檢閱器】；餘收進系統 `ellipsis.circle` Menu；Delete 置底、role destructive、Divider 隔開。分組只用 spacing 不用分隔線。
**〔可觀察結果〕**：能力零移除（每項仍至少一個入口）；主列按鈕數 = 3。

### T-044 分頁標題可辨識（C2）
**問題**（1）fallback 先取 root.text，預設「中心主題」遮住其他辨識來源；（2）active tab 讀 `sessions[active].document` 而編輯改的是 `vm.document`，標題在本分頁內會變舊。
**交付**：純函式 `TabDisplayTitles`。序：非預設 root → file basename → 非預設 document.title → 第一個非空後代 → 中心主題。active slot 注入 live document／filePath。
**細節**：去重編號必須在**截斷之前**；顯示用 `.truncationMode(.middle)`（分頁標題常共用前綴，尾部截斷會切掉唯一辨識字元）。

### T-045 聚焦路徑取代底部 breadcrumb（C3）
**問題**：onAppear 必選 root，底部 breadcrumb 常態重複標題；同時左上另有 focus capsule，兩份狀態。
**交付**：底部帶整條移除（空間還畫布）；左上 capsule 展開為 root→focus 可點路徑，取消聚焦收在同一組。
**理由**：聚焦是一個**模式**，模式指示器要在視線落點（左上），不是最易忽略的底部中央。一般 selection 不觸發（selection 變得太頻繁，會成噸音）。
**〔可觀察結果〕**：非 focus 時 AX 不出現路徑；focus 時路徑只反映 root→focus 不隨 selection 噪動；點祖先改 `focusBranchID`。

### T-046 CanvasTransform 去重（toMap）
**問題**：`MapCanvasView` 的 `toMap` 定義兩次（:213、:398）。公式相同但呼叫座標原點不同。
**交付**：純 `CanvasTransform(screen↔map)`；visible rect 與 lasso 共用；Checks 做 round-trip。
**邊界**：**不順便改 pan／scale** —— 無缺陷證據不動。

### T-047 App icon 字形重設計
**問題**：現行單向右輐射 + 等大圓點，讀起來是通用的「分享／分支」符號。owner 明確要求重設計。

**設計不變式（參數由實作對門檻搜尋，不得手挑）**：
1. **雙軸鏡像對稱**（左右、上下），中心節點置畫布中心。
   → **重心由構造保證居中，t 掃描機制不再需要**。重心斷言保留為守衛，應以大餘裕通過。
2. 中心是單一較大質量，採**產品自身的根節點形態**（圓角矩形，寬 > 高）。
3. 每側 N 片葉：large N=3（中央那片落水平軸）、mid N=2（上下各一，不落軸）、small N=1（落軸）。
4. 連接線用與產品連接線同族的曲線，不是直線。
5. 墨色全部奶油 `F2EFE7`；底板漸層不變。**葉片不得用分支色** —— 實測對漸層底僅 1.15–1.65。

**驗收**（汿檻不降，只改寫結構斷言）：
- 結構可分離：每側各一條垂直掃描，恰得 N 段
- 中心可分離：一條**不落水平軸**的水平掃描，得 5 段（葉・線・中心・線・葉）
  ※ 若實作幾何使某掃描退化，可改用等價斷言，**但必須說明為何等價，且附退化情形的 mutation control**
- 最弱峰值 ≥ 680；每片葉對當地背景對比 ≥ 3.0
- 墨色重心兩軸皆在 max(1% 底板寬, 1 裝置像素) 內
- **參數必須是內點**：任一自由參數 ±1 design unit 仍可行
- **陰性對照**：移除左側葉片（退回單向）必須 FAIL 結構斷言

**回報須帶餘裕不只帶 PASS。**

---

## 已知阻礙

- `~/.pi/agent/extensions/guard.ts:804` 與 `:782` 重複宣告 `const decision` → **所有新 pi session 無法啟動**。需 Owner 授權才能修。
