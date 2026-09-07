# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

**Files**

| File | Purpose |
|---|---|
| `amp_dl_review_fig1.svg` | Master figure — graphic-first, fully editable vector (Illustrator / Figma / Inkscape / PPT) |
| `amp_dl_review_fig1.png` | 2340×1584 raster export (~300 dpi at double-column width, 183 mm) |

**Design: graphics carry the story, text kept to short labels.**

Top pipeline strip (drawn icons, left → right): DNA/metagenome → sORF calling →
peptide candidates → neural network → validated AMP (shield) → microplate MIC assay.

1. **AMP biology** — Schiffer–Edmundson helical wheel (KWKLFKKILKVLKALV) with hydrophobic
   moment μH arrow and residue color code; lipid-bilayer disruption diagram with carpet-model
   helices, toroidal pore and leaking cytoplasmic contents.
2. **Feature encoding** — one-hot matrix; charge-vs-hydrophobicity scatter with AMP/non-AMP
   clusters and decision boundary; PLM (ESM-2/ProtT5/ProtBERT) blocks with attention arcs and
   embedding heatmap; position-wise sequence logo in bits.
3. **Model architectures** — drawn diagrams: CNN (sliding filters → feature maps → pooling →
   dense → P(AMP)), BiLSTM (bidirectional cell chain), Transformer (residue tokens, multi-head
   attention arcs, blocks, [CLS]); hybrid/transfer-learning footnote.
4. **Training & evaluation** — ROC/AUC curve family (PLM vs hybrid vs CNN), grouped metric bars
   (Sn/Sp/Acc/MCC for BiLSTM vs BERT), 2×2 confusion matrix.
5. **Applications** — screening funnel (10⁶ sORFs → ~10³ scored → ~10² validated), generative
   design (GAN/VAE/diffusion/LLM), deployment icons (web server, drug leads, food & feed).
6. **Challenges & outlook** — icon tiles: data bias & leakage, quantitative activity (MIC),
   interpretability, structure-aware modeling, DBTL closed loop, standardized benchmarks.

**Editing tips (SVG)**

- Short labels are real `<text>` elements — click and retype.
- Each panel is a named group: `pipeline`, `panel-bio`, `panel-encode`, `panel-arch`,
  `panel-eval`, `panel-apps`, `panel-challenges`.
- All icons (helical wheel, membrane, ROC curves, sequence logo, networks, funnel, tiles) are
  native SVG shapes/paths — recolor, rescale or restyle freely; colors are plain hex values.
- Fonts default to Helvetica/Arial (logo letters: Courier). Suggested journal export:
  PDF/EPS from Illustrator or Inkscape, or 600-dpi PNG/TIFF.
