# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

Journal-style, **graphic-dominant** review figure: white canvas, hairline rules,
bold lowercase panel letters (a-f), one-line caption, ~100 short text elements
total (panel titles, axis numbers, legend keywords) — no annotation paragraphs,
no card/pill/badge shapes, no tabular number grids.

**Files**

| File | Purpose |
|---|---|
| `amp_dl_review_fig1.svg` | Master figure — fully editable vector (Illustrator / Figma / Inkscape) |
| `amp_dl_review_fig1.png` | 2340×1290 raster export (~300 dpi at double-column width) |

**Panels (graphics carry the content)**

- **a | AMP mechanisms** — Schiffer-Edmundson wheel as colored residue beads
  (blue +/red/white) with computed hydrophobic-moment arrow; phospholipid
  bilayer cross-section with inserted cationic helix and pore defect; larger
  barrel-stave and toroidal-pore line diagrams.
- **b | Features** — color-only MSA block (24 sequences + consensus row),
  PLM embedding matrix with diverging colorbar, t-SNE scatter with three
  cluster envelopes, WebLogo-style conservation logo.
- **c | Architectures** — three fine-line columns (CNN / BiLSTM / Transformer):
  token input strip, empty module boxes, kernel-swap arrows, bidirectional cell
  chain, multi-head attention arcs with ×N bracket, pooling bars / hidden-state
  dots / [CLS] vector, mini sigmoid curves with P(AMP) dots, dashed fusion.
- **d | Evaluation** — ROC with confidence band + PR curves (full axis
  furniture, in-plot legends), metric dot plot with 95% CI whiskers.
- **e | Translation** — wordless icon pipeline (reads → assembly graph →
  gene track with sORF → peptide → scorer), lollipop ranking with FDR line,
  dose-response with error bars and MIC line, color-only MIC activity matrix.
- **f | Challenges** — six line pictograms with two-word titles: homology
  leakage, label quality, interpretability, structure-aware, generalization,
  closed loop.

**Editing tips** — every remaining label is real text; panels are named groups
(`panel-a` … `panel-f`); all shapes are native SVG with plain hex colors.
Suggested export: PDF/EPS or 600-dpi TIFF.
