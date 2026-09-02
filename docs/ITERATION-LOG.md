# MindFlow 迭代紀錄

Owner 裁定迭代 50 輪。本檔是唯一進度來源；唤醒後先讀這裡再接手。

## 角色

| 角色 | pane | 職責 |
|---|---|---|
| 主 agent | `wD:p1` | 視覺方案、驗收、完成判定 |
| 助理 | `wD:p4` | 程式架構、技術方案、審查 |
| Worker | `wD:p6` | 實作（雙方定案後才派）|

## 規則

- 一輪 = 一個**已驗證的改善**，不是一個 commit，也不是一次嘗試
- 未驗證不計入；回退的也不計入
- 沒有真實改善可做時要說出來，**不得為了湊數字發明工作**
- 本檔上限 60 條；超過就歸檔到 `docs/archive/`

## 事故：2026-09-01 tabs provenance（已結案，無損失）

主 agent 在 01:22 拍了一份「保險備份」，但當時 Worker 的 GUI transaction 正在跑。快照印出 `VERIFIED`，實際拍到測試中間狀態。

最終結果：owner 資料完好。live 保留 postquit `1e0fd74f...`，經鑑識確認是最新 flush 狀態（兩份預設名單節點圖得到真實命名、一份標題 10→11 字，方向與損壞相反）。

### 由此寫死的規則

1. **備份的效力來自 provenance，不來自 copy fidelity。**驗證「複本 = 來源」等於什麼都沒驗
2. **跨 pane 備份前必須確認無 GUI transaction 進行中**
3. **可逆不是不驗的理由。**結果對不對跟該不該先驗，是兩件事
4. **對路徑的量測必須先斷言路徑存在。**「路徑不存在」與「結果為空」在輸出上難以區分（曾因此發出假警報）
5. **持久化完整性驗證含 filename+bytes；語義診斷至少含 root title + node count。**只看 node count 不夠 —— 單節點地圖的全部內容就在 title 上
6. **不轉述未驗證的數字。**主 agent 曾複述「4 vs 4」，實為共同 8 / 各自 12

### 待清理（owner 確認後）

- `~/Documents/UNTRUSTED-DO-NOT-RESTORE-mindflow-tabs-0122-taken-mid-test`
- `/tmp/mindflow-t035-owner-tabs-prequit-62193`
- Support 下的 `tabs.owner-20260829` / `tabs.pre-dev-backup` / `tabs.pre-uitest-backup`

## 進度

| # | 項目 | 證據 | commit |
|---|---|---|---|
| 1 | T-035 自由畫布（三段式放開判定、子樹跟隨、root→pan、回到自動排列）| Worker 六項 GUI A–F PASS；cycle mutation control 預期 FAIL(rc133)；Checks+verify 全綠。像素量測：E 108px/4px 厚、F 84px/2px 厚；厚度門檻 3.1px 由規格推得（指示器 3.7 / 連接線 2.5）。預期長度以 card width **76pt → 97.6px** 為準，舊的 64pt/79px 作廢 | `2240b00` |
| 2 | T-035 follow-up：删除危險的 `u35.sh`（trap 覆蓋使備份還原被靜默拆掉）、Cmd-Z 收進 `performCoreShortcut` | Checks+verify 獨立跑過 | `a72c2b2` |
| 3 | T-036 色票 A（OKLCh 推導、三層節點形態、深色中性色、移除假 theme picker）| 主 agent 量渲染像素：深色四色對畫布 3.102–3.129、奶油字 5.007–5.049；混色 5.03–5.33。**首版被退**：紅色量化後 2.9986。六色中四色親量、二色依回報 hex 計算 | `cc90f7c` |
| 4 | 狀態訊號縮放不變（指示器/選取/重掛/search/batch/hover/連結線/summary，含 padding、圓角、虛線）| fit 0.23 下量得指示器 6px=**3.00pt**、選取圈 4px=**2.00pt**；若隨內容縮應為 1.38px / 0.92px。mutation（不除 scale）rc1 / 47 failures。**命中帶未動** | `249b56c` |
| 5 | TabStore 交易邊界（staging+commit、sibling 上限、cleanup 不掩蓋主因）| 助理獨立驗 ownership gate 與 names/bytes/mtime oracle；verify rc0、mutation rc1。規則收斂為「**只有本次確實新增 sibling 才得 prune**」，以不變式取代列舉錯誤路徑 | `219332c` |
| 6 | import 上限（bytes 8 MiB、depth 128、**不設節點上限**）| bounded read + 邊解析邊中止；拒絕時不動 document/undo/dirty/selection。掉了 OPML 多 top-level 深度少算 1 的 bug（fixture 只有一個 top-level，結構上測不到）。原生 `.mindmap` 不受限 | `060b744` |
| 7 | 圖標改由程式生成（三尺寸帶、光學置中）| 10 slots 全過 runs=3 / peak≥680 / 端點對比≥3；主 agent 獨立重建 1024 量得**重心偏移 0.07%**（修正前 6.78%）。字形美感仍 owner-pending | `bce215f` `f4d2bcd` |
| 8 | 字體階層：**產品無缺陷，NodeStyle 未改**；只補契約 gate | 實渲染比 1x/2x 皆 1.20/1.1538；equal 與 stale baseline 兩條 control 兩尺度全 rejected；墨色 oracle 以 `一`=2px vs `思考Hg`=18px 證明未退化成 line box | `5e4769b` |
| 9 | 六分支 light／dark 視覺審查 fixture | 建立後立即用它抳出 connector 色彩缺陷：六條連接線全為單一 `#3268A0` | `4bda586` |
| 10 | UI 測試 storage 雔離（單一 `MINDFLOW_STORAGE_ROOT`）| 產品端 marker 守衛（目錄存在 + 是目錄 + marker 內容逐位元組相等）；production-path gate 改錯即 rc=1；GUI proof：owner tabs digest／20 檔／root-title SHA16／node count 前後相同 | `5e68795` |
| 11 | connector 幾何所有權（`ConnectionGeometry` 產 primitives，其餘只做 adapter）| 主 agent 親量：x=615 六條連接線 **y 範圍新舊逐條完全相同**，顏色由 1 種變 6 種；light 對比 4.81–5.34、dark 3.09–3.24 | `99d179b` |
| 12 | 儲存失敗持續信號（`Set<StorageFailureKind>`、episode semantics）| 三個 mutation 有牙；主 agent 逐字核對三條文案，確認 warning 提前 return、**有警告時不顯示時間戳** | `bb6c044` |
| 13 | 外殼語意色（去 Palette A）| 主 agent 量：**畫布本體 x0…1403 y171…1343 前後相異像素 = 0**（light／dark 皆然）；dirty 暖色像素 96→0／112→0；星標核心 `244,197,65` 前後相同 | `71d3784` |
| 14 | 工具列精簡（主列只留子主題／兄弟／檢閱器，餘進 More）| 選單項目帶九條：Divider 在 y384…385（高2、色113,114,113）、刪除置底；工具列無垂直分隔線。**發現 destructive 在 macOS 選單不渲染紅色**，oracle 改守可觀察三件 | `30cca8f` `3df5f27` |
| 15 | 星標幾何：bottom-center + layout 預留 + fishbone reroute | 主 agent 親量四版面×light／dark **32/32 CLEAR**，墨色一致（light 119／dark 120）；fishbone 由 FOREIGN 18px→0；association 僅擦過 padding（foreign 全在 ink bbox 下一列） | `6ca883a` |

### 這兩輪的教訓：文件漂移比沒文件更危險

主 agent 依 §2 提出字體階層修正案，但 §2 寫的 15/13/12.5 早已不是產品（實為 18/15/13）。那個「4% 塌陷」不存在，**提案若執行會把已可辨識的階層縮小。**

違反的是專案自己的第一條：**以可達的程式碼為準。**

修法不是把數字同步回來 —— 同步過的會再漂。而是立規則：

> **只有被檢查強制的數字才寫進 DESIGN；其餘一律指向程式碼。**

### 教訓：mutation 對原碼字串有牙，對 runtime 浮現沒牙

T-044/T-050 兩輪出現同一結構性現象：**「gates 全綠＋mutation 有牙」與「實測完全失效」同時成立**。`grep` 到 `.accessibilityLabel` 只證明字串在檔案裡，對「它有沒有浮現到 AX」零資訊。

規則（p1 裁決）：

> **凡票的目標是 runtime 行為（AX 浮現、實際鍵擊路徑、渲染結果），完工條件只能是實跑探針的結果，不得是 gate／source 結果。** gate 與 mutation 降級為防回歸用途。

§8 的圖標數字沒爛，因為 Checks 會失敗；§2、§3、§4 都爛了，因為沒人守。

### 色彩這輪的教訓

首版 Checks 用**量化前的浮點值**算對比度 → 3.000003 → PASS；實際落成 8-bit → 2.995191 → 使用者看到的顏色不達標。

**斷言必須釘最終 8-bit 顏色，且門檻要留餘裕（採 3.1 而非 3.0）。**踩線的規格會被四捨五入推下去。

### 拿掉危險本身，不是加守衛

一晚三次，正確解法都不是加守衛：

- 文件對程式碼兩份 → 不同步，而是規定「只有被檢查強制的數字才寫進 DESIGN」
- 畫面對 SVG 兩份 → 不是加一致性測試，而是 `ConnectionGeometry` 單一來源
- owner 資料在爆炸半徑裡 → 不是再多備份一次，而是 storage 雔離讓測試根本碰不到

### 修避蔽缺陷時，差點自己寫出一個避蔽缺陷

`writeRecoveryCopy` 的 Bool 被丟掉、toast 只活 2.4 秒後被過期時間戳蓋掉 —— 都是「**stale 數字蓋掉現實**」。

而修它的第一版設計用**單一 enum**，會讓 autosave 失敗默默蓋掉 recovery 失敗 —— 同一個形狀。

**這個形狀連正在盯著它看的人都會再犯。**

### 驗了量得到的，沒驗真正要緊的

- 排程：測了**終止條件**，沒測「叫不叫得醒人」→ 兩次嗚醒失敗（PATH 缺 `/opt/homebrew/bin`）
- cleanup：測了正常路徑，沒測失敗路徑 → `set -u` 展開順序使還原静默跳過
- 狀態訊號：花一整輪驗**縮放不變**，從來沒量它**看不看得見** → 淺色下對畫布僅 1.41

規則：**先問「這件事失敗時，最先失去的是什麼」，再決定驗什麼。**

### 兩個 agent 同時被同一個假設騙過

星標位置：助理從 `offset -10` 推論「多半在卡片外」，主 agent 從描述接受。

實測：包圍盒 18×17 內，畫布 48px、節點填色 45px —— **一半壓在節點上**。

進而證明：畫布 L=0.8620、節點 L=0.1312，對畫布≥3 需 L≤0.2540、對節點≥3 需 L≥0.4935 → **區間為空**。不是調色問題，是幾何問題。

**兩個 agent 都在推論星標應該在哪裡，而不是看它在哪裡。**

### 同一個顏色，三條渲染路徑，三組數字

```
Palette 規格值              #a88208
視窗實拍                    #a88109
ImageRenderer 直接 colorAt   #b79302   ← 連畫布也從 #f1efe7 變 #f5f2ec
```
第三組算出對比 2.615–2.922，看起來是產品不達標。實際是 **ImageRenderer 的 NSImage 是 Display-P3／裝置編碼，被當成 sRGB 算**。

辨識線索：**畫布與星標同方向變亮** —— App 不可能同時改兩個不相干的顏色，但 profile 換算會。

差點做出的錯誤決定：為了迴避一個量錯的 oracle 而把產品色壓暗。

**規則：候選行動是「改產品」時，先確認量具本身。**

另：`ImageRenderer` 不是內部細節 —— **列印與 PNG 匯出都走它**，撤掉 gate 等於使用者看得到的兩條路徑完全沒驗。

### 跨 agent 決策的來源

一次實例：助理在 pane 裡讀到主 agent **尚未送出的推理**，把它當成裁決，鎖進 Task Packet。主 agent 查自己實際送出的訊息，發現那條裁決從未存在。

**規則：只有實際送達、帶署名的訊息算決策。**terminal 上可見的思考只算診斷線索。

這是「把『我知道』當『文件裡有』」的鏡像版：**把『對方應該會這樣裁』當成『對方裁了』**。packet 引用一個不存在的授權，比沒有授權更危險 —— 因為它看起來已經被審過。

### 唤醒排程（完工前每次啟動必確認）

owner 規定：**額度用盡時，兩個 pane 於上次唤醒後 5h10m 再啟動**，直到工作完成。

- job：`local.mindflow.relay`（LaunchAgent），腳本 `~/.pi/agent/scripts/mindflow-relay.sh`
- 唤醒方式：**`StartInterval` = 18600 秒（5h10m）**，自載入起算、之後每 5h10m 重複。owner 於 2026-09-01 23:22 要求「從現在重新起算」，首次觸發約 04:32
- 不用固定時刻：固定時刻跨日會漂移，間隔制才精確符合「上次唤醒後 5h10m」
- **不自刪**。舊版是一次性 job，觸發後自毀 —— 2026-09-01 的 05:58–8:13 因此**完全沒有唤醒機制**，若當時額度用盡就斷在那裡
- 檢查：`launchctl list | grep mindflow`
- **自動終止**（兩道，先到先生效）：
  - `touch ~/.pi/agent/scripts/mindflow-relay.done` → 下次觸發時自刪並卸載
  - 逾期日 **2026-09-15** → 自刪，**不需任何人記得**
- 刪除順序固定：**先 `rm` 檔案、最後才 `bootout`** —— bootout 會殺掉自己的行程群組
- 路徑可用環境變數覆寫（`MF_PLIST` 等），**目的是讓毀滅性路徑測得到**。四條行為測試（標記、未到期、逾期、拿掉守衛的陰性對照）均通過
- 這套測試抳到一個真 bug：`$DEADLINE` 後紧接全形括號，macOS bash 將多位元組字元併入變數名 → unbound variable。**它只在逾期路徑發作，正常運作幾週都不會出現**
- log 上限 200 行

### 已識別、未開工

- **狀態訊號縮放不變**：指示器 / 選取 / 重掛 / search / batch / hover 的 lineWidth **與外推 padding** 全在被縮放的內容樹裡。fit 0.25 時指示器只剩 0.75 邏輯 px，契約「看到=排序」在大地圖縮小檢視時失效 —— **而地圖越大越需要排序**
- TabStore（staging+commit）、import bytes/node/depth 上限、icon、其餘視覺項
- **symlink 檢查名不副實**：現行以 `fileExists` 判定「是否為真實目錄」，但它會跟隨 symlink。排入後續資安路徑票，**不混進 TabStore 這輪**
