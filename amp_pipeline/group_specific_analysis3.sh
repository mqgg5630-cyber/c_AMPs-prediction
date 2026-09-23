#!/bin/bash
# ==============================================================================
# group_specific_analysis3.sh —— 组特异性 AMP 分析 v3（精确匹配层面，不用 mmseqs）
#
# 前提（round 10 的 A/B 已证实）：mmseqs 的 k-mer prefilter 对中位 11 aa 短肽基本全盲
# （self 搜索仅 40–67% 命中；0.6 同一性压缩比仅 1.002x）。任何依赖预筛的聚类/搜索
# 结论都不可靠。本脚本只用精确匹配（sort/join/awk 精确计数），回答：
#   A'. 跨队列一致性：Cohort1 与 Cohort3 的 AD-only / NC-only 精确序列集合是否显著重叠
#       （超几何检验；若只是采样噪音，重叠 ≈ 随机期望）
#   B.  深度校正：下采样到相同记录数后，AD/NC 共享率结论是否翻转
#   D.  长度分层：各长度 bin 的 AD/NC Jaccard（短肽噪音 vs 长肽信号）
#   C.  k-mer 富集：5-mer 在 AD vs NC unique 序列中的频率比较（chi2 + BH）
#
# 用法: bash group_specific_analysis3.sh <amp_results 目录> [输出目录]
# 复用 results/group_specific_family/work/all.tsv（35M 行索引）以省时间
# ==============================================================================
set -e
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RES_ROOT="$(readlink -f "${1:?用法: bash group_specific_analysis3.sh <amp_results> [out]}")"; RES="$RES_ROOT/results"
OUT="$(readlink -f -m "${2:-$PROJECT_DIR/results/group_specific_v3}")"
PREV_WORK="$(readlink -f -m "$PROJECT_DIR/results/group_specific_family/work")"
W="$OUT/work"; mkdir -p "$W"
THREADS="${THREADS:-$(nproc)}"
SORT="sort -S ${SORT_MEM:-30%} --parallel=$THREADS -T ${TMPDIR:-$W}"
PY="$(command -v python3 || command -v python)"; log(){ echo "[$(date '+%F %T')] $*"; }

# ---- 索引 all.tsv(seq name group prob)，复用 v1 的
if [ ! -s "$W/all.tsv" ]; then
  if [ -s "$PREV_WORK/all.tsv" ]; then ln "$PREV_WORK/all.tsv" "$W/all.tsv" 2>/dev/null || cp "$PREV_WORK/all.tsv" "$W/all.tsv"; log "复用索引 all.tsv"
  else
    log "[0] 汇总 14 组的三票 AMP ..."; mkdir -p "$W"
    for f in "$RES"/*/*/aggregated_results.tsv; do awk -F'\t' -v g="$(basename "$(dirname "$f")")" 'NR>1 && $8==1 {print $2"\t"$1"\t"g"\t"($4+$5+$6)/3}' "$f"; done | $SORT -k1,1 -k3,3 > "$W/all.tsv"
  fi
fi
log "  记录数: $(wc -l < "$W/all.tsv")"

# ---- 序列×组 presence（精确匹配）
if [ ! -s "$W/seq_groups.tsv" ]; then
  log "[1] 序列×组 presence ..."
  awk -F'\t' '{print $1"\t"$3}' "$W/all.tsv" | $SORT -u | awk -F'\t' '{m[$1]=m[$1]"|"$2} END{for(s in m) print s"\t"m[s]}' | $SORT -k1,1 > "$W/seq_groups.tsv"
  log "  唯一序列: $(wc -l < "$W/seq_groups.tsv")"
fi

# ---- A'. 跨队列一致性（超几何，正态近似 p 值）
if [ ! -s "$OUT/cross_cohort.tsv" ]; then
  log "[A] 跨队列一致性 ..."
  "$PY" - "$W/seq_groups.tsv" "$W/all.tsv" "$OUT" <<'PY'
import sys, math
sg, alltsv, out = sys.argv[1], sys.argv[2], sys.argv[3]
def has(gstr, g): return f"|{g}" in gstr or gstr.startswith(g)
# 总体: 出现在 C1_AD/C1_NC/C3_AD/C3_NC 任一组中的序列
pop = set(); X = set(); Y = set(); Xn = set(); Yn = set()
prob = {}
for ln in open(alltsv):
    s, _, g, p = ln.rstrip("\n").split("\t")
    if s not in prob: prob[s] = float(p)
for ln in open(sg):
    s, gs = ln.rstrip("\n").split("\t")
    c1a, c1n = has(gs, "Cohort1_AD"), has(gs, "Cohort1_NC")
    c3a, c3n = has(gs, "Cohort3_AD"), has(gs, "Cohort3_NC")
    if c1a or c1n or c3a or c3n: pop.add(s)
    if c1a and not c1n: X.add(s)
    if c3a and not c3n: Y.add(s)
    if c1n and not c1a: Xn.add(s)
    if c3n and not c3a: Yn.add(s)
def hypergeom(N, K, n, k):
    mu = K * n / N
    var = K * n / N * (N - K) / N * (N - n) / max(N - 1, 1)
    z = (k - mu) / math.sqrt(var) if var > 0 else 0.0
    p = math.erfc(abs(z) / math.sqrt(2))
    return mu, (k / mu if mu else 0.0), z, p
N = len(pop)
rows = ["contrast\tN_pop\tK_set1\tn_set2\tk_overlap\texpected\tfold_enrich\tz\tp_norm"]
tests = [("ADonly_C1_vs_C3", X, Y), ("NConly_C1_vs_C3", Xn, Yn),
         ("ADonly_C1_vs_NConly_C3(ctrl)", X, Yn), ("NConly_C1_vs_ADonly_C3(ctrl)", Xn, Y)]
inter = {}
for name, A, B in tests:
    k = len(A & B); mu, fold, z, p = hypergeom(N, len(A), len(B), k)
    rows.append(f"{name}\t{N}\t{len(A)}\t{len(B)}\t{k}\t{mu:.1f}\t{fold:.3f}\t{z:.2f}\t{p:.2e}")
    inter[name] = A & B
open(f"{out}/cross_cohort.tsv", "w").write("\n".join(rows) + "\n")
print("\n".join(rows))
# 交集候选清单（按 prob 排序）
for name, S in inter.items():
    if not name.endswith("(ctrl)") and S:
        tag = "AD" if name.startswith("AD") else "NC"
        ranked = sorted(S, key=lambda s: -prob.get(s, 0))
        with open(f"{out}/cross_cohort_{tag}_intersect.fa", "w") as o:
            for i, s in enumerate(ranked, 1):
                o.write(f">{tag}{i}|prob={prob.get(s,0):.3f}|len={len(s)}\n{s}\n")
        print(f"{tag} 交集 {len(ranked)} 条 -> cross_cohort_{tag}_intersect.fa")
PY
fi

# ---- B. 深度校正（Cohort4 AD/NC 下采样到相同记录数）
if [ ! -s "$OUT/rarefaction.tsv" ]; then
  log "[B] 深度校正 ..."
  awk -F'\t' '$3=="Cohort4_Disease_AD" || $3=="Cohort4_Healthy_NC" {print $3"\t"$1}' "$W/all.tsv" | $SORT -k1,1 -k2,2 > "$W/c4.tsv"
  NA=$(awk -F'\t' '$1=="Cohort4_Disease_AD"' "$W/c4.tsv" | wc -l); NN=$(awk -F'\t' '$1=="Cohort4_Healthy_NC"' "$W/c4.tsv" | wc -l)
  N=$(( NA < NN ? NA : NN )); log "  AD 记录 $NA, NC 记录 $NN, 下采样 N=$N"
  for g in Cohort4_Disease_AD Cohort4_Healthy_NC; do
    awk -F'\t' -v g="$g" '$1==g{print $2}' "$W/c4.tsv" > "$W/c4_$g.seq"
    tot=$(wc -l < "$W/c4_$g.seq"); step=$(awk -v t="$tot" -v n="$N" 'BEGIN{print (t/n < 1) ? 1 : int(t/n)}')
    awk -v k="$step" 'k<=1 || NR%k==1' "$W/c4_$g.seq" | $SORT -u > "$W/c4_$g.sub"
    $SORT -u "$W/c4_$g.seq" > "$W/c4_$g.uniq"
  done
  "$PY" - "$W" "$OUT/rarefaction.tsv" <<'PY'
import sys
w, out = sys.argv[1], sys.argv[2]
def rd(p): return {ln.strip() for ln in open(p) if ln.strip()}
rows = ["level\tAD_unique\tNC_unique\tshared\tunion\tjaccard\tAD_only_frac\tNC_only_frac"]
for lv in ("uniq", "sub"):
    A = rd(f"{w}/c4_Cohort4_Disease_AD.{lv}"); N = rd(f"{w}/c4_Cohort4_Healthy_NC.{lv}")
    sh = len(A & N); u = len(A | N)
    rows.append(f"{lv}\t{len(A)}\t{len(N)}\t{sh}\t{u}\t{sh/u:.4f}\t{len(A-N)/len(A):.4f}\t{len(N-A)/len(N):.4f}")
open(out, "w").write("\n".join(rows) + "\n")
print("\n".join(rows))
PY
fi

# ---- D. 长度分层（Cohort4 AD/NC + Cohort1 core5 比例）
if [ ! -s "$OUT/length_strata.tsv" ]; then
  log "[D] 长度分层 ..."
  "$PY" - "$W/seq_groups.tsv" "$OUT/length_strata.tsv" <<'PY'
import sys
sg, out = sys.argv[1], sys.argv[2]
def has(gstr, g): return f"|{g}" in gstr or gstr.startswith(g)
bins = [(1, 10, "<=10"), (11, 15, "11-15"), (16, 25, "16-25"), (26, 10**9, ">=26")]
acc = {b: {"ad": set(), "nc": set()} for _, _, b in bins}
core5 = {b: [0, 0] for _, _, b in bins}  # [in_core5, total]
for ln in open(sg):
    s, gs = ln.rstrip("\n").split("\t")
    L = len(s)
    b = next(bb for lo, hi, bb in bins if lo <= L <= hi)
    if has(gs, "Cohort4_Disease_AD"): acc[b]["ad"].add(s)
    if has(gs, "Cohort4_Healthy_NC"): acc[b]["nc"].add(s)
    core5[b][1] += 1
    if all(has(gs, g) for g in ("Cohort1_NC", "Cohort1_SCS", "Cohort1_SCD", "Cohort1_MCI", "Cohort1_AD")):
        core5[b][0] += 1
rows = ["len_bin\tAD_unique\tNC_unique\tshared\tunion\tjaccard\tcore5_frac"]
for lo, hi, b in bins:
    A, N = acc[b]["ad"], acc[b]["nc"]
    sh = len(A & N); u = len(A | N)
    c, t = core5[b]
    rows.append(f"{b}\t{len(A)}\t{len(N)}\t{sh}\t{u}\t{(sh/u if u else 0):.4f}\t{(c/t if t else 0):.4f}")
open(out, "w").write("\n".join(rows) + "\n")
print("\n".join(rows))
PY
fi

# ---- C. k-mer 富集（5-mer，Cohort4 AD vs NC unique 序列，chi2 + BH）
if [ ! -s "$OUT/kmer_enrichment.tsv" ]; then
  log "[C] k-mer 富集 ..."
  for g in Cohort4_Disease_AD Cohort4_Healthy_NC; do
    [ -s "$W/c4_$g.uniq" ] || { awk -F'\t' -v g="$g" '$3==g{print $1}' "$W/all.tsv" | $SORT -u > "$W/c4_$g.uniq"; }
  done
  for g in Cohort4_Disease_AD Cohort4_Healthy_NC; do
    awk '{for(i=1;i<=length($0)-4;i++){k=substr($0,i,5); if(!seen[k]++){c[k]++}}} END{for(k in c) print k"\t"c[k]}' "$W/c4_$g.uniq" | $SORT -k1,1 > "$W/kmer_$g.tsv"
    log "  $g: $(wc -l < "$W/kmer_$g.tsv") 种 5-mer"
  done
  NAU=$(wc -l < "$W/c4_Cohort4_Disease_AD.uniq"); NNU=$(wc -l < "$W/c4_Cohort4_Healthy_NC.uniq")
  join -t "$(printf '\t')" -a1 -a2 -e0 -o auto "$W/kmer_Cohort4_Disease_AD.tsv" "$W/kmer_Cohort4_Healthy_NC.tsv" > "$W/kmer_both.tsv"
  "$PY" - "$W/kmer_both.tsv" "$OUT/kmer_enrichment.tsv" "$NAU" "$NNU" <<'PY'
import sys, math
inp, out, NA, NN = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rows = []
for ln in open(inp):
    p = ln.rstrip("\n").split("\t")
    k, a, n = p[0], int(p[1]), int(p[2])
    # 2x2 chi2 (AD含/不含 x NC含/不含)，序列层面
    b, d = NA - a, NN - n
    tot = a + b + n + d
    num = tot * (a * d - b * n) ** 2
    den = (a + b) * (n + d) * (a + n) * (b + d)
    chi2 = num / den if den else 0.0
    pval = math.erfc(math.sqrt(chi2 / 2)) if chi2 > 0 else 1.0
    fa, fn = a / NA, n / NN
    rows.append((pval, k, a, n, fa, fn, (fa / fn if fn else float("inf")), chi2))
rows.sort()
m = len(rows)
out_rows = ["rank\tkmer\tAD_seq\tNC_seq\tAD_frac\tNC_frac\tfold_AD_NC\tchi2\tp\tp_BH"]
ranked = [(i,) + r for i, r in enumerate(rows, 1)]
# BH 从大到小
bh = [0.0] * m
running = 1.0
for i in range(m - 1, -1, -1):
    running = min(running, ranked[i][1] * m / (i + 1))
    bh[i] = running
for i, r in enumerate(ranked[:1000]):
    rk, pval, k, a, n, fa, fn, fold, chi2 = r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]
    out_rows.append(f"{rk}\t{k}\t{a}\t{n}\t{fa:.6f}\t{fn:.6f}\t{fold:.3f}\t{chi2:.1f}\t{pval:.2e}\t{bh[i]:.2e}")
open(out, "w").write("\n".join(out_rows) + "\n")
sig = sum(1 for x in bh if x < 0.05)
print(f"5-mer 种数 {m}; BH<0.05: {sig}; AD序列 {NA}, NC序列 {NN}")
print("\n".join(out_rows[:11]))
PY
fi

# ---- SUMMARY
{
  echo "# 组特异性 AMP 分析 v3（精确匹配层面） $(date '+%F %T')  ($(hostname))"; echo
  echo "前提: round 10 A/B 已证实 mmseqs prefilter 对 11 aa 短肽全盲，本轮零 mmseqs。"; echo
  echo "## A'. 跨队列一致性（超几何，正态近似）"; echo '```'; cat "$OUT/cross_cohort.tsv"; echo '```'; echo
  echo "## B. 深度校正（uniq=原始，sub=下采样等记录数）"; echo '```'; cat "$OUT/rarefaction.tsv"; echo '```'; echo
  echo "## D. 长度分层"; echo '```'; cat "$OUT/length_strata.tsv"; echo '```'; echo
  echo "## C. k-mer 富集（top10，BH 前 1000 见 kmer_enrichment.tsv）"; echo '```'; head -11 "$OUT/kmer_enrichment.tsv" | cut -c1-150; echo '```'; echo
} > "$OUT/SUMMARY.md"
cat "$OUT/SUMMARY.md"; log "完成: $OUT/SUMMARY.md"
