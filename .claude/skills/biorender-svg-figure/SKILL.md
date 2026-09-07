---
name: biorender-svg-figure
description: >-
  Draw glossy BioRender-style illustrated scientific figures (graphical
  abstracts / review overviews) as native editable SVG — icon-driven zones,
  renderer-safe gradients and opacities, automated text-overflow and pixel-probe
  QA, PNG export via svglib+pymupdf. Use when asked for illustrated overview
  figures of biomedical or food-science topics ("BioRender style", "graphical
  abstract", "综述图/插画式科研图示").
---

# BioRender-style SVG figures

Tell the story with **illustrated icons**, never data charts or text cards.
Precedents in this repo: `figures/amp_dl_review_fig1.svg` (deep learning for
AMP prediction), `figures/umami_ml_fig1.svg` (ML for umami peptides), and
`figures/pg_ad_mechanism_fig1.svg` (P. gingivalis periodontal-to-Alzheimer
mechanism).

## 1. Layout system

- Canvas 1560×1060, white background, title row (16 pt bold + thin rule).
- Six tinted zones `zone-a`…`zone-f` (2 rows × 3 cols, ~450–570 × 420–500 px),
  each: rounded tint rect (2 tints of the zone hue, 1.2 px border, rx 16),
  gradient letter chip (11 px circle, bold white letter) + "| Title" (12 pt).
- Story flows a→b→c (top row), then d←e←f visual order / f→a loop; connect
  zones with 3 px gray arrows through the gutters.
- Text budget: ≤ ~60 short labels total. Captions 8–8.5 pt gray under icons,
  a few bold take-aways; minor scenes at 8 pt — **hard font floor, nothing below 8**.

## 2. The glossy look (construction rules)

- **Gradients**: one `<defs>` block; radial gradients with highlight focus at
  cx=0.35 cy=0.30 (3 stops: light → mid → deep). Reuse the factory in
  `references/helpers.py` (`PALETTE`, `GRAD`, `build_defs`).
- **Glossy ball** `SPH(x,y,r,g)`: gradient circle + white sheen ellipse
  (`fill-opacity 0.5`, offset up-left). Use everywhere for beads/points.
- **Contact shadow** `SHAD`: two nested ellipses, `#31506B` at fill-opacity
  0.09 / 0.06, under every hero icon — kills the "floating" look.
- Strokes 1.2–1.6 px, `stroke-linecap="round"`; icons centered on an (x,y)
  anchor, 40–80 px; banners = linear gradient + white bold text + gold
  sparkles (`sparkle`, `star5`).
- One palette per theme (cool clinical vs warm food); color-only encoding
  (e.g. blue = basic/charged, red = hydrophobic) instead of tables.

## 3. Renderer-safe constraints (browser = PNG parity)

The PNG pipeline is `svglib → renderPDF → pymupdf Matrix(2,2)`. Its quirks:

- Use **`fill-opacity` only**. Bare `opacity=` on circles/ellipses/paths
  renders SOLID; `fill-opacity` on *stroked* paths also renders solid —
  precompute a solid tint instead (e.g. `#FAE4E1` for a 10 % red wash).
- `stop-opacity` is unreliable → bake alpha into stop colors.
- No filters, masks, patterns, or raster images — gradients + flat shapes.
- Escape `&` as `&amp;`; no `--` inside XML comments; after generating,
  assert every `url(#id)` reference resolves to a defs id.

## 4. Workflow

1. `pip install lxml reportlab svglib pymupdf pillow` (sandbox resets:
   reinstall; `--break-system-packages` if needed).
2. Write a **generator script** (pure Python appending SVG fragments to a
   list; icons are small functions). Import primitives from
   `references/helpers.py`. Keep generators OUTSIDE the repo (e.g. `~/.gen/`).
3. `python -m py_compile gen.py && python gen.py` → check refs:
   `re.findall(r'url\(#([^)]+)\)')` vs `re.findall(r'id="([^"]+)"')`.
4. **Overflow QA** — every `<text>` measured with `stringWidth`, clamped to
   its zone box (walk `iterancestors` for the enclosing `zone-*` group; the
   checker ignores `transform=` on ancestors — sanity-check flags visually).
5. **Render QA** — count warnings, must be 0:
   `svg2rlg → renderPDF.drawToFile → pymupdf Matrix(2,2) → PNG` (2340×1590).
6. **Pixel probes** — PIL point samples (icon midtones) + region counts
   (≥ N px matching a color predicate). Probe the icon *body*, not borders or
   labels; when a probe "fails", dump a color histogram of the box before
   patching — it is usually a sampling miss.
7. **Density audit** — no empty pocket larger than ~100×60 px; every zone
   ≥ 2 scenes; heroes get shadow + sparkles. List zone contents by coordinate
   before declaring done.
8. Export a **vector PDF** next to the PNG (journals require vector or
   ≥300 dpi); commit `figures/*.svg *.png *.pdf` + update `figures/README.md`;
   one commit per version bump; push to the working branch.


## 5. Top-journal compliance checklist (Nature/Cell graphical-abstract bar)

- **Caption**: bold `Figure n |` lead, roman title, then a one-line summary
  underneath (≤ 2 caption lines inside the canvas).
- **Alt text**: `<title>` + `<desc>` telling the whole story (accessibility;
  required by many journals).
- **Font floor**: nothing below size 8; captions 8–8.5, zone titles 12,
  figure title 16.
- **Colour-blind safety**: audit every *informational* colour pair with
  `cbt_audit` / `deltaE(..., "deuteranopia")` from helpers.py. Pass =
  ΔE-deut ≥ 25 (or ≥ 15 with normal ΔE ≥ 25). Reference results from precedent
  figures: bead blue/red 114, green/gray wells 44, green/amber wells 61,
  P. gingivalis mechanism pairs 92-121 — all pass. Decorative zone tints are exempt (panel identity is
  carried by letter chips + titles; WCAG 1.4.1 "never colour alone"), and any
  colour that encodes *state* gets a redundant non-colour cue (e.g. white
  centre dots on "weak" MIC wells).
- **Deliverables**: editable SVG (master) + vector PDF + PNG ≥ 300 dpi at
  double-column width (2340×1590 ≈ 300 dpi at 198 mm).
- **Provenance**: all icons drawn from scratch in code — no subscription
  assets embedded, safe to publish as original artwork.

## 6. Common pitfalls (all seen in practice)

| Bug | Symptom | Fix |
|---|---|---|
| Positional opacity slip | `stroke="0.5"` in SVG, "Can't handle color: 0.5" | `grep 'stroke="0\.'` → pass `opacity=` keyword |
| `url(#gX)` typo | icon invisible in PNG | refs-vs-defs assert (step 3) |
| Keyword-after-positional | SyntaxError in generator | always call helpers with keywords after fills |
| Bulk replace on wrong anchor | patch silently no-ops / breaks | `assert old in src` before every replace |
| Bare opacity on shapes | solid blobs in PNG | fill-opacity only; solid tints for washes |
| Sparse zones | "太简单了" | density audit (step 7), 3+ scenes per zone |

## 7. Icon recipes (anchor-centered, ~20–36 primitives each)

peptide chain (beads on a line) · DNA double helix (two phase-shifted sine
strokes + rungs) · database (stacked ellipse cylinders) · monitor with glowing
NN (dark screen, layered nodes, thin links) · server · code window · AI brain ·
α-helix ribbon (gradient stroke + pale core) · helical wheel · funnel · petri
dish (agar + lawn dots + halos) · 96-well plate (color-coded wells) · test
tubes / rack · flasks with bubbles · pipette · pill · cream tube · apple ·
shield · mouse · bacterium (LPS wall, membrane, nucleoid, ribosomes, pores) ·
scissors (protease) · yeast · magnifier · lyophilizer flask · powder jar ·
tongue · tasting panel · electronic tongue · T1R1/T1R3 dimer (VFT lobes + 7-TM
columns in a membrane) · cell (nucleus + sparkles) · soup bowl · sauce bottle ·
salt shaker · noodle cup · cutlery · plate · GPU chip · blood agar · microscope
· syringe · bandage · checklist · factory · heart/leaf/star trio.

Copy exact geometry from the three precedent SVGs (they are QA-green), rescale
by wrapping in `<g transform="translate scale">`.
