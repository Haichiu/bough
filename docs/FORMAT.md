# MindFlow 檔案格式（.mindmap）

`MindFlow` 把你的圖存成**單一 JSON 文字檔**（UTF-8、副檔名 `.mindmap`）。沒有資料庫、沒有雲端、沒有私有二進位格式——任何程式都能讀寫。

> 相容性承諾：以下欄位是穩定介面。未來新版新增欄位時，舊檔照樣開啟；刪除任何現有欄位前會先經過長期棄用程序。

## 頂層結構（MindDocument）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `title` | String | 文件標題 |
| `themeName` | String | 主題 ID：`ocean`／`candy`／`forest`／`mono` |
| `directionName` | String | 版面：`logicRight`（邏輯圖）／`balanced`（平衡圖）／`fishbone`（魚骨圖）／`bracket`（括號圖） |
| `root` | Node | 中心主題（樹根） |
| `links` | [Link]? | 關聯線陣列，可省略 |
| `boundaries` | [Boundary]? | 外框陣列，可省略；每項只記一個錨點 `rootID`（見下節） |
| `offsets` | [String: {x, y}]? | 自由放置的座標偏移（鍵為節點 UUID 字串），可省略 |

## 節點（Node）— 遞迴結構

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `id` | UUID 字串 | 自動產生 | 節點唯一識別碼 |
| `text` | String | `""` | 主題文字 |
| `note` | String | `""` | 備註 |
| `collapsed` | Bool | `false` | 是否收合子主題 |
| `marked` | Bool | `false` | 星星標記 |
| `url` | String? | `nil` | 關聯網址（選單可直接開啟，SVG 匯出變連結） |
| `image` | String? | `nil` | 附圖的 data URL（base64 內嵌，維持單檔可攜） |
| `colorTag` | String? | `nil` | 色標鍵：`red`／`orange`／`yellow`／`green`／`blue`／`purple` |
| `children` | [Node] | `[]` | 子主題 |

## 關聯線（Link）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | UUID 字串 | 唯一識別碼 |
| `from` / `to` | UUID 字串 | 兩端節點的 `id` |
| `label` | String | 可省略；顯示在線上的文字（如「導致」），隨 SVG 匯出 |

## 外框（Boundary）

外框是圈住**一條分支**的框線。檔案只記「錨點」，框住的範圍由樹推導。

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `id` | UUID 字串 | 自動產生 | 外框唯一識別碼 |
| `rootID` | UUID 字串 | 必填 | 被框住分支的根節點 `id` |

```json
"boundaries": [
  { "id": "33333333-3333-3333-3333-333333333333",
    "rootID": "22222222-2222-2222-2222-222222222222" }
]
```

### 涵蓋範圍是推導出來的

外框涵蓋 `rootID` 本身加上它的所有**可見**子孫（被收合而隱藏的子孫不算）。範圍不存檔，每次繪製時從樹即時算出來，所以下列行為不需要任何額外維護：

| 你做的事 | 外框的結果 |
|---|---|
| 刪掉 `rootID` 的子孫 | 框自動縮小（`boundary: deleting a covered descendant keeps the boundary`） |
| 把 `rootID` 搬到別的父節點 | 框跟著錨點走（`boundary: moving the anchor keeps the boundary on it`） |
| 把子孫搬離 `rootID` | 框保留，該子孫不再被框住（`boundary: moving a descendant out keeps the boundary`） |
| 收合 `rootID` | 框仍在，只框住 `rootID` 自己（`boundary geometry: a collapsed anchor frames only its own node, padded 10pt`） |
| 刪除 `rootID`（或它的祖先） | 這筆外框記錄一併移除（`boundary: deleting the anchor prunes the boundary`；祖先的情況未單獨驗證） |
| 調整兄弟順序 | 只改順序，外框不受影響（`boundary: reordering siblings changes nothing but the order`） |

**為什麼存錨點而不是成員清單**：成員清單是把樹的狀態複製一份，複製品就有腐化的機會——節點被刪除、搬移、重排之後都要同步，只要漏掉一條路徑，檔案裡就會留下指向不存在節點的孤兒記錄（概要括線的歷史缺陷正是如此：只有刪除路徑會清理）。錨點讓「框住誰」永遠是推導結果，不可能與樹不一致。代價是表達不了「不連續的成員集合」——但 XMind 的外框也沒有這個語意（見 `docs/proposals/boundary.md` §0.2）。

同一個 `rootID` 最多一個外框（`boundary: a second boundary on the same root is not created (D4)`）；不同層級的外框可以巢狀（**未驗證**：沒有對應檢查）。

### 外框的相容性

| 情況 | 行為 | 對應檢查 |
|---|---|---|
| 舊檔沒有 `boundaries` | 解碼成空陣列 | `boundary: an older file without the field decodes to none` |
| 外框帶著不認得的欄位 | 忽略該欄位，其餘照常解碼 | `boundary: an unknown field is ignored and a missing id is regenerated` |
| 外框缺少 `id` | 重新產生一個 | 同上 |
| 存檔後再讀檔 | `id` 與 `rootID` 完全保留 | `boundary: Codable round-trip preserves id and rootID` |

`rootID` 是唯一必填欄位；缺漏代表檔案損毀，走下面「提示而不是閃退」的既有路徑（**未驗證**：沒有對應檢查）。

### v1 不含（刻意不做，不是待補）

| 不含 | 理由 |
|---|---|
| 範圍外框（XMind 的 `rangeType: children`） | 涵蓋語意與既有的概要括線重疊，只差畫法 |
| 外框標題 | 沒有編輯入口，先加欄位就是死欄位 |
| 樣式（形狀／線型／填色） | 一個錨點一個框，沒有區分需求 |
| 拖曳調整範圍 | 錨點語意下沒有可拖的端點 |
| Markdown／OPML／FreeMind 匯出 | 樹狀格式沒有表達非樹註記的通道，硬塞會變成假節點 |
| 匯入（任何格式） | 與概要括線的現況一致 |
| 大綱／檢閱器顯示 | 外框不是節點，不屬於大綱樹 |
| 不連續的成員集合 | XMind 也沒有這個語意，代價見上 |

## 容錯解碼規則

- 缺少任何欄位 → 使用上表預設值（例如舊版檔案沒有 `label` 也能開啟）；必填欄位見各節說明
- 不認得的欄位 → 直接忽略（向前相容）
- 缺少 `id` → 重新產生
- 檔案損毀無法解析 → App 會提示而不是閃退

## 最小範例

```json
{
  "title": "我的圖",
  "themeName": "ocean",
  "directionName": "logicRight",
  "root": {
    "id": "11111111-1111-1111-1111-111111111111",
    "text": "中心主題",
    "children": [
      { "id": "22222222-2222-2222-2222-222222222222", "text": "第一個想法" }
    ]
  }
}
```

把上面的內容存成 `我的圖.mindmap`，用 MindFlow 就能直接打開。

## 與其他格式的互通

| 格式 | 匯入 | 匯出 | 備註 |
|---|:-:|:-:|---|
| 概要括線 | — | ✅（圖形格式） | Markdown 匯出為 `- ↳ 概要（含…）: 文字` 項目；重新匯入時會成為一般節點 |
| 外框 | — | ✅（SVG；PNG／PDF 未驗證） | Markdown／OPML／FreeMind 不輸出——樹狀格式沒有表達這種註記的通道 |
| Markdown 大綱 | ✅ | ✅ | `-`／`*` 條列＋縮排；`>` 開頭為備註 |
| OPML | ✅ | ✅ | 備註放在 `_note` 屬性 |
| FreeMind (.mm) | ✅ | ✅ | `TEXT`／`FOLDED`／`COLOR` 屬性＋`richcontent NOTE` 備註 |
| PNG / PDF / SVG | — | ✅ | SVG 為向量圖，保留色標、星標、備註提示與超連結 |