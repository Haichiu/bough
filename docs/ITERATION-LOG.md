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
| 35 | **專案更名為 Bough**；對外文案；GitHub 上線；Owner 當面否決我兩處 UI | （a）MindFlow 撞名：兩款同類 App Store app、兩款 Google Play、五個 GitHub repo、**MINDFLOW DESIGN 有效商標**、巴黎 SecOps 公司。十五個候選逐一查 App Store/GitHub/npm/PyPI/商標，**十四個已被佔用**，其中 Umbel 本身就是心智圖 app、Ramus 是 macOS 圖表建模工具、Taproot 是 AI 筆記層、PureMind 有 ® 商標。Bough 是唯一存活者。（b）**兩個刻意不改**：`Application Support/MindFlow/` 改了會讓改名前的存檔全部打不開；`MindFlowKit` 模組名是使用者看不到的 churn。（c）README 每個對外承諾先驗原始碼才寫：`URLSession` 零命中、`undoLimit=100`、自動儲存實為 **1.5s debounce 而非固定週期**（原手冊寫錯，已改精確）。（d）改名弄壞 UI harness（以程序名比對），37 處 pgrep/pkill/System Events 全數跟進；探針實跑確認新名可驅動。（e）Owner 否決檢閱器標題（`7120dad`，我上一輪自己加的）→ 改 editing bar（星標＋六色填色＋清除）；否決最上面分頁列 → 整條移除，分頁改由「分頁」選單列出（>1 才出現、作用中打勾），能力不減。u21 探針隨需求作廢並記錄，非為過測而刪驗收條件。 | `42d1933` `b1a34d5` |
| 34 | 驗證 p6 的 fill 覆寫模型半邊；派畫布半邊；**發現並修正檢查程式寫入 Owner 真實儲存** | （a）`ad4ad67` 12 條 fill 斷言（往返／寬容解碼／undo-redo／六色白名單／SVG）皆有對照；p1 自做對照：`MapExporter.swift:202` fillOverride 改 nil → 2 條轉紅，證明匯出斷言非只讀既有 colorTag。（b）**缺陷**：`swift run MindFlowChecks` 期間 `~/Library/Application Support/MindFlow/tabs/` 20 個檔案遭整批重寫（時間戳一致）。派 p6 修得 `d9d6ae1`。（c）p1 獨立驗證時**第一版量測器是瞎的**：用 mtime 雜湊，`cp -R` 讓所有檔案落在同一秒，`touch` 對照未轉紅。改用**內容 sha256** 後對照轉紅（03c78ffb→e2507187），再實測跑完檢查前後內容雜湊不變 → 確認修好。Owner 資料無損（皆空白圖，另有 `tabs.owner-20260829` 備份）。 | `d9d6ae1` |
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
| 22 | T-045 聚焦路徑取代底部 breadcrumb；**並修掉「驗收條件把產品扭曲成量具形狀」的缺陷** | 先證明管道再寫條件：票裡的驗收本來是空的（沒人證過 AX 看得到這兩樣東西）。p1 先量：聚焦膠囊的 `Text` **會**浮現為 AXStaticText；底部麵包屑的 `Button("字串")` **title 全為 missing value**，但**位置可見**（中央 y≈694 三個、右下 y≈711 四個縮放控制）。據此寫成 `u10-focus-path.sh`：以**幾何**判定移除、以 AX 判定路徑，並加入**防過度刪除的守衛**（右下四個控制必須存活）；實作前先跑，如期 FAIL=2（有牙）。p6 `6d13535` 實作後探針全綠（PASS=6）、閘門全綠、且 p6 自己跑了陰性對照——**但產品變差了**。p1 不收綠燈就結案，以 AX 幾何實測：`AXStaticText x=284` 是完整字串 `聚焦：N-0000 › N-0001 › N-0005`，**右邊 x=482/539/593/638 又有四個按鈕**——**同一行把路徑畫了兩次**。追因後確認：**這不是實作者精緻，而是 p1 的驗收條件造成的**——條件要求「一個 StaticText 拼出 root→focus」，而 Button 在此 target 不暴露 title，**唯一能滿足的方式就是把路徑再畫一次**；p6 的註解也直白寫明動機。修法：拿掉重複的整串 `Text`（只留模式標籤 `聚焦：`），改在每個段落按鈕上挂 `.accessibilityIdentifier("focuspath-<text>")`，並把 `axdump-rich.scpt` 擴充為讀取 `AXIdentifier`（該管道早經 row 17 實測可用）。重量：`AXStaticText x=284 val=[聚焦：]` —— 重複消失；`focuspath-N-0000/N-0001/N-0005` 依 x 遞增（326/382/437）—— 順序正確。新 oracle 改讀 identifier 並**新增一條斷言：任何 StaticText 再拼出整條路徑就 FAIL**。結果 **PASS=7 FAIL=0**，閘門全綠。**內建對照**：第 3、4 相是同一個查詢在兩個狀態下跑（空 vs 三筆），這才讓第 3 相的「找不到」可解讀。**教訓：一個只能靠新增可見元素才能滿足的驗收條件，會把產品扭曲成量具的形狀。測試掛鉤屬於 AX metadata，不屬於渲染出來的 UI。探針全綠不等於產品正確，這就是視覺裁決者必須親自看畫面的理由** | `6d13535` + `u10`/`identifier` |
| 23 | T-046 CanvasTransform 去重落地（採用 p7 bake 分支）＋**T-053 刪除鍵獨立驗證**；同輪兩次自我推翻 | **T-046**：p7 於 `bake/p7` `e7144f3` 實作，p1 早前已獨立重跑（980 筆 legacy 等價＋2000 筆隨機往返、0 失敗）。本輪 cherry-pick 進 main，唯一衝突在 `MindFlowChecks.swift` 檔尾——**形狀是「雙方各自追加」而非二選一**，解法為保留雙方並替 T-052 區塊補回 `do` 的結尾括號；合併後親跑 `ALL CHECKS PASSED`。**T-053**：p6 `491ed75` 修好 Owner 回報的刪除警告聲，真因是**修飾鍵閘門搶在 delete case 之前 `return event`，事件流進 responder chain → AppKit 播系統警示音**；p6 抽出純函式 `deleteOutcome(for:)` 三態並讓監控器與檢查共用。**p1 獨立驗證刻意不重跑 p6 的 `u13`，也不碰 `deleteOutcome`**——純函式正確不能證明接線走得到它，**而那正是原始 bug 本身**。自寫 `u16-delete-modifiers.sh` 打真實按鍵路徑：控制組（只選取不按鍵）count=20 乾淨；plain ⌫／⌥⌫／⌃⌫／⌦ 皆 count=19 且節點消失 → 五項通過。**⌘⌫ 例外：count 維持 20，完全沒反應**。**未證明的部分照實記錄**：「節點消失」只是「按鍵被認領」的代理指標，**「被別的功能吃掉」與「掉進 AppKit 嗶掉」在文件上完全同形**；p1 試圖用插樁建置記錄監控器實收按鍵來分辨，**失敗**（補丁進了原始碼卻沒進二進位檔，原因未明），故**未宣稱 ⌘⌫ 會嗶**，改以三種可能並列交回 p6，並明講「若是無害的前兩種就回報無需修改，不要為了讓我的探針變綠而去改沒壞的行為」。**自我推翻一**：p1 一度斷言 `scripts/package.sh` 會在建置失敗時默默打包舊二進位檔（因第 6 行 `swift build … | tail -1` 吞掉錯誤）——**這是錯的**，第 3 行 `set -euo pipefail` 使管線失敗即中止；在寫進專案記錄前自查推翻並主動通知 p6 忽略。**自我推翻二**：另一支探針 `u14-flows.sh`（日常流程稽核）實跑時基線在 20 與 21 之間跳動，p1 一度懷疑 `uit_prepare_storage` 漏狀態（若成立則**先前所有探針結論的地基都有問題**）；實測連跑三次皆 count=20、單一檔案 → **地基是穩的**，不穩的是探針自身的點擊與時序。**一支不穩的儀器不得產生「發現」**，故不採信其輸出也不提交。順帶修掉本檔自身的文件漂移：「已識別、未開工」仍列著 T-045（第 22 輪已完成）與 T-046（本輪落地），與本檔自警的「文件漂移比沒文件更危險」相抵觸，一併移除 | `89124ea` + `u16` |
| 24 | **待辦清單稽核：三張「未完成」的票其實早已交付**＋ XMind 差距清單（S4 前置規格） | 起因是一次**真實的誤派工**：p1 依 `tickets/README.md` 把 T-044 分頁標題派給 p6，p6 開工後 p1 才發現 `TabDisplayTitles.swift` 早已存在、`ContentView.swift:387` 已在呼叫、`MindFlowChecks.swift:6182` 已有 12 處守衛——**立即叫停**。順藤摸瓜後確認同一類問題有三張：**T-041**（`StorageFailureKind`、注入式 `recoveryWriter`、四段文案 switch、`MindFlowChecks:5229` 守衛）、**T-042**（`MindFlowChecks:5379` 以**掃描原始碼**斷言 `ContentView.swift` 只剩**恰好一個** `Palette` 參照）、**T-044**。三張都是**實作完成且有守衛，卻兩份檔案都沒記**，所以清單上看起來還沒做。已補上結案記錄（`1f8d20f`）。**本檔自己在第 99 行就警告過這件事**（「T-032–T-036 就是因為只進了 ITERATION-LOG，本檔停在 T-031 而漂開」），這次是**反方向的同一種漂移**。教訓已寫進票裡：**拿到票的第一件事是先去程式碼確認它真的還沒做**。另：逐項實測後確認 **Undo/Redo、搜尋取代、插入父主題、兄弟重排、關聯線、多種結構六項全部早已存在**（六次假設六次落空），功能面真正缺的只有 Boundary 與 Outline。據此寫成 `docs/XMIND-GAP.md`（`5806f4a`）作為 S4 的前置規格，結論是**差距不在功能而在「使用者可調的樣式」根本不存在**（`NodeStyle` 欄位全為 `let` 且由深度推導），故 S4 第一刀應切在**資料模型（節點級 override 並存活於存檔往返）**而非 Theme Editor。檔內**明列未完成的那一半**：票要求的「同一張圖並排視覺比對」未做，p1 影像判讀不可靠，需 Owner 的眼睛 | `1f8d20f` + `5806f4a` |
| 25 | `u17-undo-restores.sh`：**undo 必須完全還原**——先前完全無人守的一條 | undo 是使用者依賴最深、思考最少的機制；**部分還原比沒有 undo 更壞**，因為損壞是靜默的而使用者已經走遠了。六相：基線 / **Tab 陽性對照（count 21）** / Tab+undo / Delete+undo / Tab+undo+redo / undo 越過起點五次。結果 **PASS=5 FAIL=0**，包括「刪除父節點後 undo 需連子樹逐個還原、且 UUID 層級相等」。**本輪的實質內容是兩個 p1 自己的 oracle bug，不是產品缺陷**：① `treecompare identical` **成功時什麼都不印**（exit 0），探針卻去比對字串 `"IDENTICAL"` → 四相全部誤報為回歸；② redo 相拿兩次**不同啟動**的新建節點比 UUID，而新節點每次都是隨機 UUID（只有 fixture 節點是決定性的 `00000000-0000…`），**該斷言本身就無效**，已改為結構斷言（count 21 且 parentof=N-0005）。兩個 bug 都是先假設產品壞掉、實際拿檔案手動重比才拆穿。**標準作業因此不變：探針變紅時，先懷疑儀器。**另一支 `u14-flows.sh`（需逐字輸入）因焦點漂移不可重現，**不採信也不提交**；u17 改為每相只送單一按鍵，這才是本 harness 真正做得到的事 | `u17` |
| 26 | **T-054 分頁 undo 隔離：補上「外洩方向」與「受害者側」的斷言**；並修掉 p1 自己寫進規格文件的假斷言 | 起於一次**錯誤的缺口判定**：p1 grep `inactiveStacks` 在 `MindFlowChecks.swift` 得到 0，判定「per-tab undo 零守衛」。實際上既有守衛叫 `per-tab undo isolates stacks`（:2185）——**搜實作符號而非行為名稱**造成的誤判，本輪第八次同類。誠實比對後確認新增的並非重複：既有那條測**擁有者側**（切回分頁 0 後 undo 還原自己的編輯），未覆蓋的是**外洩方向與受害者側**。新增三條：① **新分頁無自身歷史時按 undo，不得消耗前一分頁的堆疊**（`loadFromSession` 的 `?? ([], [])` 是唯一防線，先前無人守）；② 在他處 undo 後，**另一分頁 `sessions[i].document` 必須原封不動**（既有只驗 active 文件，看不見受害者）；③ redo 同樣分頁隔離。全數 PASS，實作本來就是對的——本輪買的是**保險，不是修復**。防的是本 app 最惡劣的失效：在一個文件按 undo、靜默損壞另一個文件，使用者不會把損壞歸因於切分頁，等發現時正確狀態已離開好幾次編輯。另修 `docs/XMIND-GAP.md`：p1 在第 24 輪寫進去的「功能面還缺 Outline 大綱檢視」**是假的**——`OutlineFlattener.swift` 產生 `OutlineRow`、`ContentView.swift:547` 在用、Inspector 有「大綱」分頁（:401）、另有大綱編號與 `⇧⌘M` 切換。同一句錯誤也躺在 `p1-wake-msg.md` 裡會反覆誤導未來的自己，一併修正（`1432ae8`）。**唯一確認的功能缺口收斂為 Boundary 外框**，且 `Theme.swift` 已預留 `.boundary` 顏色角色而模型與 UI 皆無 | `T-054` |
| 27 | **T-043 重辰：整條移除視窗工具列**（Owner 裁示改寫驗收條件） | 本輪的關鍵不在實作而在**發現驗收條件本身是錯的**。p1 準備實作 T-043（主列精簡至 3 顆）時讀到現況程式碼——**它已經是 3 顆了**，`git log -S` 查出是 `30cca8f`（2026-09-02）就交付的。而 Owner 的「很醜很沒必要」是在那之後說的，代表**他看著已精簡版仍然不滿意**，照原文做完只會交出「滿足字面、沒解決問題」的東西。依既定規則（驗收條件與意圖不符時改條件，不硬幹）回報並給四個選項，Owner 選**整條拿掉**。實作順序是關鍵：**先盤點哪些能力只住在工具列、給它們新家，再拆**。盤點結果四項（符合視窗、檢閱器、展開至 N 層、取消聚焦），其中**檢閱器開關在全產品範圍沒有第二個入口**——直接移除會讓檢閱器永遠打不開。新增於 `CommandMenu("顯示")`：符合視窗 ⌘0、檢閱器 ⌥⌘I、展開至 1–4 層、取消聚焦、全部展開、全部收合；ContentView `.toolbar` 区塊 83 行移除並留下現場註解。Oracle 改寫但**保留並收緊**能力清單：入口只承認 App 選單與畫布右鍵選單這種**使用者點得到**的地方，不再接受內部管線字串（舊版正是這個寬鬆處讓「檢閱器」的風險看不出來）。**兩道守衛互補的實例**：`verify.sh` 抓到 p1 新 oracle 漏掉的事——`expandAll`／`collapseAll` 成為孤兒 API，因為 p1 誤把選單裡的「全部收合／展開」***切換***當成那兩個獨立命令的入口（切換表達不了「已部分展開時全部展開」）；已補入口並把 oracle 改成不接受切換。閘門：MindFlowChecks ALL PASSED、verify.sh ALL GREEN。**Runtime 實測**：打包後 AX 掃描真實視窗，子主題／兄弟主題／檢閱器／更多／ellipsis **全數零命中**。另自記一筆：p1 在 payload 裡用了 `\uXXXX` 逃逸寫 Swift，造成字面 `\u5b50` 編譯失敗——**違反了自己訂下的規則（payload 內 Unicode 必須是真字元）** | `T-043` |
| 33 | 結案 T-055；快捷鍵交叉稽核審結（**無缺陷**）；驗證 Boundary v1 單元檢查到不了的那一半 | （a）**T-055 結案 PASS=4 FAIL=0**。u19 的陽性對照之前不穩，原因是 `canvas_hex` 拍整螢幕再依視窗座標裁切，**却沒檢查誰在最上面**；有一次量到的是 Ghostty 的 `#282c34`。現在每次取樣前重新 activate 並**驗證** frontmost 確實是 MindFlow，失敗回傳 `NOTFRONT` 由呼叫端報 `INSTRUMENT:`——哨兵值不得拿去跟顏色比對，否則會把儀器故障報成產品失敗。另修正票上兩個錯：期望值寫的是淺色外觀的 `#f2efe7`，而系統在深色模式（正確為 `#101819`）；`screencapture` 會做色彩描述檔轉換使各通道位移約 2，因此不能用字串相等比對。（b）**快捷鍵交叉稽核審結：沒有缺陷，不需修。** 我先前列出 7 個「選單與監聽器重複宣告」的鍵（⌘z ⌘d ⌘r ⇧⌘m ⌥⌘f ⌥⌘p ⌥⌘/）並懷疑會雙重觸發。實際不會：`KeyboardMonitor.swift:360` 命中後 `return nil` 將事件消費，選單 action 不會再跑；而那些選單列本身就**委派回 `KeyboardMonitor.performCoreShortcut`**，是同一份真相來源（⌘z 直呼 `vm.undo()` 語意等同）。**記下來是為了不讓未來的 session 再查一遍**。（c）**Boundary v1 GUI 驗證 PASS=5 FAIL=0**（`u20-boundary-gui.sh`）。單元檢查能證資料正確，證不了 ⇧⌘B 有沒有送達 app、畫布有沒有畫出東西，因此用**兩個必須一致的獨立 oracle**：視窗區域的像素差異、以及存檔裡的外框數量。結果：主題選單有「加入外框」、⇧⌘B 使畫布變動 1.2%（雜訊底為 0）、存檔含**恰好一筆**外框且錮定在被選節點的 UUID。另截圖用眼睛確認：框確實圈住 N-0002 連同它四個子節點，不是隨便一個矩形。（d）**本輪兩次紅燈全是我的儀器壞掉，不是 p6 的程式**：差分器用 `grep -oE '^[0-9]+'` 讀 ImageMagick 的 `1.04807e+08`，**只抳到開頭那個 `1`**，於是回報「什麼都沒畫」；功能 oracle 找 `*.json`，但文件實際存成 `*.mindmap`，於是回報「沒有存檔」。**兩次都是對照組先亮紅燈把我擋下來**；已改用尺度無關的正規化 RMSE，且門檻以「閒置雜訊×10」**自校準**而非寫死常數。（e）審過 p6 的 `docs/FORMAT.md` 並核准：每條行為都附檢查名稱，三處沒有檢查的地方它主動標「未驗證」 | `c788273` |
| 32 | 審 p6 的 Boundary 提案；**修掉我自己兩個錯誤**；寫好待解鎖的探針 | （a）**第九個假宣稱，而且是會自我複製的那種**：p6 指出「`Theme.swift` 已預留 `.boundary` 顏色角色」是錯的，我複查後確認：那是 `private enum GamutMapping { case step; case boundary }` 的 case，色域映射策略而已。該錯誤同時寫在 `docs/XMIND-GAP.md` **與喚醒訊息**裡，**每次喚醒都會把它複製到下一個工作階段**；兩處均已修正。外框是從零開始，沒有任何預留槽位。（b）提案審查**通過**：它的核心是語意收窄（XMind 沒有跨父節點的任意成員集合），因此 D1 採**錨點 `rootID` 而非成員集合**——能推導就不存，使不一致狀態變成不可表達。我用**完全不同的管道**（XMind 官方使用指南）獨立確認：「topics from different branches will each have their own boundary」——結論一致，順帶抓到官方快捷鍵 `⇧⌘B` 可供 parity 沿用。（c）**我第二個錯：用壞掉的儀器公開質疑了 worker 的證據**。我宣稱本機找不到 `.asar`、無法重現 p6 的量測，並把這個懷疑寫進提案。實際上目錄名是 `Xmind.app`（小寫 m）而我用 `XMind*.app`，**bash 的 pattern matching 一律區分大小寫，與檔案系統是否區分無關**——假陰性。以正確路徑重 grep **完整複現** p6 的字串，已公開撤回並告知 p6。**「探針報找不到時先懷疑探針」這條規則對我自己也適用，這次我沒遵守。** （d）寫好 `u19-theme-repaint.sh`（**尚未執行**，鎖屏中），以「視窗區域眾數顏色」當畫布底色以免取樣點壓到節點。（e）確認**匯出會自動跟隨主題**（匯出用 `Palette.light`，而它解析至當前主題），加斷言鎖住這個耦合。（f）退役兩個過期產物（p4 的交接文件、不穩的 u14）至 `/tmp`，可逆不刪 | `Xmind.app` |
| 31 | 極簡主題補上留白；驗證 p6 的 `⌘/` 修正；**一次協作碰撞的教訓** | （a）極簡主題原本只拿掉填色與邊框，反而比經典更擁擠——盒子消失後，內距就不再是裝飾而是**唯一撐開節點的東西**。新增 `insetScale`（極簡 1.3、墨黑 1.15）並斷言「極簡內距必須大於經典」。（b）驗證 p6 的 `c0280fb`：它抽出 `performBranchFold`，以嚴格的 `modifiers == [.command]` 排除 shift，回傳 false 讓事件落到選單快捷鍵；**做了陽性對照**（把守衛改成 `contains(.command)` → 3 條斷言轉紅），確認其檢查有咬合力；副作用是 `⌥⌘/` 也一併被放行到選單，剛好修掉第二個死鍵。（c）**教訓：派工時我列了禁碰檔清單，却漏掉 `MindFlowChecks.swift` 這個共用檔**。結果：我的 `git add -u` 曾暫存 p6 的半成品；p6 的 commit 則夾帶了我的斷言而實作還在我本地，**使那個 commit 單獨拿出來是紅的**；已立即補交實作恢復一致。共用工作目錄時，**檔案所有權必須連測試檔一起切**。閘門兩道全綠 | `insetScale` |
| 30 | **可切換主題系統（Owner 需求）**：新增「極簡」等四套主題 | Owner 要求加極簡風格並能切換。先上網查證極簡設計原則（NN/g 等）：**層級來自留白與字級，而非邊框與色塊**、中性色配單一強調。因此主題**不能只換顏色**，否則「極簡」仍是一堆方框。架構：一個主題 = **accent + 中性色 + 節點形態**；六條分支色沜用現有的 OKLCh 色相旋轉導出，**新主題免費繼承色域映射與暗底對比度下限**。`.classic` 逐位元還原舊色盤，所以全部舊色彩斷言仍描述真實出貨狀態。**刻意不讓 statusHighlight 隨主題變色**（標記徽章是語意訊號），只重解明度以維持可讀。持久化沿用 `showOutlineNumbers` 的既有慣例；啟動套用寫在 **app target 而非 kit**，以免 MindFlowChecks 開始依賴開發者選了哪個主題。斷言含：四主題畫布與 accent 兩兩相異、**每一主題明暗兩態的主次文字都過 WCAG 4.5:1**、徽章色相不漂移、快取不會因切換而損壞、rawValue 可往返。已做陽性對照（故意改錯會紅）。**誠實聲明：畫布是否真的重繪尚未實測** —— 探針失敗時先建對照組（HEAD 原始碼另建一份），**對照組同樣零視窗**，再查出 `CGSSessionScreenIsLocked = Yes`：**螢幕鎖定時 GUI 探針全都無效**，與本次改動無關。閘門兩道全綠 | 主題選單 |
| 29 | **修掉 p1 自己在上一輪引入的假快捷鍵**＋說明面板補上 ⌥⌘I | 從一個「完成度」問題出發：工具列拆掉後可發現性下降，`⌘/` 說明面板是使用者唯一的快捷鍵地圖，所以去檢查它有沒有收錄新鍵。**結果發現的不是漏寫，而是 p1 自己前一輪造的缺陷**：說明面板第 21 列已有 `("⌘+ / ⌘- / ⌘0", "縮放")`——**⌘0 早就被佔用**，而 p1 把「符合視窗」也綁上 ⌘0。進一步量測才是重點：`KeyboardMonitor:362` 的 `case "0"` post `.mindFlowReset` 後 `return nil`（消化），且該 `switch` **不在 `commandOnly` 保護下**；local monitor 又先於 menu key equivalent 執行，**所以那個選單快捷鍵永遠不會觸發**——選單上會顯示一個看似可用、按下去却做別件事的鍵，比不綁更壞。並已確認兩者是**不同能力**：`.mindFlowReset` 是 `scale=1, pan=.zero`（回 100% 並置中），`.mindFlowFit` 是 `fitToView`（縮放至整張圖）。修法：符合視窗**不綁快捷鍵**，保留選單列與畫布右鍵「全圖」兩個入口；oracle 也反過來**斷言它不得宣稱這個鍵**，以免未來有人為了「补上快捷鍵」又裝回去。另把實測確認可用的 ⌥⌘I（檢閱器）寫進說明面板。**教訓：新增快捷鍵前必須先查監聽器有沒有先消化它；「程式碼裡寫了這個鍵」跟「這個鍵會動」是兩件事。** 閘門兩道全綠 | `⌥⌘I` |

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

- **T-050 原目標**（分頁真正的 VoiceOver 名稱）—— 已降級 backlog，owner 不用 VoiceOver
