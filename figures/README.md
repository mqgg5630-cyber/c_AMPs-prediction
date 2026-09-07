# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

Dense, publication-grade **BioRender-style** review figure (v7). Every panel packs
multiple real data-style visualizations; text stays minimal (~128 short labels).
100% native editable SVG — gradients + flat shapes only, no filters, renderer-safe
opacities (`fill-opacity`/`stroke-opacity`, solid precomputed tints).

**Files** — `amp_dl_review_fig1.svg` (master) · `amp_dl_review_fig1.png` (2340×1770, ~300 dpi)

**Panel contents**

- **a | AMP mechanisms** — Schiffer-Edmundson wheel (glossy charged/hydrophobic beads,
  hydrophobic sector shading, μH arrow); charge×hydrophobicity activity-landscape
  contours; detailed Gram-negative envelope (LPS-decorated outer membrane, periplasm
  with peptidoglycan, inner membrane, nucleoid, plasmids, 70S ribosomes, polysome
  mRNA, flagellum with basal body + hook, pili) under AMP attack with pore bursts
  and leaks; mechanism cascade carpet → toroidal → micelle → lysed ghost.
- **b | Features** — 20-sequence MSA + per-column conservation bars; PLM embedding
  heatmap with row dendrogram and diverging colorbar; 4-cluster t-SNE with halos;
  8×8 descriptor correlation matrix; 12-position conservation logo.
- **c | Architectures** — token strip → CNN (two kernel rows, stride arrows, gradient
  pooling bars) / BiLSTM (capsule cells with σ-gate dots, tanh arcs, bidirectional
  arrows, hidden-state beads) / Transformer (Q/K/V strips, token spheres, multi-head
  arcs, ×N blocks with residual skip); attention heatmap; GNN mini-graph; ESM-2
  embedding chip; aligned mini-sigmoids → late-fusion pill.
- **d | Evaluation** — ROC with confidence band + in-plot legend; PR curves;
  calibration curve; train/val learning curves; MCC violin plots with whiskers
  across three model families.
- **e | Translation** — reads → assembly graph → gene track with glowing sORF;
  **Sankey funnel** (10⁶ → 10³ → 10² → 24) with gradient flows; time-kill curves;
  MIC heatmap with row dendrogram; stacked outcome bar.
- **f | Challenges** — phylogenetic tree with train/test/novel leaves (homology
  leakage); noisy vs curated label scatter with halos; saliency strip; dual-color
  ribbons + pLDDT bar; generalization shift; synergy checkerboard; DBTL loop.

**Editing** — panels are named groups `panel-a`…`panel-f`; all labels are real text;
26 gradients centralized in `<defs>`. Export: PDF/EPS or 600-dpi TIFF.
