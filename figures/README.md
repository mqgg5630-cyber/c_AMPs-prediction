# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

Journal-style (Nature Reviews / Trends) graphic figure. White canvas, hairline rules,
bold lowercase panel letters (a-f) with a formal figure caption, muted NPG palette
(#E64B35 / #4DBBD5 / #00A087 / #3C5488), and real plot furniture (axes, ticks,
numerical labels, legends) throughout — no PPT-style cards, pills or badges.

**Files**

| File | Purpose |
|---|---|
| `amp_dl_review_fig1.svg` | Master figure — fully editable vector (Illustrator / Figma / Inkscape) |
| `amp_dl_review_fig1.png` | 2340×1350 raster export (~300 dpi at double-column width) |

**Panels**

- **a | AMP structure-activity** — Schiffer-Edmundson helical wheel (melittin 1-20,
  100°/residue spokes, computed μH hydrophobic moment), phospholipid-bilayer cross-section
  (headgroup circles + zigzag tails) with inserted amphipathic helix, barrel-stave vs
  toroidal-pore mechanism diagrams, colored mature-sequence strip.
- **b | Data & feature representation** — multiple-sequence alignment block with consensus
  row and ruler, PLM embedding matrix with diverging colorbar, t-SNE embedding scatter
  (known AMPs / non-AMPs / novel clade), hand-crafted descriptor heatmap with feature-group
  brackets, property radar chart, WebLogo-style conservation logo.
- **c | Model architectures** — three fine-line columns (CNN / BiLSTM / Transformer) with
  dimension annotations, unrolled cells, attention arcs, ×N bracket, aligned mini sigmoid
  outputs with P(AMP) values, dashed fusion into a late-fusion module.
- **d | Benchmarking & evaluation** — ROC with confidence band + PR curves (grids, numeric
  ticks, legends) and a metric dot plot with 95% CI whiskers for three model families.
- **e | From metagenomes to leads** — reads → assembly graph → gene track with sORF →
  peptide → scorer; ranked-candidate lollipop chart with FDR cutoff; dose-response curve
  with error bars and MIC line; activity-spectrum MIC heatmap.
- **f | Open challenges** — six fine-line pictograms: homology leakage, label quality,
  interpretability saliency, structure-aware modeling with pLDDT bar, generalization,
  DBTL closed loop.

**Editing tips** — every label is real text; panels are named groups (`panel-a` …
`panel-f`, `caption`); all shapes are native SVG paths/rects/circles with plain hex
colors; sequence text uses Courier. Suggested export: PDF/EPS or 600-dpi TIFF.
