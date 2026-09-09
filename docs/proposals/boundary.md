# Boundary（外框）設計提案

> **狀態**：提案，未實作、未定案。**作者**：Walker / wD:p6。**日期**：2026-09-09。
> **依據**：本檔所有「現況」都是當日實測（HEAD `6c0b1b6`）＋ XMind 本體字串（`/Applications/Xmind.app/Contents/Resources/app.asar`）。行號會隨 commit 位移，引用時請以內容為準。
> **範圍**：只回答資料模型／行為／持久化／第一刀四題。**不含工單**，不動 `tickets/`、`docs/ITERATION-LOG.md`、`FORMAT.md`。
> **不確定**一律標示「不確定」並寫出「要先量什麼」。

---

## 0. 三個前提校正（先講，因為它們改變答案）

### 0.1 `Theme.swift` 的 `.boundary` **不是顏色角色**（原敘述有誤）

`docs/XMIND-GAP.md:35` 寫「`Theme.swift` 已有 `.boundary` 這個**顏色角色**（:102/:217/:304），亦即主題系統預留了槽位」。實測 `Theme.swift:100-103`：

```swift
private enum GamutMapping {
    case step
    case boundary
}
```

`.boundary` 是**色域映射策略**（OKLCH chroma 邊界二分搜尋的兩個模式之一），`:217`/`:304` 是它的使用點，與外框功能無關。**主題系統沒有預留外框色槽。**
→ 建議：p1 把 `docs/XMIND-GAP.md:35` 那句改成「主題層沒有任何外框對應物（連色槽也沒有）」，否則未來會有人拿這個錯誤前提去「接上既有的槽位」。

### 0.2 XMind 的 Boundary **不是「任意跨層級成員」**（語意要收窄）

XMind 自己程式碼裡的 boundary 模型（asar 字串實測，逐字）：

```
rangeType:i.rangeType??"children",rangeStart:i.rangeStart??0,rangeEnd:i.rangeEnd??0,title:i.title??""
o.range="parent"===e.rangeType?"master":`(${e.rangeStart},${e.rangeEnd})`
visibleMasterBoundaries
y(d(t),"boundaries",[])          // 每個 topic 帶一個 boundary id 陣列
```

只有兩種外框：

| 型別 | `rangeType` | 涵蓋範圍 | XMind 內部名 |
|---|---|---|---|
| 範圍外框 | `"children"` | `parentTopicId` 底下第 `rangeStart…rangeEnd` 個**連續兄弟**（可以只含 1 個） | normal boundary |
| 主外框 | `"parent"` | `parentTopicId` **本身 ＋ 它的可見子孫**（整條分支） | **master boundary** |

也就是說：
- XMind 講的「跨層級」= **主外框包住一個主題與其子孫**，不是任選任意節點。它**沒有**「不連續／跨父節點成員集合」這種東西。
- 範圍外框的**涵蓋語意與我們現有的 `MindSummary` 完全相同**（同父、連續兄弟，`Model.swift:153-167`），差別只在「封閉外框」vs「括線＋標籤」。
- 外框可選標題（`title` / `"boundarytitle"` / `boundaryAddingTitleButton`），但**可選**。

**結論：真正缺的只有一項 —— 主外框（子樹外框）。** 這直接把第 1 題的答案從「id 集合 vs 子樹」變成「XMind 只有子樹這一種，所以先做子樹」。

### 0.3 順手發現的既有缺陷：boundary 不能重蹈 summary 的覆轍

`MindSummary` 只在**刪除路徑**清理：`ViewModel.swift:456`（`delete`）、`:1310`（`deleteBatch`）呼叫 `pruneSummaries`（實作 `:1446`）。但 `move(id:toParent:)`（`:495`）、`promote`（`:517`）、`moveSibling`（`:702` / `:939`）**都不清理**。
後果：把概要端點搬離父節點後，summary 仍留在 `document.summaries`，`SummaryGeometry.bracket` 找不到端點 → 回傳 nil → **括線靜默消失**，資料仍佔位，只有 undo 看得到。這是「範圍語意」的典型腐化。
→ **boundary 的生命週期必須對每一種結構變更都有定義，而且要靠單一收斂點維護，不靠每個呼叫點記得。**

---

## 1. 資料模型

### D1 — 存「錨點」`rootID`，不存成員 id 集合（核心決定）

```swift
public struct MindBoundary: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    /// 被框住的分支根。涵蓋範圍每次渲染由樹即時推導：root 本身 + 所有可見子孫。
    public var rootID: UUID
}
```

| | 成員 id 集合 | **錨點 rootID（採用）** |
|---|---|---|
| 表達力 | 任意不連續、跨父節點 | 只表達「某節點的子樹」 |
| 與樹一致性 | 每次 mutation 都要同步；刪除／搬移／重排都可能留下孤兒 id（見 §0.3） | **不可能不一致**：範圍是推導出來的 |
| 刪到成員 | 要逐個移除，剩 <2 個怎麼算？語意要發明 | 子孫被刪 → 範圍自動縮小 |
| 搬移成員 | 成員離開視覺群組後框會橫跨全圖，或要發明「離開就退出」規則 | 搬 root → 框跟著走；搬子孫出去 → 它自然不在框內 |
| 收合 | 被隱藏的成員要不要算？要發明規則 | 只算可見節點，天然一致 |
| 與 XMind 對齊 | **XMind 沒有這個東西**（§0.2） | 就是 XMind 的 master boundary |
| 代價 | 實作與測試面積大得多 | 表達不了「不連續成員」——但沒人表達得了，因為 XMind 也沒有 |

理由：**能用推導的就不要存。** 成員集合把「樹的狀態」複製了一份，複製品就有腐化可能；錨點讓邊界條件全部變成「渲染時算一次」。
**若 Owner 真的要「圈住不連續的幾個節點」**（XMind 做不到、我們也不該假設他要），代價是 §2 的表格要重寫成「每個 mutation 的成員同步規則」，並且要新增 prune；這是另一張票，不是 v1。

### D2 — v1 **不存** `rangeType`

v1 只有子樹一種型別，存一個永遠是 `"subtree"` 的欄位是死彈性（本專案明訂不為不存在的使用情境加欄位）。日後要做 XMind 的範圍外框時，用容錯解碼新增：

```swift
// 只作為未來擴充示意，v1 不要寫進程式碼
public var rangeType: String = "subtree"   // "subtree" | "children"
public var startID: UUID?
public var endID: UUID?
```

舊檔沒有這些欄位 → 預設 `"subtree"`，自動相容；這就是本專案的相容機制（`docs/FORMAT.md`「容錯解碼規則」），**不需要格式版本號**。

### D3 — v1 **不存** `text` / 標題

XMind 的標題是可選附加物，但我們**沒有「外框標題編輯器」這個使用情境**。先加欄位卻沒有入口＝死欄位。要標註群組目前 `MindSummary` 已經能做。
**若 Owner 要求外框可命名**：欄位與 Inspector 輸入框**同一個 commit 一起上**，不先佔位。

### D4 — 一個 root 最多一個外框

v1 沒有樣式可選，兩個同範圍外框在視覺上完全重疊、無法區分也無法各自選取。`addBoundary(rootID:)` 對已存在的 root 回傳既有 id（不新增第二筆）。XMind 允許同一主題多個外框，因為它有 shape/fill 可區分；我們沒有，先不做。

### D5 — 允許巢狀／重疊

父與子各有外框是合法的（XMind 也是）。渲染按 depth 由外而內排序，填色透明度低到巢狀時不會明顯疊深。**不需要不變式**。

### D6 — 存放位置

`MindDocument` 新增 `public var boundaries: [MindBoundary]`（與 `summaries` 同層，`Model.swift:188`），`decodeIfPresent ?? []`。

---

## 2. 行為（被圈住的節點被刪除／搬移／收合時）

**唯一不變式**：`boundary.rootID` 必須存在於文件中；**涵蓋範圍 = root 本身 + 所有可見子孫**。下表每一列都是這條的推論，沒有額外狀態。

| 結構變更 | boundary 的行為 | 理由 |
|---|---|---|
| 刪除 root（或 root 的祖先） | **移除**這筆 boundary | 錨點不存在，框無意義；undo 可回復 |
| 刪除 root 的子孫 | 保留，範圍自動縮小 | 框屬於 root，不屬於被刪的子孫 |
| 批次刪除 | 同上；若整棵含 root 被刪則移除 | 與單刪一致 |
| `move` 搬走 root | **跟隨**（rootID 不變） | 錨點搬家，框跟著走 |
| `move` 搬走 root 的子孫 | 保留，範圍自動縮小 | 離開子樹就不再被框 |
| 搬一個節點**進** root 底下 | 自動被框住 | 範圍即時推導的必然結果 |
| 兄弟重排（`moveSibling`） | 無影響 | 範圍不含順序語意 |
| **收合 root** | **仍然畫**，框住 root 自身節點框 | root 仍可見；外框是 root 的屬性，收合不該讓它消失 |
| 收合子孫 | 被隱藏的子孫不畫、不計入範圍 | 看不見的東西不能畫框；展開後自動恢復 |
| 子孫全部被收合 | 框只剩 root 自身 | 同上 |
| undo / redo | 隨整份文件快照進出（`ViewModel.swift:316-345`） | 不需專用邏輯 |
| 切分頁／複製文件 | 隨文件走 | 與 `summaries` 相同 |

**收斂點決定**：新增 `pruneBoundaries(doc:)`（檢查每個 `rootID` 是否仍存在），並且**在 `mutate` 內呼叫**，而不是在 `delete` / `deleteBatch` 各加一次。理由：§0.3 的 bug 正是「有人忘了在某個呼叫點 prune」；把不變式綁在唯一的 mutation 入口，未來新增任何結構操作都自動正確。成本：每次 mutation 走一次 `boundaries × contains`，文件是幾十到幾百節點的樹，可忽略。
（`ViewModel.swift` 是 p1 目前的作業線，實作時由 p1 決定放置位置；本提案只主張「單一收斂點」這個性質。）

**與 `MindSummary` 的語意差異要寫進文件**：summary 是**範圍**語意（端點 id 跟著兄弟移動而隱式擴張），boundary 是**錨點**語意（成員即時推導）。兩者不要互相對齊，也不要「順手」讓 boundary 沿用 summary 的 prune 路徑。

---

## 3. 持久化與復原

### 3.1 `.mindmap` 檔

```json
"boundaries": [ { "id": "…", "rootID": "…" } ]
```

- 容錯解碼：缺 `boundaries` → `[]`；缺 `id` → 重新產生；不認得的欄位忽略（`docs/FORMAT.md`「容錯解碼規則」）。
- 往返保證：存檔→讀檔後 `boundaries` 與 `rootID` 完全相等。
- **`docs/FORMAT.md` 要新增 Boundary 段**（p1 擁有該檔）。順帶：**目前頂層結構表根本沒有 `summaries`**，只在「與其他格式的互通」表提到概要——這是既有文件債，建議同一批補上。
- 建議的 FORMAT.md 欄位表（給 p1 直接抄）：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `id` | UUID 字串 | 自動產生 | 外框唯一識別碼 |
| `rootID` | UUID 字串 | — | 被框住分支的根節點 `id`；涵蓋 root 及其子孫 |

### 3.2 undo / redo

`mutate` 存的是**整份 `MindDocument` 快照**（`ViewModel.swift:316-329`）。boundary 的新增／刪除都走 `mutate` → 自動可 undo，**不需要新機制**。
選取狀態（`selectedBoundaryID`）**不進 undo**，與 `selectedSummaryID` 一致（選取是 UI 狀態，不是文件狀態）。

### 3.3 匯出

| 格式 | v1 | 理由 |
|---|---|---|
| SVG | **畫** | 向量格式能表達；與畫布共用幾何（`MapExporter.swift:175-190` 的 summary 就是這個模式） |
| PNG / PDF（`StaticMapView`） | **畫** | 同一個幾何函式（`StaticMapView.swift:103-120`） |
| Markdown | **不輸出**，文件化 | MD 是**樹狀**格式。`MapExporter.markdown` 對 summary 用的是「接在子樹後的一行」`- ↳ 概要（含X）: text`（`:47-60`），因為 summary 有明確的父與端點；boundary 的成員跨層級，沒有等價的錨點行，硬塞會誤導。**而且我們的 MD 匯入會把那一行變成真節點**，等於製造假資料 |
| OPML / FreeMind | **不輸出**，文件化 | 同上，樹狀格式沒有表達這種註記的通道 |
| 匯入（MD/OPML/FreeMind） | **忽略** | 與 `summaries` 現況一致（`MapImporter.swift` 對 summary 有 **0** 處提及） |

「表達不了就明說」：`FORMAT.md` 的互通表要加一列 Boundary，匯出欄位標「SVG/PNG 有；MD/OPML/FreeMind 無」。
**若 Owner 之後真的抱怨 MD 看不到外框**，再談 lossy 一行（例如 `- ↳ 外框（含 A、B、C）`）；v1 不做，因為它會被自己匯入成節點。

### 3.4 幾何（三個渲染面共用）

新增純函式（對照 `SummaryGeometry.swift:5-21` 的既有模式）：

```swift
public struct BoundaryFrameGeometry: Equatable {
    public let rect: CGRect      // root 與可見子孫 frames 的聯集，外擴 padding
    public let cornerRadius: CGFloat
}
public enum BoundaryGeometry {
    public static func frame(for boundary: MindBoundary,
                             layouts: [UUID: NodeLayout],
                             origin: CGPoint) -> BoundaryFrameGeometry?
}
```

- 範圍：`root` 與**可見**子孫的 `NodeLayout.frame` 聯集，外擴約 10–12pt（summary 的 `out = 14` 同量級）。
- 形狀：圓角矩形（XMind 有 `boundaryShape` / `boundaryBorderLinePattern` / `boundaryFillColorString` 等樣式，v1 **不做選項**）。
- 顏色：**沒有專用色槽**（§0.1），v1 用既有 `Palette`——描邊 `palette.textSecondary.opacity(0.8)`（與 summary 描邊一致）、填色 `palette.accent.opacity(0.06)`（極淡，不搶節點）。
- 圖層：畫在節點之前（背景層），與 `StaticMapView.swift:81` 的 summary 括線同一層。
- **不確定**：4 種版面的聯集是否都好看。邏輯圖（`logicRight`）沒問題；平衡圖／魚骨圖／括號圖是否會出現「一個子樹的 bounding box 蓋到無關節點」**沒有實測**。要先量的：對 4 個 `MapDirection` 各跑一次「深子樹 + 外框」的截圖／bounds 檢查。若某版面醜，fallback 是限制該版面或改畫「沿子樹外緣的折線」，但**這是幾何問題，不影響 §1 的模型**。

---

## 4. 最小第一刀（只能做一件事就出貨）

### v1 交付（可獨立上線，每項都完整）

1. `MindBoundary` 模型 ＋ `MindDocument.boundaries` ＋ 容錯解碼。
2. `pruneBoundaries` 掛在 `mutate`（§2 的不變式）。
3. `BoundaryGeometry.frame` 純函式。
4. 畫布：畫圓角框、可點選、可刪除（右鍵選單或 Delete，與 summary 的互動一致）。
5. 入口：節點右鍵選單「加入外框」／已有外框時顯示「移除外框」。
6. 存檔往返 ＋ SVG / PNG 匯出。
7. Checks：§2 表格**每一列**一條、Codable 往返、幾何（含收合子孫）、匯出含／不含。
8. `docs/FORMAT.md` 的 Boundary 段（p1 執行）。

### 為什麼是「子樹」而不是「範圍外框」

範圍外框的涵蓋語意與 `MindSummary` 重疊（§0.2），做了只是「概要的另一種畫法」；**主外框是唯一現有資料結構表達不了的東西**，所以它才是那個「只能做一件事」的事。這也符合「narrow but complete」：一種型別，每個生命週期情況都定義完整，而不是四種型別各做一半。

### v1 明確不做（連理由一起留下）

| 不做 | 理由 |
|---|---|
| 範圍外框（`rangeType: children`） | 與 `MindSummary` 涵蓋語意重複，只差畫法。**要先問 Owner**：他要的是「封閉框版的概要」嗎？ |
| 外框標題 | 沒有編輯入口就是死欄位；要命名用 summary |
| 樣式（形狀／線型／填色／透明度） | 沒有使用情境；XMind 那些選項是給「同主題多外框」區分用的，我們一 root 一框 |
| 拖曳調整範圍 | 錨點語意下沒有「範圍端點」可拖 |
| MD / OPML / FreeMind 匯出 | 樹狀格式表達不了，硬做會產生假節點（§3.3） |
| 匯入 | 與 summary 現況一致 |
| 大綱 / Inspector 顯示 | 外框不是節點，不屬於大綱樹 |
| 「不連續成員集合」 | XMind 沒有；表達力換來的是每個 mutation 的同步與 prune 面積（§D1） |

---

## 5. 不確定 / 要先量什麼（不編）

1. **XMind 刪除／搬移被框節點時，範圍端點怎麼調整**：asar 只看得到「插入在 rangeEnd 之後會擴張」（`asMovable({rangeEnd: rangeEnd + l.length})`），刪除時的行為**沒有實跑 XMind 驗證**。**我們的錨點模型不需要這條規則**；只有要 1:1 對齊 XMind 的範圍外框才需要，屆時要先在 XMind 裡實測並記錄。
2. **範圍外框要不要做**：取決於 Owner 是否認為「概要括線」與「封閉外框」是兩種不同的東西。目前證據只能說涵蓋語意相同。
3. **顏色是否新增主題角色**：`Palette` 沒有 boundary 角色（§0.1）。v1 先用既有色；若要新增，那是主題系統的票（p1 目前的作業線）。
4. **巢狀深度限制**：v1 不設限，**沒有實測** XMind 有沒有上限。
5. **`MindSummary` 搬移不 prune**（§0.3）是既有缺陷，**不在本提案範圍**；要修是獨立一張票（會動 `ViewModel.move`）。
6. **執行期驗收**：螢幕目前鎖定，任何 GUI 探針跑不了。解鎖後要跑：右鍵建立外框 → 框出現且可選取 → Delete 移除 → undo 復原 → 收合子孫框縮小 → 收合 root 框仍在 → 匯出 SVG 含框、MD 不含。

---

## 6. 驗收看點（給 p1 轉票用）

- **模型**：§2 表格每一列一條 check；`boundaries` Codable 往返（含缺欄位／未知欄位）；同一 root 不重複；root 被刪後 boundary 被 prune。
- **幾何**：單節點／深子樹／收合子孫／巢狀／4 種版面的 bounds。
- **執行期（AX，需解鎖）**：建立→可選取→刪除→undo；節點刪除後框**縮小而非消失**。
- **匯出**：SVG 含外框 path；Markdown／OPML **不含**，且不產生假節點。

---

## 附錄 A-0：p1 獨立驗證（第 32 輪）

本提案最關鍵的一步是 §0.2 的語意收窄（「XMind 沒有跨父節點的任意成員集合」），它直接決定了 D1 採用錨點而非成員集合。該結論原本只有**單一來源**：XMind `app.asar` 的字串。

**證據來源缺口（如實記錄）**：p1 在本機**找不到任何 `.asar`**（`/Applications` 無 XMind、`~/Downloads` 只有一份 `.xmind` 文件），因此**無法重現該次量測**。單一且不可重現的外部證據，不足以獨自支撐一個架構決定。

**改以獨立管道複查，結論一致**。XMind 官方使用指南 `https://xmind.com/user-guide/boundary-new` 逐字寫道：

> When adding a boundary to **multiple topics**, topics from the same branch will be grouped under the same boundary. **Topics from different branches will each have their own boundary.**
>
> **The central topic and multiple floating topics** cannot have a boundary.

這與 §0.2 的主張相同：**外框不能跨分支**，所以「不連續／跨父節點成員集合」在 XMind 裡不存在。D1 的錨點模型因此站得住，且其理由不依賴任何無法查核的來源。

同一頁另外兩項對實作有用、且本提案原本沒寫的事實：
- 「Adjust the Boundary Scope：拖曳外框上下的藍色邊界可調整範圍」——與 `rangeStart`/`rangeEnd` 的連續兄弟語意吻合，是 §0.2 表格的旁證。
- **Mac 快捷鍵為 `⇧⌘B`**。專案預設是 XMind parity，v1 應直接沿用，不要另創。


## 附錄 A：證據出處

**本專案（HEAD `6c0b1b6`）**
- `Sources/MindFlowKit/Model.swift:153-167`（`MindSummary` 欄位與「同父連續兄弟」語意）、`:183-189`（`MindDocument`，`summaries` 在 `:188`）
- `Sources/MindFlowKit/Theme.swift:100-103`（`GamutMapping.step/.boundary`）、`:102`、`:217`、`:304`（使用點）
- `Sources/MindFlowKit/ViewModel.swift:316-345`（`mutate`/`undo`/`redo` 整份快照）、`:456` 與 `:1310`（僅刪除路徑 prune）、`:1446`（`pruneSummaries`）、`:495`（`move`）、`:517`（`promote`）、`:702`/`:939`（`moveSibling`）
- `Sources/MindFlowKit/SummaryGeometry.swift:5-21`（`SummaryBracketGeometry` / `bracket(for:)`）
- `Sources/MindFlowKit/MapCanvasView.swift:608-645`（畫布 summary 渲染／選取）、`StaticMapView.swift:103-120`（PNG/PDF）、`MapExporter.swift:175-190`（SVG）、`:47-60`（MD 概要行）
- `Sources/MindFlowKit/LayoutEngine.swift:129`/`:291`/`:307`（收合子樹不進 layout）
- `Sources/MindFlowKit/MapImporter.swift`（`summar` 出現 0 次）
- `docs/FORMAT.md`（容錯解碼規則；頂層表缺 `summaries`）、`docs/XMIND-GAP.md:34-35`（待更正）

**XMind 本體（`app.asar` 字串，逐字）**
- `rangeType:i.rangeType??"children",rangeStart:i.rangeStart??0,rangeEnd:i.rangeEnd??0,title:i.title??""`
- `o.range="parent"===e.rangeType?"master":`(${e.rangeStart},${e.rangeEnd…`
- `visibleMasterBoundaries`
- `y(d(t),"boundaries",[])`（topic 帶 boundary id 陣列）
- 樣式欄位：`boundaryShape`、`boundaryBorderLinePattern`、`boundaryFillColorString`、`boundaryBorderLineWidth`、`boundaryFont`、`boundaryAddingTitleButton`、`"boundarytitle"`
