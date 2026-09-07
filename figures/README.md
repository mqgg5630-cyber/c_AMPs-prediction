# Review Figures — Illustrated (BioRender-style) SVGs

Three graphical-abstract figures, all 100% native editable SVG built from
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

## Figure 3 — P. gingivalis / periodontal-to-Alzheimer mechanism
`pg_ad_mechanism_fig1.svg` (master) + `.pdf` (vector) + `.png` (2340x1590)

a Periodontal niche (inflamed pocket with P. gingivalis rods and fimbriae, plus
zoom inset) - b Virulence cargo (RgpA/RgpB/Kgp gingipains using shape + letter
redundancy, OMVs with cargo dots) - c Systemic spread (bloodstream vessel with
red cells, immune cells and disseminating cargo) - d BBB gate (endothelial
tight-junction modules and astrocyte branches) - e Brain entry (brain silhouette
with magnified target region) - f Neuronal mechanisms (neuron injury with
amyloid-beta plaques and tau fragments; compact AChE-Aβ nucleation inset with
PAS, Aβ peptide and residue 344-361 surface patch). A bottom evidence band
shows transcriptomics/GEO, molecular docking and 1 microsecond MD simulation.

**Editing** - zones are named groups `zone-a`...`zone-f` (plus the Figure 3
methods band `zone-g`); every icon is plain paths/ellipses referencing one
`<defs>` gradient block (recolor globally). The reproducible generator/exporter
is `generate_top_journal_svgs.py`; journal exports include PDF/EPS-ready vector
PDF and 300-dpi-class PNG.

**Journal compliance** - all figures ship as editable SVG (master), vector
PDF and 2340x1590 PNG (~300 dpi at double-column width). Captions use a bold
"Figure 1 |" lead plus a one-line summary; alt text is embedded via SVG
`<title>`/`<desc>`; minimum label size 8. A deuteranopia deltaE audit passes
for all informational colour pairs (bead classes 114, well states 44/61;
"weak" wells also carry a white centre dot as a redundant cue). Zone tints
are decorative - panel identity is carried by letter chips and titles.

**Reproducibility** - the full methodology (layout system, glossy-icon rules,
renderer-safe constraints, overflow + pixel-probe QA pipeline) is captured in
`.claude/skills/biorender-svg-figure/` (SKILL.md + references/helpers.py) and the reproducible exporter `figures/generate_top_journal_svgs.py`.
