#!/usr/bin/env bash
# U15 (Walker/p6): T-043 toolbar as the user actually sees it (AX, not source text).
#
# T-043 moved 11 equal-weight toolbar buttons down to 3 primaries plus a native
# ellipsis menu. The source-level check (t043Check) reads the declaration; this
# probe reads the runtime window:
#   1. the toolbar exposes exactly the three primary capabilities
#      (子主題 / 兄弟主題 / 檢閱器) and nothing else except the overflow menu;
#   2. the overflow is one native pop-up menu titled "More";
#   3. every collapsed capability is findable inside that menu;
#   4. Delete sits last behind a divider;
#   5. the conditional 取消聚焦 entry appears once a branch is focused.
# Positive control: the same AX path must find a toolbar item that is *not*
# there — the probe proves the channel can say "absent" before trusting it.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
activate(){
  osascript -e 'tell application "Bough" to activate' >/dev/null 2>&1; sleep 0.3
  local front
  front=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  if [[ "$front" != "Bough" ]]; then
    echo "ABORT: instrument failure — frontmost='${front:-unknown}', AX/menu would be read elsewhere" >&2
    uit_quit_flush >/dev/null 2>&1
    exit 70
  fi
}

toolbar_tsv(){ # role<TAB>description<TAB>title, one line per toolbar control
  osascript <<'AS' 2>/dev/null
tell application "System Events" to tell (first process whose name is "Bough")
  set tabCh to character id 9
  set w to first window whose name contains " – "
  set tb to toolbar 1 of w
  set out to {}
  repeat with e in (UI elements of tb)
    set r to ""
    set d to ""
    try
      set r to role of e as text
    end try
    try
      set d to description of e as text
    end try
    if r is "AXGroup" then
      repeat with c in (UI elements of e)
        set cr to ""
        set cd to ""
        set ct to ""
        try
          set cr to role of c as text
        end try
        try
          set cd to description of c as text
        end try
        try
          set ct to title of c as text
        end try
        set end of out to cr & tabCh & cd & tabCh & ct
      end repeat
    else
      set end of out to r & tabCh & d & tabCh
    end if
  end repeat
  set AppleScript's text item delimiters to linefeed
  return out as text
end tell
AS
}

more_menu_tsv(){ # press the More pop-up, dump items and one level of submenus
  osascript <<'AS' 2>/dev/null
tell application "System Events" to tell (first process whose name is "Bough")
  set tabCh to character id 9
  set w to first window whose name contains " – "
  set tb to toolbar 1 of w
  set pop to missing value
  repeat with e in (UI elements of tb)
    try
      if (role of e as text) is "AXPopUpButton" then set pop to e
      if (role of e as text) is "AXGroup" then
        repeat with c in (UI elements of e)
          if (role of c as text) is "AXPopUpButton" then set pop to c
        end repeat
      end if
    end try
  end repeat
  if pop is missing value then return "ERROR no popup"
  click pop
  delay 0.7
  set out to {}
  repeat with mi in (menu items of menu 1 of pop)
    set itemTitle to ""
    try
      set itemTitle to title of mi as text
    end try
    set itemEnabled to ""
    try
      set itemEnabled to (enabled of mi as text)
    end try
    set end of out to "item" & tabCh & itemTitle & tabCh & itemEnabled
    try
      repeat with subItem in (menu items of menu 1 of mi)
        set subTitle to ""
        try
          set subTitle to title of subItem as text
        end try
        set end of out to "sub" & tabCh & itemTitle & tabCh & subTitle
      end repeat
    end try
  end repeat
  key code 53
  set AppleScript's text item delimiters to linefeed
  return out as text
end tell
AS
}

uit_prepare_storage >/dev/null || exit 1
uit_launch small-20 30 >/dev/null || { echo "ABORT launch"; exit 1; }
sleep 1.2; uit_ime_switch; activate

echo "=== 1. main row composition (AXToolbar) ==="
TB=$(toolbar_tsv)
echo "$TB" | sed 's/^/      /'
[[ -n "$TB" ]] && ok "toolbar channel readable" || bad "toolbar channel returned nothing"

# Positive control: the channel must report absence for a label that is not there.
if grep -q "絕對不存在的主題" <<<"$TB"; then
  bad "positive control: channel claims an absent label exists"
else
  ok "positive control: channel reports absent labels as absent"
fi

caps=$(awk -F'\t' '$1=="AXButton" && ($2=="子主題" || $2=="兄弟主題") {print $2}
                  $1=="AXCheckBox" {print "檢閱器"}' <<<"$TB" | sort | tr '\n' ' ')
expected_caps=$(printf '%s\n' 子主題 兄弟主題 檢閱器 | sort | tr '\n' ' ')
[[ "$caps" == "$expected_caps" ]] && ok "main row exposes exactly 子主題 / 兄弟主題 / 檢閱器" \
  || bad "main row capabilities are [${caps% }] (expected 子主題 兄弟主題 檢閱器)"

pops=$(awk -F'\t' '$1=="AXPopUpButton" {print $3}' <<<"$TB" | tr '\n' ' ')
[[ "$pops" == "More " ]] && ok "the only other main-row control is the native More menu" \
  || bad "unexpected main-row control(s): [${pops% }]"

cap_count=$(awk -F'\t' '($1=="AXButton" && ($2=="子主題" || $2=="兄弟主題")) || $1=="AXCheckBox" {n++} END{print n+0}' <<<"$TB")
extra=$(awk -F'\t' '!(($1=="AXButton" && ($2=="子主題" || $2=="兄弟主題")) || $1=="AXCheckBox" || ($1=="AXPopUpButton" && $3=="More")) {print $1":"$2":"$3}' <<<"$TB")
echo "      measured: capability controls=$cap_count, overflow=$pops, other=[${extra:-none}]"
[[ "$cap_count" -eq 3 ]] && ok "主列按鈕數 = 3 capabilities" \
  || bad "主列 capability count is $cap_count (expected 3)"
[[ -z "$extra" ]] && ok "no stray controls in the main row" || bad "stray main-row controls: $extra"

echo "=== 2. every collapsed capability is findable in the More menu ==="
MENU=$(more_menu_tsv)
if [[ "$MENU" == ERROR* || -z "$MENU" ]]; then bad "More menu did not open/read: ${MENU:-empty}"
else
  echo "$MENU" | sed 's/^/      /'
  menu_has(){ # item -> title is field 2; sub -> sub-title is field 3
    awk -F'\t' -v kind="$1" -v want="$2" \
      '(kind=="item" && $1=="item" && $2==want) || (kind=="sub" && $1=="sub" && $3==want) {found=1} END{exit !found}' <<<"$MENU"; }
  want_items=("符合視窗" "全部展開" "全部收合" "展開至" "版面" "複製 MD" "刪除")
  for label in "${want_items[@]}"; do
    menu_has item "$label" && ok "More contains 「${label}」" || bad "More is missing 「${label}」"
  done
  want_subs=("顯示到第 1 層" "顯示到第 2 層" "顯示到第 3 層" "顯示到第 4 層"
             "邏輯圖（右展）" "平衡圖（左右）" "魚骨圖" "括號圖" "回到自動排列")
  for label in "${want_subs[@]}"; do
    menu_has sub "$label" && ok "More 子選單 contains 「${label}」" || bad "More 子選單 is missing 「${label}」"
  done

  last=$(awk -F'\t' '$1=="item" {t=$2} END{print t}' <<<"$MENU")
  [[ "$last" == "刪除" ]] && ok "Delete is the last More item" || bad "last More item is 「${last}」"
  prev=$(awk -F'\t' '$1=="item" {n++; t[n]=$2} END{print t[n-1]}' <<<"$MENU")
  [[ -z "$prev" ]] && ok "a divider separates Delete from the items above" \
    || bad "item above Delete is 「${prev}」 (expected divider)"

  menu_has item "刪除" && ok "Delete is reachable from the toolbar" || bad "Delete missing from More"
fi

echo "=== 3. conditional entry: focus a branch, then 取消聚焦 must appear ==="
activate
r=$(uit_context_menu N-0005 "聚焦此分支"); sleep 0.8
if [[ "$r" != "pressed" ]]; then bad "could not focus a branch (ctx='$r') — conditional phase uninterpretable"
else
  MENU2=$(more_menu_tsv)
  if [[ "$MENU2" == ERROR* || -z "$MENU2" ]]; then bad "More menu did not open/read while focused"
  else
    awk -F'\t' '$1=="item" && $2=="取消聚焦" {found=1} END{exit !found}' <<<"$MENU2" \
      && ok "取消聚焦 appears once a branch is focused" \
      || bad "取消聚焦 missing while focused"
  fi
  activate; uit_key 53; sleep 0.4   # leave focus mode (Esc clears focusBranchID)
fi

echo
echo "U15 RESULT: PASS=$PASS FAIL=$FAIL"
uit_quit_flush >/dev/null
[[ "$FAIL" -eq 0 ]]
