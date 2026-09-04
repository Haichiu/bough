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
| 16 | T-044 分頁標題（16-grapheme、active live、最終字串唯一）＋T-049 節點層建立＋D2 吞字修復＋T-050 驗收管道 |
| 17 | T-047 icon 字形重設計（方向 A 卡片樹＋強制破對稱）| `da2aaa2` glyph：root 填充卡（≥2.1×）＋兩張描邊子卡（不互為鏡像）＋圓角肘線；`a2128e4` gates（p1 修正版，渲染完成品上量）：非實心（16px fill=0.6042 ≤ 0.70；錨點舊=0.469 過／實心≈0.9 拒）＋flip-mismatch ≥0.10 全 10 slots（本 glyph 最低 0.2055@64px；**舊 icon 0.000 被拒＝陰性對照**）；內點 ±1 design unit 全綠；mutation 鏡像子卡／填實心各 rc=1 首敗；掃描先斷言、對比≥3.0、光學置中不變全過。**美學裁決（p1，2026-09-03）：accept。**`/tmp/iconsym` 獨立實測：flip-mismatch 新 0.184–0.292（四 band，門檻 0.10）、fill 0.412–0.495（門檻 0.70）；舊 icon 全 band 0.000 被拒——陰性對照實測。64px ASCII 判讀「讀得出卡片樹而非抽象網路圖」。**已知取捨**：16px 是最弱 band——描邊子卡在該尺寸已填成實面，root 填充 vs 子卡描邊的層級感知不到（墨量 30→40、bbox 8x8→8x11；結構未崩解，blobs 皆 1）。**未行使選項**：小 band 改填充子卡——原樣記錄、現在不做；16px 只出現在 Finder 列表與選單，Dock/切換器 ≥64px；owner 看了說 16px 不行再行使| `da2aaa2` `a2128e4` | resolver headless 全綠＋12/14 boundary mutation 有牙；GUI：p1 量 AXIdentifier 與 resolver 輸出在**量出的 reverse-mtime 順序**上逐字相等（截斷後才碰撞、使用者字串被讓開、8+1+7=16），陰性對照實測；T-049 四路徑 node-level＋方向鍵導航（以取代目標反推選取）PASS；D2 吞字（`6d74a8a` live-store seed）雙情境 PASS；T-050 原目標降級 backlog（實測 `.accessibilityLabel` 在普通內容區不產生屬性），identifier 僅驗收管道 | `7f3404a` `7056f10` `68bd471` `6d74a8a` `a6ea038` |
| 18 | T-051 輕量資安（S1 真洞；S2/S3 先量再決，兩項結論＝不加守衛）| S1 `ec72b74`+`0e702cc`：openURL scheme allowlist（字串切法之外，**對 NSWorkspace 實收的 URL 物件再斷言一次**；13 條 Foundation 實測行為釘死防解析器漂移）（http/https/mailto；原則：允許交給瀏覽器/郵件撰寫、拒絕定址本地檔案系統或派給任意 app；大小寫不敏感＋歸一化；mutation 拿掉 allowlist 首敗）；S2 `a1f5575`：**實驗證據**——TabStore staging 存檔不 open symlink（target 331→331 identical）、`Data.write(.atomic)` 以 rename 取代連結本身（349→349 identical）、iCloud 式目錄 symlink 本就 bounded 失敗 → **不加守衛**，fixture＋行為記錄即交付；S3 `6c7d060`：外部實體與 billion-laughs 均 0.00s bounded 拒絕 → fixture＋記錄，不加冗餘守衛。威脅模型：能在 storage 種 symlink 者已有同 user 寫權，防的是同步/解壓/誤建連結，非高危。排除：網路（p1 grep 實驗空）、沙箱簽署、依賴稽核、剪貼簿、加密、同 user 惡意行程 | `ec72b74` `0e702cc` `a1f5575` `6c7d060` |
| 19 | T-047 小 band 子卡填充（owner 裁決行使既有選項）| p6 `32d3378`：`childCard` 改 `filled: band == .small`，small band 兩 slot 實心、mid/large 維持描邊。**p1 獨立驗證**（自寫 oracle，不引用 MindFlowKit、不重用 Checks 程式）：① **收旛控制**——變更前先凍結 10 個 slot 的 SHA256，重建後逐一對比：**恰好 2 個 small slot 變動、其餘 8 個逐位元組相同**；② gates 親跑 ALL CHECKS PASSED，fill 0.6146/0.5966 ≤ 0.70（**門檻未動**）、flip min 0.2055 ≥ 0.10；③ **有牙**——p1 自行把 `filled` 改回 `false`：`FAIL T-047 small fills both child cards on the minimal band`（line 4900）rc=1，還原後全綠；且突變運行重現 fill=0.6042，與變更前基線逐位相符，**證明前後數字歸因正確**；④ **產品判讀**：16px 實際只動 8/256 px（肥描邊在該尺寸本就自併，log 早已預測）；32px 動 18/1024，子卡由**空心環→實心**，是真正可見的改善。owner 螢幕為 Retina 2560x1664，Finder 列表與選單的 16pt 槽實際取用 `icon_16x16@2x.png`（32px）——**改善正好落在 owner 看得到的那個 slot**，1x 的 16px 槽只在非 Retina 螢幕出現 | `32d3378` |
| 20 | Owner 「節點層預設＋Space 才編輯」需求：**實測後確認大部分早已存在，不造新工作**；並量出 Shift+Tab 為死鍵 | p1 建 `scripts/uitest/u9-space-shifttab.sh`（隔離 storage、三相）實跑：**A** Space → `editing='N-0005'`、count 20、0新增、原文完好（findtext=1）→ 進編輯且**不**取代內容；**C 陽性對照** Tab → count 21，證明探針看得見節點建立；**B** Shift+Tab → count 維持 20、無編輯，**因對照組有燒起來所以可解讀** → Shift+Tab 確實未繫結。**p1 自己的假設被實測推翻**：曾推測「Space 是可印字元，會被 D2 type-to-replace 吃掉而把內容變成空白」—— 實際 `case " "` 排在 `default:` 之前，根本到不了。已先標明為假設才驗，未當事實轉述。**本輪刻意不改產品**：Shift+Tab 該綁什麼是語意決定（XMind 本身也沒綁），已開 T-052 附選項、可重用的 `move(id:toParent:)` 與預定驗收，等 Owner 選定。**【事後更正，同輪】p1 在此犯了自己一直在提醒別人的錯**：票裡「XMind 本身也沒綁」一句**未經查證即當作事實寫下**。XMind 官方指南明載 "press Tab to indent, press Shift + Tab to outdent"（<https://xmind.com/user-guide/outliner-new>）。因此本題**從來不是 Owner 的裁決題**——專案既有的 XMind parity 預設早已推導出答案。Owner 指出後 p1 查證、更正 T-052 並定案為 outdent，派 p6 實作。教訓：**「預設規則已經涵蓋的問題，不該被升級成裁決題」，而未查證的斷言就是製造假裁決題的來源**。交付物＝實測證據＋可重跑的回歸探針（Space 行為之前完全無人守） | `u9` probe |
| 21 | T-052 Shift+Tab = outdent 落地並**獨立驗證**；同時修掉 p1 自己 u9 的弱斷言 | p6 `9e25e56`：`promote(id:)` 只做三道守衛（有父、父非 root、有祖父）後轉呼叫既有 `move(id:toParent:)`，註解明寫 "no new tree surgery"；`KeyboardMonitor` 同時接受 back-tab 位元組 `\u{19}` 與帶 `.shift` 的 `\t`，兩種 responder chain 拼法都路由到 promote。**p1 獨立驗證刻意不重跑 u9**——u9 在同一個 commit 裡被實作者大改 158 行，**與被測物同批出貨的 oracle 不是對照組**；改自寫 `u12-outdent-indep.sh`，斷言全部走 `treecompare`：① 基線幾何 `parentof(N-0005)=N-0001`、`parentof(N-0001)=N-0000`、count=20；② **孫節點 Shift+Tab → `parentof(N-0005)=N-0000`（正是原祖父）且 count 仍 20**（移動而非增刪）；③ **root 直接子 Shift+Tab → `parents` 比對完全相同**，no-op 成立；④ **陽性對照 Tab → count 21**。對照第一次是 **FAIL**，原因是 p1 自己的 harness bug（把 `'uit_key 48'` 當單一命令名傳給 `"$3"`）——**沒有把「三條實質斷言已過」拿來當作可以略過對照的理由**，修成 `tab_key()` 包裝後重跑才收案。gates 親跑 `ALL CHECKS PASSED` / `ALL GREEN`，含 5 條 T-052 模型層檢查。**同輪的自我更正**：worker p7 回報「Space 會吞掉節點文字」並宣稱有位元組證明，與 row 20 結論相反。查證後兩件事同時成立——**該回報是錯的，但它揭露了 p1 的 oracle 真的有洞**：u9 用 `findtext` 子字串比對，`N-0005` 與 `N-0005 ` 無法區分，若 Space 真的插入字元也照樣 PASS。新增 `u11-space-exact.sh` 改為逐位元組相等，並加**陽性對照（字母 x）**：Space 後儲存文字 `'N-0005'` 與基線完全相同，字母 x 則使該節點不再含 N-0005 → **對照有燒起來，所以「沒變」這個結果可解讀**。教訓：**弱斷言的危險不在它會誤判，而在它讓錯誤的挑戰無法被乾淨地駁回** | `9e25e56` + `u11`/`u12` |

### 這兩輪的教訓：文件漂移比沒文件更危險

主 agent 依 §2 提出字體階層修正案，但 §2 寫的 15/13/12.5 早已不是產品（實為 18/15/13）。那個「4% 塌陷」不存在，**提案若執行會把已可辨識的階層縮小。**

違反的是專案自己的第一條：**以可達的程式碼為準。**

修法不是把數字同步回來 —— 同步過的會再漂。而是立規則：

> **只有被檢查強制的數字才寫進 DESIGN；其餘一律指向程式碼。**

### 教訓：mutation 對原碼字串有牙，對 runtime 浮現沒牙

T-044/T-050 兩輪出現同一結構性現象：**「gates 全綠＋mutation 有牙」與「實測完全失效」同時成立**。`grep` 到 `.accessibilityLabel` 只證明字串在檔案裡，對「它有沒有浮現到 AX」零資訊。

規則（p1 裁決）：

> **凡票的目標是 runtime 行為（AX 浮現、實際鍵擊路徑、渲染結果），完工條件只能是實跑探針的結果，不得是 gate／source 結果。** gate 與 mutation 降級為防回歸用途。

### 教訓：對照組無效，比沒有對照組更貴

T-050 三輪「改→全綠→實測仍空」之後才發現：拿來對照的兩顆工具列按鈕能浮現 label，**不是因為 Label 形狀，而是因為它們在 AXToolbar（NSToolbarItem 由 AppKit 取名）**——這個機制不存在於普通內容區。「跟它們逐字同形」從一開始就不可能成功。

> **對照組必須先驗證「差異軸真的是我們比對的那個軸」，否則二分只是在錯誤的維度上排序。** 共用一部分特徵就假設共用全部，是「把宣稱當事實」的二分版。

### 手法記錄：以「取代目標」反推鍵盤選取

選取本身不暴露在 AX，但**導航後打一個字、看哪個節點的內容被取代**，就能確定讀出選取落在哪個節點（D2 修好後打字可靠，讀數確定）。p1 用這招驗完 T-049 方向鍵導航（Right 進第一子節點、Down 走下一兄弟）。凡「狀態不暴露、但狀態會決定一個可觀察寫入」的場合都可套用。

### 量具規則：閾值二值化必須對賬無閾值結構量測

p1 以 tol=40 的 ASCII 逐像素列 16px icon，抗鋸齒中間調被切掉，子卡看似「斷成一截一截」，差一步把「16px 崩解」當產品缺陷回報——blob 連通性量測（新舊皆單一 blob、新墨量約 2×）擋下來。

> **以閾值二值化做形狀判讀時，必須同時跟一個不依賴閾值的結構量測對賬**（連通元件、墨量、bbox）。「量到的不是以為的東西」第 15 例，第三次自己的量具差點變成對產品的誤判。

同一輪的量具教訓：System Events 的 `description` 回的是 AXRoleDescription（所以全是「button」），不是 AXDescription；SwiftUI `.accessibilityLabel` 寫進後者。量具讀錯欄位，三輪修補全部白做。

### 行為記錄：分頁排序 = reverse mtime（最新在最左）

p1 以五個完全相異標題實測：畫面左→右 = 建檔序反轉。與 T-044 的刻意取捨有交互：**使用者只要重新存檔一個舊分頁，它就會跳到最左，suffix 也可能重算**（suffix 依 session order 分配、刻意不持久化）。不是缺陷，但未寫下的行為三個月後無法與缺陷區分。

結果記錄：`.accessibilityIdentifier` 在普通內容區會浮現 → T-044 的 AX 逐字驗收以 identifier 為管道結案；identifier 是**驗收管道，不是無障礙修復**，分頁對 VoiceOver 依然無名（T-050 原目標降級進 backlog，票內有實測依據）。

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

> **本段只列尚未動工的項目。**凡進度表已收錄的，一律以進度表為準，不在此重述。
> 2026-09-03 p1 清理：舊內容五項中四項早已完工（狀態訊號縮放不變 row 4、TabStore row 5、
> import 上限 row 6、icon rows 7/17/19），第五項 symlink 已由 T-051 S2 實驗裁定不加守衛（`a1f5575`）。
> 這正是本檔自己記的「文件漂移比沒文件更危險」的複發；舊內容原樣保留在 git 歷史。

- **T-045** 聚焦路徑取代底部 breadcrumb（C3）—— 尚未開工；驗收不得依賴 `.accessibilityLabel`（T-050 實測在普通內容區不浮現）
- **T-046** CanvasTransform 去重（`toMap` 兩處定義）—— 尚未開工；無缺陷證據，不順便改 pan/scale
- **T-050 原目標**（分頁真正的 VoiceOver 名稱）—— 已降級 backlog，owner 不用 VoiceOver
