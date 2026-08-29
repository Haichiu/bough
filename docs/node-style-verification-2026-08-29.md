# NodeStyle / U7 verification — 2026-08-29

## Tested artifacts

| Build | Commit | `MindFlow` SHA-256 (first 16) | Role |
|---|---|---|---|
| pre-NodeStyle snapshot | `1988012` | `b6a9ce79ddb7c3d2` | negative control |
| S4 NodeStyle snapshot | `f922f69` | `ac40b2d968e38620` | positive control |

Both runs used immutable copies under `/tmp`, not the mutable Desktop app.

## U7 oracle

U7 loads `scripts/fixtures/u7-style.mindmap`, a fixed 20-node derivative of
`small-20`. One depth-2 topic is a 31-character Chinese string without spaces so
character-level wrapping is observable.

The oracle checks:

1. AX and SVG relative center positions after independently removing translation and
   scale (observed `0.0039888`; provisional threshold `0.016`).
2. Width and height profiles within each depth cohort. Width observed `0.0205797`
   with threshold `0.083`; height observed `0.0` with provisional threshold `0.02`.
   AX exposes text/accessibility bounds while SVG rects include padding and stroke,
   so absolute pixel dimensions are deliberately not compared.
3. Exact NodeStyle export values: fonts `18/15/13`, radii `14/11/9`, opaque and
   unstroked depth 0/1 surfaces, root fill `#3c4c62`, and depth>=2 fill opacity
   `0.12` with same-branch-color stroke at opacity `0.38` and width `1.0`.
4. The long topic produces at least two SVG `<text>` lines.

### Discriminating power

- **Has an old-build negative control:** font at every depth, radius at depth 0/1,
  deep paint, and wrapping.
- **Internal consistency only; no cross-version discrimination:** relative position,
  width profile, height profile, and depth>=2 radius. The old exporter used the same
  layout frames and already emitted deep `rx=9`. These checks guard future divergence
  between screen and export; they do not distinguish S4 from the old build.

## Results

| Check | Old snapshot | S4 snapshot |
|---|---|---|
| fonts by depth | `17/14/12` — FAIL | `18/15/13` — PASS |
| radii by depth | `9/9/9` — FAIL at depth 0/1 | `14/11/9` — PASS |
| deep paint | white/no opacity, stroke width `1.5` — FAIL | `0.12`, branch stroke `0.38/1.0` — PASS |
| long-topic SVG lines | `1` — FAIL | `2` — PASS |
| relative geometry (consistency only) | old reading discarded; see oracle correction below | position `0.0040/0.016`, width `0.0206/0.083`, height `0.0000/0.02` — PASS |
| **U7** | **FAIL (expected negative control)** | **PASS** |

The first S4 parse incorrectly reported position error `0.4936`: AX exposes two
`AXStaticText` elements with value `N-0000`—the canvas node (`92x38`) and document
title (`381x52`). The title frame is also occupied by the version/autosave status
text; the canvas root is the sole other candidate. The parser now permits duplication
only for the root/document-title value and requires exactly that structure. Any
duplicate non-root value or ambiguous root candidates fail closed. A synthetic
duplicate `N-0001` probe exits 1 with the duplicate named.

The old style/wrap negative evidence is independent of that duplicate-root correction.
It was not rerun after foreground authorization ended.

Five offline recalculations of the same saved S4 artifacts produced identical errors:
position `0.0039888`, width `0.0205797`, height `0.0`. Because these are deterministic
recomputations of **one capture**, they do not measure capture-to-capture noise. The
position and width thresholds are provisional values at about 4x the single observed
errors. Height has no observed nonzero error, so `0.02` is explicitly provisional
rather than noise-derived. More captured runs are required before calling these noise
bounds.

## Harness facts discovered

- The menu bar parent is AX title `File`, while its submenu and item are Chinese
  (`匯出` / `SVG 向量圖…`).
- The NSSavePanel is an `AXDialog` titled `Save`; its filename field contains the stem
  without `.svg`.
- U7 artifacts use fixed filenames under `/tmp/uitest-artifacts` and are overwritten;
  they do not accumulate.

## Screenshot probe

U1 still PASSed on the S4 snapshot, but the attempted CGWindow-ID capture produced no
PNG. Screenshot capability is **not established**. The unverified helper was removed
rather than adding compile time and warnings to every U1 run.

The new appearance—fonts `18/15/13`, radii `14/11/9`, and branch-tinted depth>=2
nodes—has **not received any visual verification**. U7 proves that screen/export read
consistent numerical geometry and that SVG emits the accepted values; it does not
prove those values look good. At this point only the owner's eyes can make that
judgment.
