# XMind 差距清單（S4 樣式系統的前置規格）

`tickets/README.md:95` 把 S4 樣式系統封存，並指定開工條件：
**「需先完成『同一張圖在 XMind 與 MindFlow 並排比對』的差距清單作為規格。」**
本檔是該清單。

## 這份清單證到什麼程度

| 部分 | 方法 | 可信度 |
|---|---|---|
| MindFlow 現況 | 直接讀原始碼與既有守衛 | 高，可重查 |
| XMind 能力 | XMind 官方 user guide | 高，附連結 |
| **視覺並排比對** | **未完成** | **缺** —— 見末節 |

> p1 的影像判讀不可靠，因此**沒有**做真正的「同一張圖並排」。本檔交付的是**結構性**差距；
> 票上要求的視覺比對仍未完成，需要 Owner 的眼睛或一組截圖。**不要把本檔當成 S4 規格已齊備。**

## 一、功能面：已追平，不是差距所在

2026-09-09 逐項實測，六次假設全部落空——每一項「我以為缺的」都已存在：

| 假設缺口 | 實際狀態 | 證據 |
|---|---|---|
| Undo / Redo | 已有 | `ViewModel.swift` `undoStack`、上限 100、分頁各自獨立、有合併；⌘Z 已繫結 |
| 搜尋 / 取代 | 已有 | `ContentView.swift` 搜尋列、`closeSearch()` 單一離開路徑 |
| 插入父主題 | 已有 | `insertParent(id:)` + 快捷鍵 + 右鍵選單 |
| 兄弟節點重排 | 已有 | `moveSibling(id:offset:)`、`moveSibling(id:toIndex:)` |
| 關聯線 / 概要 | 已有 | `MindLink`、`MindSummary` |
| 多種結構 | 已有 | `logicRight` / `balanced` / `bracket` / `fishbone` |

另已具備：標記徽章、匯出匯入、聚焦模式、分頁、簡報模式、禪模式、自動儲存與復原快照（含持續失敗信號 T-041）。

**功能面真正還缺的只有一項**：
- **Boundary（外框）** —— XMind 用來圈選跨層級的一群節點。我們的 `MindSummary` 明確受限於「同一父節點下**連續**的兄弟」（見 `Model.swift` 註解），表達不了這個語意。
  值得注意：`Theme.swift` 已有 `.boundary` 這個**顏色角色**（:102/:217/:304），亦即主題系統預留了槽位，但模型層與 UI 完全沒有對應物。

> **原本這裡還列了「Outline 大綱檢視」，那是錯的。**實測：`OutlineFlattener.swift` 產生帶 depth／marked／note／hasChildren 的 `OutlineRow`，
> `ContentView.swift:547` 在用，Inspector 有「大綱」分頁（:401），另有大綱編號（`showOutlineNumbers`）與 `⇧⌘M` 圖／大綱切換。
> 這是本次盤點中**第七個**「我以為缺、其實早就有」的項目——寫在這裡當作對讀者的警告：
> **本專案的實作領先它的文件，任何「我們缺 X」的說法都必須先 grep 過再說。**

## 二、樣式面：差距在這裡，而且是結構性的

XMind 的核心賣點是**逐 topic 的 Format Panel**（Shape、Fill、Colors & Borders、Text 字型/大小/粗細/對齊、分支線粗細與 tapering、Quick Style）。
來源：<https://xmind.com/user-guide/format-and-style>、<https://xmind.com/user-guide/topic-editing-new>、<https://xmind.com/user-guide/text-new>

我們的 `NodeStyle` 欄位**全部是 `let`，且由節點深度推導**（三層形態）。因此差距不是「某幾個選項沒做」，而是：

> **MindFlow 目前沒有任何「使用者可調的樣式」概念。樣式是設計時決定的常數，不是文件資料。**

| 維度 | MindFlow | XMind | 差距性質 |
|---|---|---|---|
| 字型（家族／大小／粗細／對齊） | `NodeStyle.font`，依深度固定 | 逐 topic 可調 | 無使用者控制 |
| 節點形狀 | 只有圓角矩形（`cornerRadius`） | 多種形狀 + flowchart 形狀 | 只有一種 |
| 填色／邊框 | `fillBase/Opacity`、`strokeBase/Opacity/Width`，依深度 | 逐 topic 可調 | 無使用者控制 |
| 分支線樣式 | `ConnectionGeometry` 依結構決定 | 粗細、Colored Branch、tapering | 無使用者控制 |
| 間距 | `horizontalInset` / `verticalInset` 常數 | 可調 | 無使用者控制 |
| 畫布背景 | 依 light/dark 外觀 | 桌布／背景圖 | 無 |
| **節點級 override** | **完全沒有** | 每個 topic 獨立 | **架構缺口** |
| Theme Editor / 樣式庫 | 無 | 有 | 完全缺 |

### 這對 S4 的範圍意味著什麼

節點級 override 不是一個「功能」，而是**資料模型的改動**：
`MindNode` 需要能攜帶一份可選的樣式覆寫，`NodeStyle` 需要從「由深度推導的常數」變成「深度預設 ⊕ 節點覆寫」的合成結果，
而**匯出、匯入、undo、round-trip 全都要跟著保守**。這是 S4 真正的成本所在，不是 UI 面板。

建議 S4 的第一刀切在這裡，而不是先做 Theme Editor：
**先讓一個節點能覆寫一個屬性並存活於存檔往返**，其餘維度才有地方掛。

## 三、還缺的那一半（需要 Owner）

票上要的是「同一張圖並排比對」。要完成它需要：
1. 同一份內容在 XMind 與 MindFlow 各畫一次
2. 兩張截圖
3. 判斷「看起來差在哪」——這是**視覺判斷，不是結構判斷**，p1 做不可靠

在補上這一半之前，本檔只能支撐「S4 該從資料模型切入」這個結論，
**不足以支撐任何關於視覺品味的決定**（例如該不該改預設配色、圓角、字級）。
