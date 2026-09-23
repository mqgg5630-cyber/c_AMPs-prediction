#!/usr/bin/env python3
"""peptide_features.py - compare physicochemical features between peptide sets.
Usage: peptide_features.py out.tsv name1=file1.tsv name2=file2.tsv ...   (file: seq \t prob per line)
Reports per set: n, length (mean/median), net charge at pH 7 (K+R - D-E, H +0.1), hydrophobic fraction
(AILMFWVY), Eisenberg mean hydrophobicity, fraction cationic (charge>=2), amino-acid composition (%),
and effect sizes (Cliff's delta) of set1 vs each other set for length/charge/hydrophobicity.
Only the standard library is used; sets larger than MAX_N are subsampled deterministically.
"""
import sys, random, statistics as st
MAX_N = 300000
EIS = dict(zip("ARNDCQEGHILKMFPSTWYV",
    [0.62,-2.53,-0.78,-0.90,0.29,-0.85,-0.74,0.48,-0.40,1.38,1.06,-1.50,0.64,1.19,0.12,-0.18,-0.05,0.81,0.26,1.08]))
HYD = set("AILMFWVY"); AA = "ACDEFGHIKLMNPQRSTVWY"

def feats(s):
    L = len(s); ch = s.count("K") + s.count("R") - s.count("D") - s.count("E") + 0.1 * s.count("H")
    hf = sum(1 for c in s if c in HYD) / L; ei = sum(EIS.get(c, 0) for c in s) / L
    return L, ch, hf, ei

def cliffs(a, b, n=20000):
    ra = random.Random(1); rb = random.Random(2)
    a = ra.sample(a, min(n, len(a))) if len(a) > n else a; b = rb.sample(b, min(n, len(b))) if len(b) > n else b
    b_s = sorted(b); import bisect
    gt = lt = 0
    for x in a:
        lt += bisect.bisect_left(b_s, x); gt += len(b_s) - bisect.bisect_right(b_s, x)
    return (gt - lt) / (len(a) * len(b)) if a and b else float("nan")

out = sys.argv[1]; sets = []
for arg in sys.argv[2:]:
    name, path = arg.split("=", 1); seqs = []
    with open(path) as f:
        for i, ln in enumerate(f):
            seqs.append(ln.split("\t", 1)[0].strip())
    n_all = len(seqs)
    if n_all > MAX_N: seqs = random.Random(0).sample(seqs, MAX_N)
    F = [feats(s) for s in seqs if s]
    comp = {a: 0 for a in AA}; tot = 0
    for s in seqs:
        for c in s:
            if c in comp: comp[c] += 1; tot += 1
    sets.append(dict(name=name, n=n_all, F=F, comp={a: 100 * comp[a] / max(tot, 1) for a in AA}))

rows = ["metric"] + [s["name"] for s in sets]; table = [rows]
def _safe(fn, s):
    try: return fn(s) if s["F"] else "NA"
    except Exception: return "NA"
def add(label, fn): table.append([label] + [_safe(fn, s) for s in sets])
add("n_peptides", lambda s: str(s["n"]))
add("n_sampled_for_features", lambda s: str(len(s["F"])))
add("length_mean", lambda s: "%.2f" % st.mean(f[0] for f in s["F"]))
add("length_median", lambda s: "%.0f" % st.median(f[0] for f in s["F"]))
add("net_charge_mean", lambda s: "%.2f" % st.mean(f[1] for f in s["F"]))
add("cationic_frac(charge>=2)", lambda s: "%.3f" % (sum(1 for f in s["F"] if f[1] >= 2) / len(s["F"])))
add("hydrophobic_frac_mean", lambda s: "%.3f" % st.mean(f[2] for f in s["F"]))
add("eisenberg_H_mean", lambda s: "%.3f" % st.mean(f[3] for f in s["F"]))
for a in AA: add("aa_%s_pct" % a, lambda s, a=a: "%.2f" % s["comp"][a])
if len(sets) > 1:
    base = sets[0]
    for k, lab in ((0, "length"), (1, "charge"), (2, "hydrophobic_frac"), (3, "eisenberg_H")):
        table.append(["cliffs_delta_%s_vs_%s" % (lab, base["name"])] + ["ref"] + [("%.3f" % cliffs([f[k] for f in s["F"]], [f[k] for f in base["F"]])) if s["F"] and base["F"] else "NA" for s in sets[1:]])
with open(out, "w") as f:
    for r in table: f.write("\t".join(r) + "\n")
print("OK:", out)
