# Review Figure — Deep Learning for Antimicrobial Peptide Prediction

**Files**

| File | Purpose |
|---|---|
| `amp_dl_review_fig1.svg` | Master figure — fully editable vector (open in Illustrator / Figma / Inkscape / PPT) |
| `amp_dl_review_fig1.png` | 2340×1560 raster export (~300 dpi at double-column width, 183 mm) |

**Figure contents (6-panel snake workflow)**

1. **Data Resources & Curation** — AMP databases (DRAMP, DBAASP, APD3, LAMP2, CAMP),
   positive/negative sampling, CD-HIT/MMseqs2 redundancy reduction, balancing, dataset splits.
2. **Feature Encoding & Representation** — hand-crafted descriptors (one-hot, AAC/DPC/CKSAAP,
   physicochemical, PSSM) vs. pre-trained protein language model embeddings (ESM-2, ProtT5,
   ProtBERT), plus hybrid concatenation.
3. **Deep Learning Architectures** — CNN, BiLSTM/GRU, Transformer/attention, hybrid
   CNN-LSTM-attention and GNN variants (matches this repo's LSTM/Attention/BERT pipeline).
4. **Model Training & Evaluation** — k-fold cross-validation, confusion matrix, ROC analysis,
   standard metrics (Sn, Sp, Acc, BAcc, MCC, AUROC/AUPR).
5. **Applications & Tools** — large-scale screening (e.g. gut-microbiome sORF mining),
   multi-functional classification, de novo design (GAN/VAE/diffusion/LLM), representative predictors.
6. **Challenges & Perspectives** — data quality, activity quantification (MIC), interpretability,
   structure-aware modeling, wet-lab closed loop (DBTL).

**Editing tips (SVG)**

- Every label is a real `<text>` element — click and retype in any vector editor.
- Each panel is a `<g id="panelA">…<g id="panelF">` group with a comment banner — move, recolor, or delete panels independently.
- Colors are plain hex values on each element; fonts default to Helvetica/Arial (swap via the root `font-family` attribute).
- Between-panel arrows live in the single group `flow-arrows`.
- Suggested export for journals: PDF or EPS from Illustrator/Inkscape, or 600-dpi PNG/TIFF.
