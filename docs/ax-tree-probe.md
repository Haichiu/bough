# T-003 AX Tree 探測報告（決策點）

日期：2026-08-28 ｜ 探測對象：**可定址** ← 一句話結論

## 問題

畫布上的心智圖節點，在 macOS accessibility tree 上看不看得到、能不能用名稱/角色定址？

## 答案：**看得到、可定址（YES）**

- small-20 fixture 的 **20/20 節點全部出現在 AX tree**，每個都是 `AXStaticText`，`value` 即節點文字（`N-0005`…`N-0019`），`description="text"`。
- 每個節點文字元素都帶 **`position` 與 `size`（真實螢幕座標）** → 可用 AX 定位後對中心點座標點擊。
- 節點元素**沒有 `AXPress` action，只有 `AXShowMenu`** → 不能對節點直接 `perform action "AXPress"` 觸發選取；harness 走「**AX 查詢定址 + System Events 座標點擊**」這條路，不需要 `screencapture` 影像比對。
- 整棵 window tree 只有 **91 個元素**（20 節點的圖），`entire contents` 一發取回，探測耗時 <1 秒。

## 探測條件

| 項目 | 值 |
|---|---|
| App | `~/Desktop/MindFlow.app`（v3.8，2026-08-28 12:13 打包版） |
| Fixture | `scripts/fixtures/small-20.mindmap`（經 tabs slot `0D3F1CE0-0000-4000-8000-0000000000F1` 載入） |
| 視窗標題 | `N-0000 – v3.8 · 自動儲存中` |
| 方法 | `osascript` + System Events，`entire contents of window 1` 一次取回後逐元素讀 role/description/title/value/position/size/actions |
| 腳本 | `scripts/uitest/ax-probe.sh <pid>`（唯讀，未點擊、未改狀態） |

## 角色分布（91 元素）

| 角色 | 數量 | 說明 |
|---|---|---|
| AXStaticText | 48 | 20 個節點文字 + 工具列/檢閱器/麵包屑文字 |
| AXButton | 33 | 工具列/縮放/分頁關閉等 |
| AXUnknown | 6 | |
| AXGroup | 6 | 容器層（**未**帶節點文字，節點容器沒有獨立 AX 標籤） |
| AXTextField | 3 | 搜尋/取代/檢閱器輸入框 |
| AXScrollArea | 3 | |
| AXPopUpButton | 3 | |
| AXRadioButton / AXSegment | 2 | 檢閱器「備註/大綱」分段 |
| AXImage | 2 | |
| 其他（Toolbar/TextArea/ScrollBar/RadioGroup/CheckBox） | 各 1 | |

## 節點命中樣本（前 8 筆，完整 20 筆見附錄）

```
AXStaticText | d=text | v=N-0005 | pos=720,497 | size=58x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0006 | pos=720,525 | size=58x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0001 | pos=632,537 | size=59x23 | actions=AXShowMenu
AXStaticText | d=text | v=N-0007 | pos=720,552 | size=58x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0008 | pos=720,579 | size=58x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0009 | pos=721,606 | size=58x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0010 | pos=721,634 | size=56x20 | actions=AXShowMenu
AXStaticText | d=text | v=N-0002 | pos=632,646 | size=60x23 | actions=AXShowMenu
```

## 對 harness 的含義（僅記錄，未實作）

1. 定址配方：flat 取回 `entire contents` → 過濾 `AXStaticText` 且 `value` 符合 `N-\d{4}` → 讀 `position`/`size` → 對中心點座標點擊。全程 AX 座標，無解析度/主題飄移問題。
2. 選取環本身不是 AX 元素（SwiftUI overlay shape 未進 tree）→「選取成功」的驗證需透過其他可觀察狀態（例如檢閱器/麵包屑/視窗標題變化），harness 設計時要選定代理指標。
3. medium-200/large-1500 的完整 `entire contents` 會明顯變大（節點數 ×3.5 元素估計）；大圖 harness 應改用 `whose value is "N-xxxx"` 定向查詢或限定快取。本次探測僅在 small-20 上保證。
4. 節點文字 `AXShowMenu` 恰好對應節點的 context menu（SwiftUI `.contextMenu`）→ 右鍵選單測試可原生觸發。

## 重現

```bash
bash scripts/dev.sh small-20        # 或手動把 fixture 放進 tabs slot 後啟動 ~/Desktop/MindFlow.app
bash scripts/uitest/ax-probe.sh     # stdout = 本附錄格式的 dump
```

## 附錄：完整 AX dump（91 元素）

```text
WINDOW_TITLE=N-0000 – v3.8 · 自動儲存中
TOTAL_ELEMENTS=91
AXGroup/AXHostingView | d=group | t=missing value | v=
AXScrollArea/missing value | d=scroll area | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXRadioGroup/missing value | d=模式 | t=missing value | v=
AXRadioButton/AXSegment | d=備註 | t=missing value | v=
AXRadioButton/AXSegment | d=大綱 | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=中心主題
AXStaticText/missing value | d=text | t=missing value | v=備註…
AXStaticText/missing value | d=text | t=missing value | v=N-0005
AXImage/missing value | d=image | t=missing value | v=
AXTextField/missing value | d=text field | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=0
AXButton/missing value | d=button | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=N-0006
AXStaticText/missing value | d=text | t=missing value | v=N-0001
AXStaticText/missing value | d=text | t=missing value | v=N-0007
AXStaticText/missing value | d=text | t=missing value | v=N-0008
AXStaticText/missing value | d=text | t=missing value | v=N-0009
AXStaticText/missing value | d=text | t=missing value | v=N-0010
AXStaticText/missing value | d=text | t=missing value | v=N-0002
AXStaticText/missing value | d=text | t=missing value | v=N-0011
AXStaticText/missing value | d=text | t=missing value | v=N-0000
AXStaticText/missing value | d=text | t=missing value | v=N-0012
AXStaticText/missing value | d=text | t=missing value | v=N-0013
AXStaticText/missing value | d=text | t=missing value | v=N-0014
AXStaticText/missing value | d=text | t=missing value | v=N-0003
AXStaticText/missing value | d=text | t=missing value | v=N-0015
AXStaticText/missing value | d=text | t=missing value | v=N-0016
AXStaticText/missing value | d=text | t=missing value | v=N-0017
AXStaticText/missing value | d=text | t=missing value | v=N-0004
AXStaticText/missing value | d=text | t=missing value | v=N-0018
AXStaticText/missing value | d=text | t=missing value | v=N-0019
AXTextField/missing value | d=text field | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXScrollArea/missing value | d=scroll area | t=missing value | v=
AXTextArea/missing value | d=備註內容 | t=missing value | v=
AXScrollBar/missing value | d=scroll bar | t=missing value | v=
AXImage/missing value | d=image | t=missing value | v=
AXTextField/missing value | d=節點網址輸入框 | t=missing value | v=
AXScrollArea/missing value | d=scroll area | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=色標
AXUnknown/missing value | d=missing value | t=missing value | v=
AXUnknown/missing value | d=missing value | t=missing value | v=
AXUnknown/missing value | d=missing value | t=missing value | v=
AXUnknown/missing value | d=missing value | t=missing value | v=
AXUnknown/missing value | d=missing value | t=missing value | v=
AXUnknown/missing value | d=missing value | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=20 個主題 · 最深 3 層 · ★ 0 · 備註 0 · 連結 0
AXButton/missing value | d=button | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=65%
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXToolbar/missing value | d=toolbar | t=missing value | v=
AXButton/missing value | d=子主題 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=兄弟主題 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=刪除 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=全部展開 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXButton/missing value | d=全部收合 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXGroup/missing value | d=group | t=missing value | v=
AXPopUpButton/missing value | d=pop up button | t=lineweight.thin | v=
AXButton/missing value | d=符合視窗 | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXGroup/missing value | d=group | t=missing value | v=
AXPopUpButton/missing value | d=pop up button | t=Divide | v=
AXGroup/missing value | d=group | t=missing value | v=
AXPopUpButton/missing value | d=pop up button | t=paintpalette | v=
AXButton/missing value | d=複製 MD | t=missing value | v=
AXButton/missing value | d=button | t=missing value | v=
AXGroup/missing value | d=group | t=missing value | v=
AXCheckBox/AXToggle | d=toggle button | t=missing value | v=
AXButton/AXCloseButton | d=close button | t=missing value | v=
AXButton/AXFullScreenButton | d=full screen button | t=missing value | v=
AXGroup/missing value | d=group | t=missing value | v=
AXButton/AXMinimizeButton | d=minimize button | t=missing value | v=
AXStaticText/missing value | d=text | t=missing value | v=N-0000
AXStaticText/missing value | d=text | t=missing value | v=v3.8 · 自動儲存中
HITS_COUNT=20
HITS_START
AXStaticText/missing value | d=text | t=missing value | v=N-0005 | pos=720,497 | size=58x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0006 | pos=720,525 | size=58x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0001 | pos=632,537 | size=59x23 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0007 | pos=720,552 | size=58x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0008 | pos=720,579 | size=58x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0009 | pos=721,606 | size=58x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0010 | pos=721,634 | size=56x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0002 | pos=632,646 | size=60x23 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0011 | pos=721,661 | size=55x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0000 | pos=505,680 | size=84x37 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0012 | pos=721,688 | size=56x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0013 | pos=721,716 | size=56x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0014 | pos=721,743 | size=57x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0003 | pos=632,755 | size=60x23 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0015 | pos=721,770 | size=56x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0016 | pos=721,797 | size=57x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0017 | pos=721,825 | size=56x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0004 | pos=632,850 | size=60x23 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0018 | pos=721,852 | size=57x20 | actions=AXShowMenu
AXStaticText/missing value | d=text | t=missing value | v=N-0019 | pos=721,879 | size=57x20 | actions=AXShowMenu
```
