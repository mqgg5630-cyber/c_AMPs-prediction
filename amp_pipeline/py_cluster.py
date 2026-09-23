#!/usr/bin/env python3
"""py_cluster.py - dependency-free greedy clustering fallback (used only when mmseqs2 is unavailable).
Usage: py_cluster.py in.fa out_cluster.tsv min_id cov threads
Greedy incremental clustering, longest-first (CD-HIT style): a sequence joins the first existing
representative with identity >= min_id over an alignment covering >= cov of both sequences.
Candidates are pre-filtered by shared 3-mers; identity from a banded global alignment (pure python).
Output: rep_id \t member_id (same format as mmseqs *_cluster.tsv).
"""
import sys, collections
from multiprocessing import Pool
fa, out, MIN_ID, COV, TH = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
ids, seqs = [], []
with open(fa) as f:
    cur = None
    for ln in f:
        ln = ln.strip()
        if ln.startswith(">"): cur = ln[1:]; ids.append(cur); seqs.append("")
        elif cur is not None: seqs[-1] += ln
order = sorted(range(len(seqs)), key=lambda i: -len(seqs[i]))
K = 3
def kmers(s): return {s[i:i+K] for i in range(len(s) - K + 1)} if len(s) >= K else {s}
def ident(a, b):
    # global alignment identity (Needleman-Wunsch, match=1, mismatch=0, gap=0 scored as matches/len(longer))
    la, lb = len(a), len(b)
    if la < lb: a, b, la, lb = b, a, lb, la
    prev = [0] * (lb + 1)
    for i in range(1, la + 1):
        cur = [0] * (lb + 1); ai = a[i-1]
        for j in range(1, lb + 1):
            cur[j] = max(prev[j-1] + (1 if ai == b[j-1] else 0), prev[j], cur[j-1])
        prev = cur
    return prev[lb] / la
reps = []                      # list of (idx, kmerset)
index = collections.defaultdict(list)   # kmer -> rep positions
assign = {}
for n, i in enumerate(order):
    s = seqs[i]; ks = kmers(s)
    cnt = collections.Counter()
    for k in ks:
        for r in index.get(k, ()): cnt[r] += 1
    need = max(1, int(len(ks) * (MIN_ID - 0.15)))
    hit = None
    for r, c in cnt.most_common(50):
        if c < need: break
        ri = reps[r]
        if len(s) < COV * len(seqs[ri]): continue
        if ident(s, seqs[ri]) >= MIN_ID: hit = ri; break
    if hit is None:
        reps.append(i); pos = len(reps) - 1
        for k in ks: index[k].append(pos)
        assign[i] = i
    else: assign[i] = hit
    if n % 100000 == 0 and n: print(f"  clustered {n}/{len(order)} -> {len(reps)} reps", flush=True)
with open(out, "w") as o:
    for i in order: o.write(f"{ids[assign[i]]}\t{ids[i]}\n")
print(f"OK: {len(reps)} clusters from {len(order)} sequences")
