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
| `colorTag` | String? | `nil` | 色標鍵：`red`／`orange`／`yellow`／`green`／`blue`／`purple` |
| `children` | [Node] | `[]` | 子主題 |

## 關聯線（Link）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | UUID 字串 | 唯一識別碼 |
| `from` / `to` | UUID 字串 | 兩端節點的 `id` |
| `label` | String | 可省略；顯示在線上的文字（如「導致」），隨 SVG 匯出 |

## 容錯解碼規則

- 缺少任何欄位 → 使用上表預設值（例如舊版檔案沒有 `label` 也能開啟）
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
| Markdown 大綱 | ✅ | ✅ | `-`／`*` 條列＋縮排；`>` 開頭為備註 |
| OPML | ✅ | ✅ | 備註放在 `_note` 屬性 |
| FreeMind (.mm) | ✅ | ✅ | `TEXT`／`FOLDED`／`COLOR` 屬性＋`richcontent NOTE` 備註 |
| PNG / PDF / SVG | — | ✅ | SVG 為向量圖，保留色標、星標、備註提示與超連結 |