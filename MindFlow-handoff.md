# MindFlow 交接文件 — Handoff

> 供下一位 agent 無縫接手。既有細節都在專案文件裡，這裡只寫「狀態、方向、下一步」，
> 不重複文件內容，一律引用路徑。

## 一、目前在什麼狀態

- 專案路徑：`/Users/haichiu/Documents/AgentHub/projects/mindflow`
- 最新 commit：`v26.0` — "pan/zoom consistency check + comprehensive regression suite; 429 checks pass"
- Git 工作樹乾淨、無未提交變更；tag 只到 v9.9（v26 未打 tag，反映凍結令後停止打 tag）
- 桌面交付物：`~/Desktop/MindFlow.app`（執行中），另有舊版 DMG（v12.8…v25.0）
- 建置指令：`swift build`、`swift run MindFlow`、`swift run MindFlowChecks`、`bash scripts/verify.sh`、`bash scripts/package.sh VERSION`、`bash scripts/make-dmg.sh VERSION`

## 二、Owner 最新目標（凍結令）

Owner 在 v20.x 之後下達凍結：**禁止新增功能、版本、tag、commit、打包或全面回歸**。唯一任務只限使用者回報的「**基本點擊與移動不順**」，且只驗證兩個可證偽假設 H1 / H2。泛用「繼續」僅代表重試、不代表授權新工作。

→ 接手時**不要**擅自加功能、版本號、tag、打包、或跑完整回歸。

## 三、已觀察證據 / 已反證假設（H1/H2 已完成）

| 假設 | 結論 | 證據 |
|---|---|---|
| H1：點選會觸發 revealNode 造成延遲 | **已反證（REJECT）** | revealNode 已被 `lastNavWasKeyboard` 守門，滑鼠點擊不觸發 |
| H2：單擊卡頓來自手勢疊疊 | **已確認（CONFIRMED）+ 已修** | NodeView 上 `.onTapGesture(count:2)` 造成單擊約 300ms 延遲；移除後改為「選取節點再點一下」進入編輯 |

已落地之修復（見 git log）：
- 移除 `.onTapGesture(count: 2)`（`74b3a45`，H2 關鍵修復）
- DragGesture minDistance 4→8pt（`56e59ed`，減少點擊時誤拖）
- 滾輪空間過濾：游標在畫布外時滾輪不平移地圖（`dbb2045`、`bbe550b`），防止檢閱器捲動拖動畫布

## 四、目前成品最大缺口

**人機驗收缺口**：互動修復（去雙擊 / min 8pt / 滾輪門控）已部署，但**需要真實人手＋眼睛**去 `打開 MindFlow → 點節點 → 拖曳 → 捲動檢閱器` 做接受測試。這是唯一卡點——不是程式 bug，而是「是否真的變順」只有 Owner 能判斷。

**可自主驗證之待辦（非功能、屬維持品質）**：
- README.md 仍有過時「改文字：連點兩下」字樣（實際已改為「選取後再點一下」）。git log `bbe550b` 曾清理 help sheet / tab bar 的雙擊字眼，但 README 表格列殘留未清淨 → 可安全修正，不改行為、不觸及凍結範圍。

## 五、唯一下一個實驗 / 待驗收問題

- **待驗收問題**（需 Owner 手眼）：「移除雙擊 + min 8pt + 滾輪門控後，點擊與移動是否還是不順？」若仍不順 → 請使用者描述「特定操作＋感受」（例如：點哪個節點、拖到哪、感覺是『反應慢』還是『會誤動』），再據此診斷下一輪。
- **自主可推進項**：僅上述 README 過時字眼修正（純文件、不改行為）。除此之外，依凍結令**不建議**做任何功能／版本／打包改動。

## 六、建議 skills（下一位 agent 請呼叫）

- `.agents/skills/mindflow-core-loop/SKILL.md` — 證據導向核心循環；無紅訊號不擅自改動，本案全程遵循此原則
- `projects/mindflow/skills/swiftui-pro/SKILL.md` — SwiftUI/Swift 的互動與效能寫法
- `projects/mindflow/skills/appllama-app-design-skill/SKILL.md` — 非技術使用者導向的 UX/可發現性設計

## 七、引用之既有文件（不在此複製內容）

- 資料格式＋合約測試：`projects/mindflow/docs/FORMAT.md`
- 里程碑與候選功能：`projects/mindflow/docs/ROADMAP.md`
- 結構化驗收清單：`projects/mindflow/docs/TESTING.md`
- 下載與上手：`projects/mindflow/README.md`
- 更新日誌：`projects/mindflow/CHANGELOG.md`
- 只讀專案政策：`/Users/haichiu/.pi/agent/AGENTS.md`

## 八、接手者注意

- 維持「證據支持才保留改動」節奏；版本、tag、打包、廣泛回歸**留到 Owner 要求交付時**。
- 若 Owner 在線並提出新方向，以 Owner 指示優先；若離線，停在「待驗收問題」並記錄最能推進一步，不要空轉。
- 所有驗證與建置用上列命令，無需 Xcode（僅 Command Line Tools，SwiftPM executable）。
