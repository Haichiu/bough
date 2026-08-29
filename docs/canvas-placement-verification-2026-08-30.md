# Canvas placement verification (U8/U9/U10) — 2026-08-30

## Question

When a restored map opens, are all node labels inside the visible map canvas, and is
the content centered? Headless `CanvasFit` checks cannot distinguish this defect
because the fit math was correct; the failure was in SwiftUI placement at runtime.

## Tested artifacts

| Role | Commit/build | Binary SHA16 | Runtime result |
|---|---|---|---|
| negative control | `f922f69` | `ac40b2d968e38620` | U8 FAIL |
| ineffective refit attempt | `f9014f1` | `baef17148f49ab41` | identical U8 FAIL |
| diagnostic probe | uncommitted | `fc81d9ad11be6d9b` | U9 values captured |
| placement fix + probe | uncommitted | `5a0ac3d1d3808a0a` | U10 PASS after corrected canvas derivation |
| clean placement fix | `801e107` | `e9fda3fbf555b18c` | probe removed; not UI-rerun by instruction |

The old negative uses the preserved exact `ac40` app. A fresh `f922f69` release build
produced a different binary hash, so it was deleted rather than substituted for the
artifact that actually exhibited the defect.

## AX-derived visible canvas

No screen coordinates are hardcoded. U8 records every source frame and derives the
canvas as follows:

1. Require one `AXWindow`; retain the largest contained `AXGroup` as a cross-check.
2. Find the full-width `AXToolbar`: `(510,37,960,52)`, bottom `89`.
3. Find the top wide `AXScrollArea` (document tabs): `(520,95,940,25)`.
4. The ScrollArea excludes the tab row's symmetric vertical padding. Its top inset is
   derived as `95 - 89 = 6`; therefore canvas top is `120 + 6 = 126`.
5. Find the right-side `AXRadioGroup`: `(1204,140,252,22)`. Its right edge is `1456`,
   14pt inside the window right edge `1470`; applying that same inset on its left puts
   the inspector boundary at `1190`.
6. Canvas is therefore `(510,126,680,583)`, ending at window bottom `709`.

When the temporary runtime probe is present, U8 additionally requires its
`geo=680x583` to equal the derived width/height. A mismatch is a harness derivation
failure, not a product failure. Clean builds intentionally have no probe and report
that self-check as unavailable.

The earlier top `120` / height `589` estimate omitted the symmetric 6pt padding and is
discarded.

## Node identity and extent

U8 matches all 20 exact fixture texts (19 `N-####` labels plus the long Chinese topic),
not merely a regex. Only the root/document-title value may appear twice; it is
structurally disambiguated from the title frame, while any other duplicate fails
closed.

The old long label ended exactly at canvas right `1190`. This is retained as an edge
diagnostic, but no longer makes the extent unknown: AX also reported node frames down
to `802`, 93pt beyond the window bottom `709`, proving these AX frames are not clipped
to the visible canvas.

## Assertions and tolerances

- **Primary:** every fixture node frame is inside the derived canvas. Boundary
  tolerance is a provisional `1pt` for integer AX frames. This is a single runtime
  observation, not a measured noise distribution.
- **Size diagnostic:** content width/height versus canvas width/height. A map can fit
  in size while still be misplaced.
- **Center auxiliary:** signed `content center - canvas center` must remain within
  `3.1pt` per axis. AX exposes text frames while layout uses node-card frames; the
  fixture's asymmetric horizontal card insets imply a basis difference of about
  `(24-14)/2 × 0.618 = 3.09pt`. This threshold is derived from the two measurement
  bases, not widened after observing the result.
- **Probe geometry:** when present, runtime `geo` must match the AX-derived canvas.

## Negative control (U8)

Both `ac40` and the ineffective `baef` build produced the same values:

- canvas: `(510,126,680,583)`
- content bbox: `(805,392,385,410)`, edges `x=805..1190`, `y=392..802`
- size: `385x410 < 680x583` (the map was small enough)
- signed center delta: `(+147.5,+179.5)`
- bottom overflow: `N-0016=12`, `N-0017=39`, `N-0004=68`, `N-0018=66`,
  `N-0019=93pt`
- result: **FAIL**

This disproved the refit-timing hypothesis: scaling was not the defect.

## Runtime probe (U9)

Exact AX value:

```text
canvasprobe geo=680.00,583.00 bounds=-180.00,-446.00,980.00,944.00 cb=0.00,-306.00,620.00,664.00 pan=0.00,0.00 scale=0.62
```

`geo` was the visible canvas, `pan` was zero, and `bounds`/`contentBounds` had the same
center. The observed offset matched `(bounds.size - geo.size)/2 = (150,180.5)`.
The cause was SwiftUI sizing the `ZStack` to its oversized child (`980x944`), placing
that at the GeometryReader's top-leading origin, and scaling around the oversized
container's center.

## Placement fix (U10)

Pinning the `ZStack` to `geo.width/height` left the probe value byte-for-byte unchanged
but changed screen placement:

- canvas: `(510,126,680,583)`; probe geometry self-check PASS
- content bbox: `(655,212,385,410)`, edges `x=655..1040`, `y=212..622`
- signed center delta: `(-2.5,-0.5)`
- overflow: none
- result using final U8 oracle: **PASS**

The `-2.5pt` horizontal residual is reported, not called zero; it lies within the
text-frame versus card-frame basis bound above.

## Data protection and artifacts

All foreground runs used transaction-scoped tabs snapshots from `4b5d05b`. Each run
restored the owner's 20-file tabs tree to digest
`e96f06af42bc70f36db58f8bfbb5fdb0717dece085fd8212facf1f5fa524e597` and stopped the
app. Fixed artifacts overwrite rather than accumulate:

- `/tmp/uitest-artifacts/U8-old-ax.tsv`
- `/tmp/uitest-artifacts/U8-new-ax.tsv`
- `/tmp/uitest-artifacts/U9-ax.tsv`
- `/tmp/uitest-artifacts/U10-ax.tsv`

U10 was a one-shot diagnostic against a temporary probe. No permanent `u10.sh` is
kept after the probe was removed; its durable no-overflow and centering checks are U8.
