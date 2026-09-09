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

**結案記錄（2026-09-09，p1 補記）**：實作早已完成，但**兩份檔案都沒記**，所以清單上看起來還沒做。實測依據：`ViewModel.swift` 有 `StorageFailureKind`、注入式 `recoveryWriter`（測試替身接縫）、`storageFailures: Set`、四段文案 switch、`performRecoverySnapshot()` 回傳 Bool 並在 false 時 `recordStorageFailure(.recovery,…)`；`MindFlowChecks.swift:5229` 起有對應守衛，斷言 writer 被呼叫次數、`storageFailures == Set([.recovery])`、`storageWarningText == "⚠︎ 復原快照失敗"`、以及重複失敗仍持續。

### T-042 外殼語意色（C4）
**問題**：tab active 背景、dirty dot、outline selection 直接讀 Palette A —— 畫布色滞到外殼。
**交付**：shell 改用 AppKit／SwiftUI 語意色；active tab 用原生 controlBackground + separator 邊界，**不用 accent 填滿**；dirty 改 secondaryLabel；不在 App 根全局 tint（避免系統 accent 污染畫布狀態訊號）。
**顏色職務**：中性 = 狀態陳述；controlAccent = 需強調的可操作控制；橘／紅 = **持續存在的失敗**。**不得單靠顏色編碼狀態。**
**〔可觀察結果〕**：MapCanvasView／NodeView／匯出仍讀 Palette A；shell 不再出現 Palette A 色值。

**結案記錄（2026-09-09，p1 補記）**：已完成且守衛強度高於一般票。`MindFlowChecks.swift:5379` 以**掃描原始碼**的方式斷言 `ContentView.swift` 只保留**恰好一個** `Palette` 參照（大綱星號的內容色 `Palette.screen.statusHighlight`），並斷言不存在小寫 `palette.` 的外殼色參照。因此外殼語意色是被機械守住的，不是靠人自律。

### T-043 工具列精簡（C1）
**問題**：11 類等重直達按鈕、無分組；刪除緊鄰新增（誤擊風險）。
**判準**：能收的證據是**替代入口**，不是猜頻率（本專案無 telemetry，不得假稱「常用」）。
**交付**：主列只留【子主題、兄弟｜檢閱器】；餘收進系統 `ellipsis.circle` Menu；Delete 置底、role destructive、Divider 隔開。分組只用 spacing 不用分隔線。
**〔可觀察結果〕**：能力零移除（每項仍至少一個入口）；主列按鈕數 = 3。

**結案記錄（2026-09-09，驗收條件經 Owner 裁示改寫）**：原規格「精簡到 3 顆」**其實早在 `30cca8f`（2026-09-02）就已交付**，而 Owner 正是看著那個已精簡的版本說「很醜很沒必要」——**照原文做完也不會解決他的問題**。p1 據此回報並提供選項，Owner 選擇**整條拿掉**。

實作：先給四項「只住在工具列」的能力新家，再拆工具列。其中**檢閱器開關在全產品範圍內沒有第二個入口**，直接移除會讓檢閱器永遠打不開。新增於 `CommandMenu("顯示")`：符合視窗（⌘0）、檢閱器（⌥⌘I）、展開至 1–4 層、取消聚焦、全部展開、全部收合。ContentView 的 `.toolbar` 區塊（83 行）移除並留下說明註解。

驗收改寫但**保留並收緊**能力清單：入口只承認 App 選單與畫布右鍵選單這類**使用者點得到**的地方，不再接受 ContentView／KeyboardMonitor 的內部管線字串（舊版正是這個寬鬆處讓「檢閱器」這種風險看不出來）。**`verify.sh` 抓到我新 oracle 漏掉的東西**：`expandAll`／`collapseAll` 成為孤兒 API，因為我誤把選單裡的「全部收合／展開」*切換*當成那兩個獨立命令的入口；已補上真正的入口並把 oracle 對應條目改成不接受切換。

閘門：`MindFlowChecks` ALL CHECKS PASSED、`verify.sh` ALL GREEN。**Runtime 實測**：打包後 AX 掃描真實視窗，子主題／兄弟主題／檢閱器／更多／ellipsis 全部零命中。

### T-044 分頁標題可辨識（C2）
**問題**（1）fallback 先取 root.text，預設「中心主題」遮住其他辨識來源；（2）active tab 讀 `sessions[active].document` 而編輯改的是 `vm.document`，標題在本分頁內會變舊。
**交付**：純函式 `TabDisplayTitles`。序：非預設 root → file basename → 非預設 document.title → 第一個非空後代 → 中心主題。active slot 注入 live document／filePath。
**細節**：去重編號必須在**截斷之前**；顯示用 `.truncationMode(.middle)`（分頁標題常共用前綴，尾部截斷會切掉唯一辨識字元）。

**結案記錄（2026-09-09，p1 補記）**：已完成。`Sources/MindFlowKit/TabDisplayTitles.swift` 提供 `public enum TabDisplayTitles`，`ContentView.swift:387` 呼叫 `TabDisplayTitles.resolve(…, maximumGraphemes:)`，`MindFlowChecks.swift:6182` 起有 12 處守衛。**本票是「清單說謊」的代價實例**：p1 在 2026-09-09 依清單把它派給 p6 實作，p6 開工後才被叫停。教訓已寫進協作慣例：**拿到票的第一件事是先去程式碼確認它真的還沒做。**

### T-045 聚焦路徑取代底部 breadcrumb（C3）
**問題**：onAppear 必選 root，底部 breadcrumb 常態重複標題；同時左上另有 focus capsule，兩份狀態。
**交付**：底部帶整條移除（空間還畫布）；左上 capsule 展開為 root→focus 可點路徑，取消聚焦收在同一組。
**理由**：聚焦是一個**模式**，模式指示器要在視線落點（左上），不是最易忽略的底部中央。一般 selection 不觸發（selection 變得太頻繁，會成噸音）。
**〔可觀察結果〕**：非 focus 時 AX 不出現路徑；focus 時路徑只反映 root→focus 不隨 selection 噪動；點祖先改 `focusBranchID`。

**結案記錄（2026-09-05）**：p6 `6d13535` 實作，p1 修正後 `u10-focus-path.sh` PASS=7 FAIL=0。過程中發現**驗收條件本身把產品扭曲了**：原條件要求「一個 AXStaticText 拼出 root→focus」，而 Button 在此 target 不暴露 title，唯一能滿足的方式就是把路徑再畫一次；實作照做，膠囊遂同一行並排顯示兩份路徑（p1 以 AX 幾何實測：StaticText@x=284 與四個 Button@x=482–638）。修法：移除重複整串 `Text`（只留模式標籤「聚焦：」），改在每個段落按鈕掛 `.accessibilityIdentifier("focuspath-<text>")`，oracle 改讀 `AXIdentifier` 並新增「任何 StaticText 再拼出整條路徑即 FAIL」。**教訓：只能靠新增可見元素才能滿足的驗收條件，會把產品扭曲成量具的形狀。**

### T-046 CanvasTransform 去重（toMap）
**問題**：`MapCanvasView` 的 `toMap` 定義兩次（:213、:398）。公式相同但呼叫座標原點不同。
**交付**：純 `CanvasTransform(screen↔map)`；visible rect 與 lasso 共用；Checks 做 round-trip。
**邊界**：**不順便改 pan／scale** —— 無缺陷證據不動。

**結案記錄（2026-09-09）**：p7 於 `bake/p7` `e7144f3` 實作，p1 獨立重跑通過（980 筆 legacy 等價 + 2000 筆隨機往返，0 失敗；diff −22/+8；死碼 `visibleItems` 未動）。本日 cherry-pick 進 main，`MindFlowChecks.swift` 檔尾衝突為「雙方各自追加」形狀，保留雙方後閘門全綠。commit `89124ea`。

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

### T-049 新增節點後停在節點層，不自動進編輯（owner 回報）

**owner 原話**：「應該要預設先是針對節點的行動，而不是新增節點後就跳到編輯文字，這跟 xmind 邏輯不一樣。」

**現況（已實讀確認）**：四個建立路徑各自設 `editingID = newNode.id` —— `ViewModel.swift:360`（addChild）、`:382`（addSibling）、`:401`（addSiblingBefore）、`:1464`（插入父主題）。

**能力不會遺失（已驗）**：「打字即編輯」已存在於 `KeyboardMonitor.swift:280`（D2），守衛為「有 selection、無修飾鍵、單一可印字元」—— 建立路徑本來就會設 `selection`，所以拿掉自動編輯後，**打字仍然直接進編輯並取代內容**。四條 `notify` 的「直接輸入文字」仍然屬實。

**但有一個隱藏耦合，不可只刪四行**：
新節點是 `MindNode(text: "")`，`ViewModel.swift:352` 註解寫明「empty commit discards the node」—— **空節點的清除機制掛在編輯階段上**。拿掉自動編輯，就沒有編輯階段可以“空白提交”，連按 Tab 會留下一串永久的空節點。

**交付**：
1. 四個建立路徑不再設 `editingID`（保留 `selection`、`flash`、`notify`）
2. **同時**決定空節點命運。建議：新節點給預設文字（如「子主題」）而非空字串 —— 符合 XMind、節點可見可選，且打字即編輯會整段取代它。若改選別的方案，必須講明空節點何時消失

**〔可觀察結果〕**：
- Tab／Enter 建立後：`editingID == nil`、`selection == 新節點`
- 此時方向鍵導航節點（不是移動文字插入點）；Delete 刪節點
- 打一個可印字元 → 進編輯且內容**被取代**（不是附加在預設文字後面）
- 連按 Tab 五次不打字：五個節點都**可見、可選、可刪**，沒有隱形節點
- **陰性對照**：把 `editingID = newNode.id` 加回任一路徑，第一條必須 FAIL

**邊界**：不順便改鍵位配置、不動第二次點擊進編輯（`MapCanvasView:467`）、不動 D2 本身。

**結案記錄（2026-09-03）**：全款驗收完成。headless 部分 `68bd471`（四路徑 node-level＋預設文字「子主題」＋type-to-replace＋Tab×5＋陰性對照）；其下游 D2 吞字缺陷由 p1 GUI 量測發現、`6d74a8a`（editText live-store seed）修復並雙情境 GUI PASS。方向鍵導航由 p1 以「導航後打字、以被取代的節點反推選取」實測 PASS（Right 進第一子節點、Down 走下一兄弟，皆節點層移動）。

---

### T-050 分頁按鈕無障礙標籤（T-044 follow-up）

**背景（p1 GUI 探針，HEAD `7056f10`）**：隔離 storage、五分頁；五個分頁按鈕 `title = missing value`、`description = "button"`、`value = missing value` —— 完全無可讀標籤。同一次 dump 中工具列按鈕有標籤（「子主題」「兄弟主題」、`More`），只有分頁列沒設。功能間接證據：按鈕寬 68/85/86/209/226 —— 三個同根分頁去重後綴有避開佔用、兩個僅中段相異的 25 字長標題差約 ` · 2` 寬度；即 final-string allocator 在真實 GUI 正確運作，缺的是 AX 通道。

**裁定（p1）**：分頁按鈕加無障礙標籤，值 = resolver 計算出的最終 label。理由：可辨識是票目的本身（讀螢幕使用者完全分不出分頁）；工具列已這樣做，屬一致性補齊，非新機制。

**交付**：
1. 切換與關閉按鈕的 AX 標籤逐字等於 `tabDisplayTitles[index]`（同一 computed var 來源；不得另行計算或 hardcode）。
2. 找出現行 `.accessibilityLabel` 為何在 macOS AX 未浮現（`description="button"` 而非我們的字串），以最小修補讓它浮現；機制寫進 commit message —— 本案的失敗模式正是「看起來有實則無」。
3. 陰性對照由 p1 GUI 探針執行：拿掉標籤必須回到 missing value。

**驗收**：
- p1 重跑同一支探針：五分頁 AX value 逐字 == final labels（含去重後綴與截斷省略號）。
- headless gates 全綠；source check：accessibilityLabel/Value 引用 `tabDisplayTitles`。

**邊界**：不動 `TabDisplayTitles` 模組；不動工具列既有標籤；GUI 探針屬 p1 車道。

**結案記錄（2026-09-03，p1 裁決）**：原目標（真正的無障礙名稱）**降級進 backlog，不排程**——owner 不用 VoiceOver。實測依據：四顆對照組（純 Button／.accessibilityLabel／容器外同名／identifier）證明 `.accessibilityLabel` 在本 target 的普通內容區**不產生** AXTitle／AXDescription（屬性本身不存在，非空值）；工具列能浮現是因 `.toolbar{}` 走 NSToolbarItem 的 AppKit 取名路徑。已落地的是 `.accessibilityIdentifier`（**僅驗收管道，不是無障礙修復**——分頁對 VoiceOver 依然無名）。

---

### T-052 Shift+Tab 目前完全沒有繫結（已完成 `9e25e56`，p1 以 u12 獨立驗證）

**Owner 原話**：「新增節點時預設不會直接進入編輯模式，你可以繼續按 Enter、Tab 或是 Shift + Tab 針對節點做出調整，只有當使用者按空白鍵（Space）的時候才會開始編輯。」

**已實測結清的部分（不要重做）**：節點層預設（T-049）與 Space 進編輯且保留原文，已由 `scripts/uitest/u9-space-shifttab.sh` 實跑證實（見 ITERATION-LOG row 20）。

**實測到的真缺口**：Shift+Tab 完全未繫結，樹不會改變。機制：`charactersIgnoringModifiers` **會套用 Shift**，Shift+Tab 因此得到 `\u{19}`（0x19），既落不進 `case "\t"`，也過不了 `d2Replacement` 的 `scalar.value >= 0x20` 守衛，最後 `return event` 交給系統。

**決定：綁 promote / outdent。** 這不是口味問題，是專案既有預設（XMind parity）直接推導出來的。

**p1 的更正**：本票初版寫「XMind 本身並未綁 Shift+Tab」，**該敘述是錯的，且當時未經查證就寫成事實**。XMind 官方使用指南明載：

> "Shortcuts: Press Enter to add new topics, press Tab to indent, **press Shift + Tab to outdent**."
> — <https://xmind.com/user-guide/outliner-new>

因此 Shift+Tab = outdent（升一層）是 XMind 的既定語意，本專案照抄即可，不需 Owner 裁決。
（誠實標註範圍：該段出自 XMind 的 **Outliner 檢視**說明；畫布檢視的快捷鍵表未列 Shift+Tab。但 Tab=Insert Subtopic 在兩邊一致，且我們的 Tab 已經是降一層，故 outdent 是對稱且有據的綁法。）

**實作方向**：升一層＝變成原父節點的兄弟。**重用現有 `move(id:toParent:)`（ViewModel:495，已含 not-root / not-descendant / 同父短路守衛）**，不需新寫樹操作。

**若選 A，預定驗收（實跑探針，不得以 gate/source 結案）**：
- 延伸 `u9-space-shifttab.sh`：選一個**孫節點**按 Shift+Tab → 它的父變成原祖父（以 `treecompare.py parentof` 斷言），且**節點總數不變**（是搬動，不是新增）。
- **邊界**：root 的直接子節點再 promote 應為 **no-op**（root 沒有父節點）—— 必須有對應探針，且樹完全不動。
- **陽性對照**不可省：同一支探針必須同時證明 Tab 仍能建節點，否則「樹沒變」無法與探針壞掉區分。
- 若 promote 後節點被 `move` 附到祖父 children 末端而非原父之後，需判定這個位置是否可接受（p1 視覺裁決）。

---


### T-055 螢幕解鎖後補做的 GUI 驗證（已結案）

本輪有兩項行為只做了**模型層**驗證，因為實測發現 `CGSSessionScreenIsLocked = Yes`（螢幕鎖定），此時**任何需要視窗的探針都會 timeout**。
已用對照組（HEAD 原始碼另建一份）確認這是環境限制，**不是程式回歸**。

解鎖後需要實跑確認：

1. **主題切換時畫布是否立即重繪**。静態證據支持會（畫布未將 palette/style 快取在 body 之外，且 `MapCanvasView` 以 `@EnvironmentObject` 觀察 vm），但**這不等於 runtime 證明**。
   可用像素取樣做 oracle：經典畫布 `#f2efe7` → 極簡 `#ffffff`（ImageMagick 可用）。若不重繪，修法**不是**無條件加 `.id(vm.themeID)`——那會重置縮放與平移。
2. **選擇是否跨重啟保留**（UserDefaults `themeID`）。
**探針已寫好待跑**：`scripts/uitest/u19-theme-repaint.sh`（第 32 輪寫，**尚未執行過**，因為寫的當下螢幕鎖定）。它以「視窗區域的眾數顏色」當畫布底色，對節點位置免疫，並以「取樣器必須先讀到經典的 `#f2efe7`」作為陽性對照；讀不到就報 `INSTRUMENT:` 而非 `FAIL`。

3. **`⌘/` 現在只做一件事**。修正前實測到它**同時**收合分支（21→18 節點）**且**開啟說明面板；修正後應只收合。並驗 `⌘?` 開說明、`⌥⌘/` 全部收合／展開。

**結案記錄（2026-09-09）**

螢幕於 21:03 解鎖，`u19-theme-repaint.sh` 實跑 **PASS=4 FAIL=0**：

| 斷言 | 實測 | 結果 |
|---|---|---|
| 取樣器讀得到經典畫布（陽性對照） | `#121819`，期望 `#101819` | PASS |
| 切換主題會重繪畫布 | `#0c0c0d`，精確命中 | PASS |
| 主題選擇跨重啟保留 | 重啟後仍 `#0c0c0d` | PASS |
| `⌘/` 只收合分支、不開說明 | 節點 21→18、說明面板 0 | PASS |

三件事跟原本寫的不同，記錄下來：

1. **期望值原本寫錯。** 票上寫經典 `#f2efe7` → 極簡 `#ffffff`，那是**淺色**外觀的值。系統實際在深色模式，正確值是 `#101819` → `#0c0c0d`。探針已改為讀 `AppleInterfaceStyle` 自行選期望值，兩種外觀都能跑。
2. **不能用字串相等比對。** `screencapture` 會做色彩描述檔轉換，各通道位移約 2（`#101819` 讀成 `#121819`）。改為逐通道容差 6 的 `near()`。
3. **陽性對照曾不穩，原因是取樣時視窗不在前景。** 整螢幕截圖再依視窗座標裁切，若當下別的 App 蓋在上面，量到的是那個 App（曾讀到 Ghostty 的 `#282c34`）。修法：`canvas_hex` 每次取樣前重新 activate 並**驗證** frontmost 確實是 MindFlow，失敗回傳 `NOTFRONT` 由呼叫端報 `INSTRUMENT:`，不會被誤判成產品失敗。


## 已知阻礙

- ~~guard.ts 重複宣告 `const decision` 使新 pi session 無法啟動~~ —— **2026-09-03 判定過期**：p1 於當日由 owner 重開，是一個全新且成功啟動的 pi session。runtime 證據優於 source grep（`grep -c "const decision"` 仍回 2，但那兩處不在同一 scope，對「能不能啟動」零資訊）。
