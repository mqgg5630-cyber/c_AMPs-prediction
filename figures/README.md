# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

**BioRender-style** graphic-dominant review figure: glossy gradient icons, soft
shadows, rich color — rendered as 100% native, editable SVG (no bitmaps, no
filters; gradients + flat shapes only, so Illustrator / Figma / Inkscape /
browsers all render it identically). Text stays minimal (~107 short labels:
panel titles, axis numbers, legend keywords); no annotation paragraphs, no
tabular number grids.

**Files**

| File | Purpose |
|---|---|
| `amp_dl_review_fig1.svg` | Master figure — fully editable vector |
| `amp_dl_review_fig1.png` | 2340×1290 raster export (~300 dpi, double-column) |

**Panels (a–f, colored letter chips, soft tinted zones)**

- **a | AMP mechanisms** — glossy-bead Schiffer-Edmundson wheel (charged blue
  spheres with "+" marks, red hydrophobics) with hydrophobic-moment arrow;
  hero bacterium (capsule wall + teal membrane + cytoplasm gradients, purple
  nucleoid, ribosomes, flagella) attacked by AMP bead-chains; radial-gradient
  pores with coral burst rays and green leaks; barrel-stave & toroidal-pore
  close-ups with steel-gradient helix cylinders and flow arrows.
- **b | Features** — pastel rounded-cell MSA block + consensus row; diverging
  teal-white-coral embedding heatmap with colorbar; t-SNE clusters as glow-
  haloed spheres; vibrant conservation logo.
- **c | Architectures** — gradient module chips and shadowed white cores:
  CNN (gradient kernels + stride arrows), BiLSTM (mint capsule cells, teal/
  gray bidirectional arrows), Transformer (glossy token spheres + purple
  attention arcs, ×N bracket); gradient pooling bars, hidden-state beads,
  [CLS] vector; mini sigmoids with area fade and glossy P(AMP) dots; purple
  gradient fusion pill.
- **d | Evaluation** — ROC with gradient area fill + confidence band, PR
  curves, rounded in-plot legend card; dot plot with dodged glossy dots and
  95% CI whiskers.
- **e | Translation** — glossy icon pipeline (DNA reads → assembly graph →
  gene track with glowing sORF pill → peptide beads → scorer chip); haloed
  lollipop ranking with FDR line; dose-response with area fade, error bars,
  MIC line; warm rounded MIC activity matrix.
- **f | Challenges** — color pictograms with two-word titles: dashed leakage
  venn, gradient bars, red-heat saliency strip, dual-color ribbons with
  pLDDT bar, gray→blue generalization dots, purple DBTL loop.

**Technical notes** — shadows/glows use path-ellipse shapes with
`fill-opacity` (not element `opacity`) for maximum renderer compatibility;
gradients live in one `<defs>` block for easy recoloring. Panels are named
groups `panel-a` … `panel-f`. Suggested export: PDF/EPS or 600-dpi TIFF.
