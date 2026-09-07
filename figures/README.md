# Review Figures — Illustrated (BioRender-style) SVGs

Two graphical-abstract figures, both 100% native editable SVG built from
glossy illustrated icons (gradients + flat shapes, renderer-safe opacities,
no raster/filter effects). Story flows a-f through tinted zones with
chunky letter chips; text is kept to short captions.

## Figure 1 — Deep learning for antimicrobial peptide prediction
`amp_dl_review_fig1.svg` (master) + `.png` (2340x1590)

a Sources (gut/soil/water icons, DNA, databases, validated tubes, and a
"known AMPs" corpus card) - b Deep learning (peptide chain into a glowing
neural-net monitor, server + GPU cluster, code, AI brain, mouse) - c Candidates
(helix ribbon, helical wheel, sequence-optimization scene, funnel to
ranked-leads card) - d Validation (petri dish with inhibition halos, 96-well
MIC plate, tubes, flasks, pipette, sterility/hemolysis/microscopy strip) -
e Applications (pill, cream, apple, shield, syringe, bandage, mouse, plate,
banner, clinical-trials checklist, manufacturing) - f Mechanism (bacterium
under multi-chain AMP attack with pore leaks and DNA debris; carpet/toroidal/
micelle vignettes).

## Figure 2 — Machine learning for umami peptide discovery
`umami_ml_fig1.svg` (master) + `.png` (2340x1590)

a Foods (kombu, tomato, mushroom, shrimp, cheese, soybeans, fish, bacon in a
4x2 grid with umami sparkles, converging into the food-protein bead chain) -
b Preparation (protease scissors cut the chain in two places with falling
fragments; big ultrafiltration funnel with a "< 3 kDa" chip, 6-tube fraction
rack, freeze-drying flask with snowflakes, peptide-powder jar with scoop) -
c Screening (peptides into a neural-net monitor, RF/SVM/CNN chip, funnel to
ranked candidates card, magnifier over key motifs) - d Tasting (tongue,
3-person sensory panel with rating stars, broth-scoring bowls, sensory-log
clipboard, electronic tongue) - e Receptor (in-vitro vial, T1R1/T1R3 dimer
with Venus-flytrap lobes catching the peptide, brain "perception" branch,
G-protein signal to "umami!", transfected-cell assay with Ca2+ sparkles) -
f Products (soup bowl, soy-sauce bottle, salt shaker with reduction arrow,
cutlery, balanced-meal plate, instant-noodle cup, banner plus a
healthy/natural/tasty icon trio).

**Editing** - zones are named groups `zone-a`...`zone-f`; every icon is plain
paths/ellipses referencing one `<defs>` gradient block (recolor globally).
Generators kept out of the repo; export via PDF/EPS or 600-dpi TIFF.

**Reproducibility** - the full methodology (layout system, glossy-icon rules,
renderer-safe constraints, overflow + pixel-probe QA pipeline) is captured in
`.claude/skills/biorender-svg-figure/` (SKILL.md + references/helpers.py).
