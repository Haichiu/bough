#!/usr/bin/env bash
# U11 (p1): does Space mutate the node's text, byte for byte?
#
# Why this exists: u9 asserted only that the substring "N-0005" was still
# present after Space. That assertion cannot distinguish "N-0005" from
# "N-0005 " or " N-0005", so it would pass even if Space injected a character.
# A worker reported the opposite conclusion from u9's, so the weak assertion is
# replaced here with exact equality against the pre-keystroke text.
#
# Controls: the same sequence is run with a printable letter, which is EXPECTED
# to replace the text (type-to-replace). If the letter case does not show a
# change, the harness cannot see text mutations at all and the Space result is
# uninterpretable.
set -u
cd "$(dirname "$0")"; source ./lib.sh

TARGET=N-0005

node_text(){ # $1 = storage root; prints the exact text of every node matching N-0005*
  python3 - "$1" <<'PY'
import json,sys,os,glob
root=sys.argv[1]
for p in glob.glob(os.path.join(root,'**','*.mindmap'),recursive=True):
    try: d=json.load(open(p))
    except Exception: continue
    out=[]
    def walk(n):
        if isinstance(n,dict):
            t=n.get('text')
            if isinstance(t,str) and 'N-0005' in t.replace(' ',''):
                out.append(repr(t))
            for c in (n.get('children') or []): walk(c)
    walk(d.get('root') if isinstance(d,dict) else d)
    if out: print(os.path.basename(p), ' '.join(out))
PY
}

run_case(){ # $1 = label, $2 = keycode to send after selecting the node
  local label="$1" code="$2"
  uit_prepare_storage >/dev/null || return 1
  uit_launch small-20 30 >/dev/null || { echo "$label ABORT launch"; return 1; }
  sleep 1.0; uit_ime_switch
  local d cx cy
  d=$(uit_axdump); read -r cx cy <<<"$(uit_node_coords "$d" "$TARGET")"
  [[ -z "${cx:-}" ]] && { echo "$label ABORT: target not found"; uit_quit_flush; return 1; }
  uit_click "$cx" "$cy"; sleep 0.8
  uit_key "$code"; sleep 0.9
  local editing; editing=$(uit_canvas_editing)
  uit_key 36   # Return: commit whatever the editor holds
  sleep 0.9
  uit_quit_flush >/dev/null; sleep 1.2
  echo "$label editing_after_key='$editing'"
  echo "$label stored: $(node_text "$MINDFLOW_STORAGE_ROOT" | tr '\n' ' ')"
  uit_cleanup_all >/dev/null 2>&1 || true
}

echo "=== BASELINE: no keystroke, just select and quit ==="
run_case BASELINE 53   # Esc: selects then unwinds, must not alter text
echo
echo "=== SPACE (keycode 49): the behaviour under dispute ==="
run_case SPACE 49
echo
echo "=== CONTROL letter x (keycode 7): type-to-replace, MUST show a change ==="
run_case LETTER 7
echo
echo "Read: if LETTER shows no change the instrument is blind and SPACE proves nothing."
