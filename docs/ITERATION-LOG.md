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

### 色彩這輪的教訓

首版 Checks 用**量化前的浮點值**算對比度 → 3.000003 → PASS；實際落成 8-bit → 2.995191 → 使用者看到的顏色不達標。

**斷言必須釘最終 8-bit 顏色，且門檻要留餘裕（採 3.1 而非 3.0）。**踩線的規格會被四捨五入推下去。

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
