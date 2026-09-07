# Review Figures — Illustrated (BioRender-style) SVGs

Two graphical-abstract figures, both 100% native editable SVG built from
glossy illustrated icons (gradients + flat shapes, renderer-safe opacities,
no raster/filter effects). Story flows a-f through tinted zones with
chunky letter chips; text is kept to short captions.

## Figure 1 — Deep learning for antimicrobial peptide prediction
`amp_dl_review_fig1.svg` (master) + `.png` (2340x1590)

a Sources (gut/soil/water, DNA, databases, tubes) - b Deep learning (peptide
chain into a glowing neural-net monitor, server, code, AI brain) - c Candidates
(helix ribbon, helical wheel, funnel to ranked-leads card) - d Validation
(petri dish with inhibition halos, 96-well MIC plate, tubes, flasks, pipette) -
e Applications (pill, cream, apple, shield, mouse, plate, banner) -
f Mechanism (bacterium under AMP attack; carpet/toroidal/micelle vignettes).

## Figure 2 — Machine learning for umami peptide discovery
`umami_ml_fig1.svg` (master) + `.png` (2340x1590)

a Foods (kombu, tomato, mushroom, cheese, soybeans, fish -> food proteins) -
b Preparation (protease scissors cut the protein chain; yeast, ultrafiltration
funnel, peptide fractions) - c Screening (peptides into a neural-net monitor,
RF/SVM/CNN chip, funnel to ranked umami candidates) - d Tasting (tongue,
3-person sensory panel, electronic tongue) - e Receptor (T1R1/T1R3 dimer with
Venus-flytrap lobes catching a peptide in the membrane, G-protein signal to
"umami!"; cell-based assay) - f Products (steaming soup bowl, soy-sauce
bottle, salt shaker with reduction arrow, cutlery, balanced-meal plate,
low-salt banner).

**Editing** - zones are named groups `zone-a`...`zone-f`; every icon is plain
paths/ellipses referencing one `<defs>` gradient block (recolor globally).
Generators kept out of the repo; export via PDF/EPS or 600-dpi TIFF.
