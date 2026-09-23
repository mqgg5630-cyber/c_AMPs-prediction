#!/bin/bash
# ==============================================================================
# group_specific_family.sh —— 家族层面的组特异性 AMP 分析 (修正精确序列层面的组装/菌株噪声)
#
#  1. 全部三票 AMP 唯一序列 -> mmseqs easy-cluster (默认 --min-seq-id 0.9 -c 0.8, 双向覆盖) -> 家族
#  2. 每组: 家族集合 (组内任一成员出现即算), 以及每个家族在该组中出现的 MAG 数 (从 sORF 名解析, 作为流行率代理)
#  3. 二分类队列: 家族层面 AD/NC 特异与共享 + 按 MAG 数归一化的富集 (log2 ratio, Fisher 精确检验 + BH)
#  4. 五阶段队列: 家族层面成员模式 + 每家族各阶段 MAG 数
# 用法: bash group_specific_family.sh <amp_results 目录> [输出目录] ; 环境变量 MIN_ID(0.9) COV(0.8) THREADS
# ==============================================================================
set -e
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RES_ROOT="$(readlink -f "${1:?用法: bash group_specific_family.sh <amp_results> [out]}")"; RES="$RES_ROOT/results"
OUT="$(readlink -f -m "${2:-$PROJECT_DIR/results/group_specific_family}")"; W="$OUT/work"; mkdir -p "$W"
MIN_ID="${MIN_ID:-0.9}"; COV="${COV:-0.8}"; THREADS="${THREADS:-$(nproc)}"
SORT="sort -S ${SORT_MEM:-30%} --parallel=$THREADS -T ${TMPDIR:-$W}"
PY="$(command -v python3 || command -v python)"
log(){ echo "[$(date '+%F %T')] $*"; }

# ---- mmseqs: 找不到就装到 conda env
MM="$(command -v mmseqs || true)"
if [ -z "$MM" ]; then
  CB="$(conda info --base 2>/dev/null | grep -m1 '^/' || echo "$HOME/miniconda3")"
  [ -x "$CB/envs/mmseqs2/bin/mmseqs" ] || { log "安装 mmseqs2 (conda, bioconda) ..."; "$CB/bin/conda" create -y -q -n mmseqs2 -c conda-forge -c bioconda mmseqs2 >/dev/null 2>&1 || "$CB/bin/conda" create -y -n mmseqs2 -c conda-forge -c bioconda mmseqs2; }
  MM="$CB/envs/mmseqs2/bin/mmseqs"
  [ -x "$MM" ] || { echo "[错误] mmseqs2 安装失败 ($MM 不存在). 手动: conda create -n mmseqs2 -c conda-forge -c bioconda mmseqs2"; exit 1; }
fi
log "mmseqs: $MM ($($MM version 2>/dev/null | head -1))"

# ---- 1. 三票 AMP: seq \t name(首个) \t 组列表 ; 同时解析 MAG id
# sORF name 形如 sORF_<MAG>_<n> / <MAG>__bin.X_k141_... ; 用可配置的正则 MAG_RE 抽取, 默认取去掉末尾 _数字 后的前缀
MAG_RE="${MAG_RE:-}"
if [ ! -s "$W/all.tsv.done" ]; then
  log "[1] 汇总各组三票 AMP (seq, name, group) ..."
  for f in "$RES"/*/*/aggregated_results.tsv; do
    grp="$(basename "$(dirname "$f")")"
    awk -F'\t' -v g="$grp" 'NR>1 && $8==1 {print $2"\t"$1"\t"g"\t"($4+$5+$6)/3}' "$f"
  done | $SORT -k1,1 -k3,3 > "$W/all.tsv"        # seq name group prob
  head -3 "$W/all.tsv" | cut -f2 > "$W/name_samples.txt"
  touch "$W/all.tsv.done"
fi
log "  sORF 名示例: $(paste -sd' | ' "$W/name_samples.txt")"
# MAG id 解析函数 (python, 便于正则)
"$PY" - "$W/all.tsv" "$W/seq_group_mag.tsv" "$MAG_RE" <<'PY'
import sys, re
inp, out, pat = sys.argv[1], sys.argv[2], sys.argv[3]
rx = re.compile(pat) if pat else None
def mag(name):
    if rx:
        m = rx.search(name); return m.group(1) if m else name
    n = name.split()[0]
    n = re.sub(r'^sORF_', '', n)
    # k141_/NODE_ contig ids carry no MAG -> keep the contig id (each contig ~ one MAG anyway)
    n = re.sub(r'_\d+$', '', n)          # drop trailing _serial
    n = re.sub(r'_\[.*$', '', n)
    return n
seen = 0
with open(inp) as f, open(out, 'w') as o:
    for ln in f:
        seq, name, grp, prob = ln.rstrip('\n').split('\t')
        o.write(f"{seq}\t{grp}\t{mag(name)}\t{prob}\n"); seen += 1
print("parsed", seen)
PY
# 每组 MAG 总数 (归一化分母)
awk -F'\t' '{print $2"\t"$3}' "$W/seq_group_mag.tsv" | $SORT -u | awk -F'\t' '{c[$1]++} END{for(g in c) print g"\t"c[g]}' | sort > "$OUT/mags_per_group.tsv"
log "  每组 MAG 数: $(awk '{printf "%s=%s ", $1,$2}' "$OUT/mags_per_group.tsv")"

# ---- 2. 聚类
if [ ! -s "$W/clu_cluster.tsv" ]; then
  cut -f1 "$W/all.tsv" | uniq | awk '{print ">u"NR"\n"$0}' > "$W/uniq.fa"
  cut -f1 "$W/all.tsv" | uniq | awk '{print "u"NR"\t"$0}' > "$W/uniq_id2seq.tsv"
  N=$(wc -l < "$W/uniq_id2seq.tsv"); log "[2] mmseqs easy-cluster $N 条 (min-seq-id $MIN_ID, cov $COV, 双向) ..."
  "$MM" easy-cluster "$W/uniq.fa" "$W/clu" "$W/mmtmp" --min-seq-id "$MIN_ID" -c "$COV" --cov-mode 0 --threads "$THREADS" -v 1 >/dev/null
  rm -rf "$W/mmtmp"
fi
NF=$(cut -f1 "$W/clu_cluster.tsv" | $SORT -u | wc -l); NU=$(wc -l < "$W/uniq_id2seq.tsv")
log "  家族数: $NF  (唯一序列 $NU, 压缩比 $(awk -v a=$NU -v b=$NF 'BEGIN{printf "%.1f", a/b}')x)"
# seq -> family(代表序列 id)
$SORT -k2,2 "$W/clu_cluster.tsv" | join -t $'\t' -1 2 -2 1 -o 1.1,2.2 - <($SORT -k1,1 "$W/uniq_id2seq.tsv") | awk -F'\t' '{print $2"\t"$1}' | $SORT -k1,1 > "$W/seq2fam.tsv"   # seq fam
join -t $'\t' <(cut -f1 "$W/clu_cluster.tsv" | $SORT -u) <($SORT -k1,1 "$W/uniq_id2seq.tsv") > "$OUT/family_representatives.tsv"   # fam repseq

# ---- 3. 家族 x 组: 成员序列数, MAG 数
$SORT -k1,1 "$W/seq_group_mag.tsv" | join -t $'\t' - "$W/seq2fam.tsv" | awk -F'\t' 'BEGIN{OFS="\t"}{print $5,$2,$3,$4}' | $SORT -k1,1 -k2,2 -k3,3 -u > "$W/fam_group_mag.tsv"   # fam grp mag prob
awk -F'\t' 'BEGIN{OFS="\t"}{k=$1"\t"$2; n[k]++; if($4>p[k])p[k]=$4} END{for(k in n) print k,n[k],p[k]}' "$W/fam_group_mag.tsv" | $SORT -k1,1 -k2,2 > "$W/fam_group_stats.tsv"   # fam grp n_mags maxprob

# ---- 4. 分析 (python)
"$PY" - "$W/fam_group_stats.tsv" "$OUT/mags_per_group.tsv" "$OUT/family_representatives.tsv" "$OUT" <<'PY'
import sys, math, collections, itertools
stats, mpg, reps, out = sys.argv[1:5]
MAGS = dict(l.split('\t') for l in open(mpg).read().splitlines()); MAGS = {k:int(v) for k,v in MAGS.items()}
REP = dict(l.split('\t',1) for l in open(reps).read().splitlines())
fam = collections.defaultdict(dict)
for ln in open(stats):
    f, g, n, p = ln.rstrip('\n').split('\t'); fam[f][g] = (int(n), float(p))
def fisher(a,b,c,d):  # right-tail and two-sided via hypergeometric (log-space)
    from math import lgamma, exp, log
    def lchoose(n,k): return lgamma(n+1)-lgamma(k+1)-lgamma(n-k+1)
    n=a+b+c+d; r1=a+b; c1=a+c
    lo=max(0,r1+c1-n); hi=min(r1,c1)
    ps={x: exp(lchoose(r1,x)+lchoose(n-r1,c1-x)-lchoose(n,c1)) for x in range(lo,hi+1)}
    p0=ps[a]; return min(1.0, sum(v for v in ps.values() if v<=p0*1.0000001))
def bh(ps):
    m=len(ps); order=sorted(range(m), key=lambda i: ps[i]); q=[0]*m; prev=1.0
    for rank,i in reversed(list(enumerate(order,1))):
        prev=min(prev, ps[i]*m/rank); q[i]=prev
    return q
def binary(cohort, gNC, gAD, tag):
    nNC, nAD = MAGS[gNC], MAGS[gAD]; rows=[]
    S_AD={f for f in fam if gAD in fam[f]}; S_NC={f for f in fam if gNC in fam[f]}
    sh=S_AD&S_NC; onlyA=S_AD-S_NC; onlyN=S_NC-S_AD; U=S_AD|S_NC
    with open(f"{out}/{cohort}/family_set_summary.tsv","w") as o:
        o.write("set\tn_families\tpct_of_union\n")
        for k,v in (("AD_total",len(S_AD)),("NC_total",len(S_NC)),("shared",len(sh)),("AD_specific",len(onlyA)),("NC_specific",len(onlyN))): o.write(f"{k}\t{v}\t{100*v/len(U):.2f}\n")
        o.write(f"Jaccard\t{len(sh)/len(U):.4f}\t\nMAGs_AD\t{nAD}\t\nMAGs_NC\t{nNC}\t\n")
    for f in U:
        a=fam[f].get(gAD,(0,0))[0]; c=fam[f].get(gNC,(0,0))[0]
        if a+c<3: continue                       # 至少 3 个 MAG 才检验
        p=fisher(a,nAD-a,c,nNC-c); l2=math.log2(((a+0.5)/nAD)/((c+0.5)/nNC))
        rows.append([f,a,c,f"{100*a/nAD:.2f}",f"{100*c/nNC:.2f}",f"{l2:.2f}",p])
    qs=bh([r[6] for r in rows]) if rows else []
    for r,q in zip(rows,qs): r.append(q)
    rows.sort(key=lambda r:(r[7], -abs(float(r[5]))))
    with open(f"{out}/{cohort}/family_enrichment.tsv","w") as o:
        o.write("family\tmags_AD\tmags_NC\tprev_AD_pct\tprev_NC_pct\tlog2_ratio_AD_vs_NC\tfisher_p\tBH_q\tdirection\trep_seq\n")
        for r in rows: o.write("\t".join(map(str,r[:6]))+f"\t{r[6]:.3g}\t{r[7]:.3g}\t{'AD_enriched' if float(r[5])>0 else 'NC_enriched'}\t{REP.get(r[0],'')}\n")
    sig=[r for r in rows if r[7]<0.05]; up=sum(1 for r in sig if float(r[5])>0)
    with open(f"{out}/{cohort}/family_set_summary.tsv","a") as o:
        o.write(f"tested_families(>=3 MAGs)\t{len(rows)}\t\nBH_q<0.05\t{len(sig)}\t\n  AD_enriched\t{up}\t\n  NC_enriched\t{len(sig)-up}\t\n")
    print(f"{cohort}: families AD {len(S_AD)} NC {len(S_NC)} shared {len(sh)} ({100*len(sh)/len(U):.1f}% of union) | tested {len(rows)} | q<0.05: {len(sig)} (AD-enriched {up}, NC-enriched {len(sig)-up})")
def stages(cohort, pre):
    st=["NC","SCS","SCD","MCI","AD"]; gs=[f"{pre}_{s}" for s in st]; n=[MAGS[g] for g in gs]
    pat=collections.Counter(); rows=[]
    for f in fam:
        m=[fam[f].get(g,(0,0))[0] for g in gs]; p="".join('1' if x else '0' for x in m)
        if p=="00000": continue
        pat[p]+=1; prev=[100*x/nn for x,nn in zip(m,n)]
        # Spearman-like trend: correlation of prevalence with stage index 0..4
        k=5; xs=range(k); mx=2.0; my=sum(prev)/k
        num=sum((x-mx)*(y-my) for x,y in zip(xs,prev)); den=math.sqrt(sum((x-mx)**2 for x in xs)*sum((y-my)**2 for y in prev))
        r=num/den if den else 0.0
        if sum(m)>=3: rows.append([f]+m+[f"{v:.2f}" for v in prev]+[f"{r:.3f}",REP.get(f,'')])
    with open(f"{out}/{cohort}/family_pattern_counts.tsv","w") as o:
        o.write("pattern_NC_SCS_SCD_MCI_AD\tn_families\tstages\n")
        for p,c in pat.most_common(): o.write(f"{p}\t{c}\t{'+'.join(s for s,b in zip(st,p) if b=='1')}\n")
    rows.sort(key=lambda r: -abs(float(r[11])))
    with open(f"{out}/{cohort}/family_stage_trend.tsv","w") as o:
        o.write("family\t"+"\t".join("mags_"+s for s in st)+"\t"+"\t".join("prev_"+s+"_pct" for s in st)+"\ttrend_r\trep_seq\n")
        for r in rows: o.write("\t".join(map(str,r))+"\n")
    core=pat["11111"]; tot=sum(pat.values())
    inc=sum(1 for r in rows if float(r[11])>0.8); dec=sum(1 for r in rows if float(r[11])<-0.8)
    with open(f"{out}/{cohort}/family_stage_summary.tsv","w") as o:
        o.write("metric\tvalue\n"); o.write(f"families_total\t{tot}\ncore_all5\t{core}\ncore_pct\t{100*core/tot:.2f}\n")
        for s,g,nn in zip(st,gs,n): o.write(f"families_{s}\t{sum(1 for f in fam if g in fam[f])}\nMAGs_{s}\t{nn}\nstage_specific_{s}\t{pat[''.join('1' if t==s else '0' for t in st)]}\n")
        o.write(f"trend_r>0.8(increasing_with_stage,>=3MAGs)\t{inc}\ntrend_r<-0.8(decreasing)\t{dec}\n")
    print(f"{cohort}: families {tot}, core(all 5) {core} ({100*core/tot:.1f}%), increasing {inc}, decreasing {dec}")
import os
for c in ("Cohort2_Matched265_NCvsAD","Cohort4_Full476_NCvsAD","Cohort1_Matched265_5Stage","Cohort3_Full476_5Stage"): os.makedirs(f"{out}/{c}",exist_ok=True)
binary("Cohort2_Matched265_NCvsAD","Cohort2_Healthy_NC","Cohort2_Disease_AD","Cohort2")
binary("Cohort4_Full476_NCvsAD","Cohort4_Healthy_NC","Cohort4_Disease_AD","Cohort4")
stages("Cohort1_Matched265_5Stage","Cohort1")
stages("Cohort3_Full476_5Stage","Cohort3")
PY
{
  echo "# 家族层面组特异性 AMP 分析 (mmseqs id>=$MIN_ID cov>=$COV)  $(date '+%F %T')"; echo
  echo "sORF 名示例: $(paste -sd' | ' "$W/name_samples.txt")"; echo
  echo "每组 MAG 数:"; echo '```'; cat "$OUT/mags_per_group.tsv"; echo '```'; echo
  for c in Cohort2_Matched265_NCvsAD Cohort4_Full476_NCvsAD; do echo "## $c"; echo '```'; cat "$OUT/$c/family_set_summary.tsv"; echo '```'; echo "Top 15 富集家族 (BH q 升序):"; echo '```'; head -16 "$OUT/$c/family_enrichment.tsv" | cut -f1-9; echo '```'; echo; done
  for c in Cohort1_Matched265_5Stage Cohort3_Full476_5Stage; do echo "## $c"; echo '```'; cat "$OUT/$c/family_stage_summary.tsv"; echo '```'; echo "成员模式 Top 12:"; echo '```'; head -13 "$OUT/$c/family_pattern_counts.tsv"; echo '```'; echo "趋势最强家族 Top 10 (|r|):"; echo '```'; head -11 "$OUT/$c/family_stage_trend.tsv" | cut -f1-12; echo '```'; echo; done
} > "$OUT/SUMMARY.md"
cat "$OUT/SUMMARY.md"; log "完成: $OUT/SUMMARY.md"
for c in Cohort2_Matched265_NCvsAD Cohort4_Full476_NCvsAD; do head -501 "$OUT/$c/family_enrichment.tsv" > "$OUT/$c/family_enrichment_top500.tsv"; done
for c in Cohort1_Matched265_5Stage Cohort3_Full476_5Stage; do head -501 "$OUT/$c/family_stage_trend.tsv" > "$OUT/$c/family_stage_trend_top500.tsv"; done
