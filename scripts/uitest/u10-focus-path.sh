#!/usr/bin/env bash
# U10 (p1): acceptance oracle for T-045 (focus path replaces the bottom breadcrumb).
#
# The ticket words its acceptance in AX terms, and T-050 proved .accessibilityLabel
# does not surface here, so the channel was demonstrated BEFORE the criteria were
# written. Measured on HEAD e86ee11, fixture small-20, node N-0005 selected:
#
#   * The focus capsule DOES surface:  AXStaticText value = "聚焦：N-0005"
#   * Breadcrumb buttons do NOT expose text: every AXButton has title=missing value
#   * But their POSITIONS are visible: 3 AXButton at y=694, x=653/706/756
#     (bottom-centre, window x=244 w=960 so centre=724), plus 4 unrelated
#     bottom-right controls at y=711..712, x=1039..1156.
#
# So removal is asserted by geometry (the centre row must empty) and the focus
# path by AXStaticText value. The bottom-right controls are a guard: they must
# still be there afterwards, otherwise "the band is gone" was achieved by
# deleting too much.
#
# IMPLEMENTATION CONSTRAINT that follows from the measurement: render each path
# segment as Button { ... } label: { Text(...) }. A Button("string") exposes no
# title to AX, which would leave this oracle blind.
#
# Run before implementing: phase 1 MUST fail (3 crumb buttons present). That
# failure is the proof the probe has teeth.
set -u
cd "$(dirname "$0")"; source ./lib.sh

PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
rich(){ osascript "$(dirname "$0")/axdump-rich.scpt" 2>/dev/null; }

crumb_buttons(){ # AXButtons in the bottom-centre row
  rich | awk -F'\t' -v wy="$1" -v wh="$2" -v wx="$3" -v ww="$4" \
    '$1=="AXButton" && $3 > wy+wh-90 && $2 > wx+0.35*ww && $2 < wx+0.75*ww' | wc -l | tr -d ' '
}
corner_buttons(){ # bottom-right controls, the over-deletion guard
  rich | awk -F'\t' -v wy="$1" -v wh="$2" -v wx="$3" -v ww="$4" \
    '$1=="AXButton" && $3 > wy+wh-90 && $2 > wx+0.78*ww' | wc -l | tr -d ' '
}
# The path is read through accessibilityIdentifier on each segment button, in
# left-to-right order. An earlier pass asserted a single StaticText spelling the
# whole path; because Buttons expose no title, the only way to satisfy that was
# to draw the path a second time as a plain string, and the implementation duly
# did so — the measurement was shaping the product. Identifiers are a test hook,
# not a visible element, so the oracle no longer distorts what it measures.
focus_path(){ rich | awk -F'\t' '$1=="AXButton" && $7 ~ /^focuspath-/ {print $2"\t"$7}' \
  | sort -n | sed 's/^[0-9]*\t//' | sed 's/^focuspath-//' | paste -sd'>' -; }

select_node(){ local d cx cy; d=$(uit_axdump); read -r cx cy <<<"$(uit_node_coords "$d" "$1")"; [[ -z "${cx:-}" ]] && return 1; uit_click "$cx" "$cy"; sleep 0.8; }

uit_prepare_storage >/dev/null || exit 1
uit_launch small-20 30 >/dev/null || { echo "ABORT launch"; exit 1; }
sleep 1.2; uit_ime_switch
read -r wx wy ww wh <<<"$(uit_wingeom)"
select_node N-0005 || { echo "ABORT: node not found"; uit_quit_flush >/dev/null; exit 1; }

echo "=== 1. non-focus + selection: bottom centre row must be empty ==="
c=$(crumb_buttons "$wy" "$wh" "$wx" "$ww")
echo "  crumb-row buttons=$c (was 3 before T-045)"
[[ "$c" -eq 0 ]] && ok "bottom breadcrumb band removed" || bad "still $c buttons in the bottom centre row"

echo "=== 2. guard: bottom-right controls must survive ==="
g=$(corner_buttons "$wy" "$wh" "$wx" "$ww")
echo "  corner buttons=$g (baseline 4)"
[[ "$g" -eq 4 ]] && ok "bottom-right controls intact" || bad "corner controls changed: $g (expected 4) — too much was deleted"

echo "=== 3. selection alone must not produce a path ==="
f=$(focus_path)
[[ -z "$f" ]] && ok "no focus path while merely selecting" || bad "path shown without focus: '$f'"
# Phases 3 and 4 run the same query in two states. Empty here and non-empty there
# is what makes a 'nothing found' result in phase 3 interpretable rather than blind.

echo "=== 4. focus shows a root->focus path ==="
r=$(uit_context_menu N-0005 聚焦此分支); sleep 1.5
osascript -e 'tell application "MindFlow" to activate' >/dev/null 2>&1; sleep 0.6
[[ "$r" == "pressed" ]] || bad "could not enter focus (ctx='$r') — phases 4/5 uninterpretable"
f=$(focus_path); echo "  focus path='$f'"
[[ -n "$f" ]] && ok "focus path observable in AX" || bad "focus path not observable"
[[ "$f" == "N-0000>N-0001>N-0005" ]] && ok "path spells root->focus in order" || bad "path is not root->focus: '$f'"
sc=$(rich | awk -F'\t' '$1=="AXStaticText" && $4 ~ /N-0000.*N-0001/ {n++} END{print n+0}')
[[ "$sc" -eq 0 ]] && ok "path is not also drawn as a duplicate string" || bad "path rendered twice: $sc static text(s) spell the whole path"

echo "=== 5. changing selection must not perturb the path ==="
select_node N-0009 || echo "  (N-0009 not found, skipped)"
f2=$(focus_path); echo "  after selecting elsewhere='$f2'"
[[ "$f2" == "$f" ]] && ok "path is byte-identical after selection change" || bad "path moved with selection: '$f' -> '$f2'"

uit_quit_flush >/dev/null; uit_cleanup_all >/dev/null 2>&1 || true
echo; echo "U10 result: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
