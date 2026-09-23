#!/bin/bash
# ==============================================================================
# group_specific_analysis2.sh —— 组特异性 AMP 分析 v2（针对短肽、避免假阳性/假阴性结论）
#
# v1 暴露的两个问题，本脚本据此重写：
#   (1) 90% 相似度对 11 aa 短肽没有区分力（压缩比 1.0x，等于没聚类）→ 先做“压缩比曲线”标定阈值
#   (2) sORF 名里没有 MAG/样本信息 → 无法做严格流行率检验；本脚本只做“可辩护”的分析，
#       并把“需要服务器导出哪些文件”写成清单
#
# 产出：
#   A. compression_curve.tsv   子样本(20 万)在 id=0.99/0.9/0.8/0.7/0.6 下的压缩比 → 说明短肽聚类行为
#   B. nn_identity_*.tsv       组特异序列 vs 共享序列 的最近邻同一性分布 → 判断“特异”是否是菌株变异
#   C. family_overlap.tsv      正式阈值(FULL_ID)下家族层面的组间重叠 / 核心家族(14 组共有)
#   D. features_family.tsv     家族层面 AD 特异 vs NC 特异 vs 核心 的理化特征对比
#   E. NEXT_STEPS_SERVER_FILES.md  解锁“每个 AMP 在多少人中出现”所需的最小服务器导出清单
#
# 用法: bash group_specific_analysis2.sh <amp_results 目录> [输出目录]
# 环境变量: MIN_ID(0.7) SAMPLE(200000) SENS(7.5) THREADS
# ==============================================================================
set -e
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RES_ROOT="$(readlink -f "${1:?用法: bash group_specific_analysis2.sh <amp_results> [out]}")"; RES="$RES_ROOT/results"
OUT="$(readlink -f -m "${2:-$PROJECT_DIR/results/group_specific_family2}")"
PREV_WORK="$(readlink -f -m "$PROJECT_DIR/results/group_specific_family/work")"   # v1 已建好的索引，直接复用
W="$OUT/work"; mkdir -p "$W"
FULL_ID="${FULL_ID:-0.7}"; SAMPLE="${SAMPLE:-200000}"; SENS="${SENS:-7.5}"; THREADS="${THREADS:-$(nproc)}"
SORT="sort -S ${SORT_MEM:-30%} --parallel=$THREADS -T ${TMPDIR:-$W}"
PY="$(command -v python3 || command -v python)"; log(){ echo "[$(date '+%F %T')] $*"; }

# ---- mmseqs 定位（PATH -> tools/ 静态二进制）
MM="$(command -v mmseqs || true)"; [ -z "$MM" ] && [ -x "$PROJECT_DIR/tools/mmseqs/bin/mmseqs" ] && MM="$PROJECT_DIR/tools/mmseqs/bin/mmseqs"
[ -n "$MM" ] || { echo "[错误] 找不到 mmseqs (应在 $PROJECT_DIR/tools/mmseqs/bin/mmseqs)"; exit 1; }
log "mmseqs: $MM"

# ---- 复用/重建 索引: all.tsv(seq name group prob) -> uniq.fa / uniq_id2seq.tsv
for f in all.tsv uniq.fa uniq_id2seq.tsv; do [ -s "$PREV_WORK/$f" ] && [ ! -e "$W/$f" ] && ln "$PREV_WORK/$f" "$W/$f" 2>/dev/null || true; done
if [ ! -s "$W/all.tsv" ]; then
  log "[0] 汇总 14 组的三票 AMP (seq, name, group, prob) ..."
  for f in "$RES"/*/*/aggregated_results.tsv; do awk -F'\t' -v g="$(basename "$(dirname "$f")")" 'NR>1 && $8==1 {print $2"\t"$1"\t"g"\t"($4+$5+$6)/3}' "$f"; done | $SORT -k1,1 -k3,3 > "$W/all.tsv"
fi
[ -s "$W/uniq_id2seq.tsv" ] || cut -f1 "$W/all.tsv" | uniq | awk '{print "u"NR"\t"$0}' > "$W/uniq_id2seq.tsv"
[ -s "$W/uniq.fa" ] || cut -f1 "$W/all.tsv" | uniq | awk '{print ">u"NR"\n"$0}' > "$W/uniq.fa"
NU=$(wc -l < "$W/uniq_id2seq.tsv"); log "  唯一三票 AMP: $NU"

# ---- A. 压缩比曲线（子样本）
if [ ! -s "$OUT/compression_curve.tsv" ]; then
  K=$(( NU / SAMPLE + 1 )); log "[A] 压缩比曲线: 每 $K 条取 1 条 (约 $((NU/K)) 条)"
  awk -v k=$K 'NR%k==1' "$W/uniq.fa" > "$W/sub.fa"
  printf 'min_seq_id\tsensitivity\tcov\tclusters\tseqs\tcompression\n' > "$OUT/compression_curve.tsv"
  for id in 0.99 0.9 0.8 0.7 0.6; do
    rm -rf "$W/sub_$id"; "$MM" easy-cluster "$W/sub.fa" "$W/sub_$id" "$W/subtmp_$id" --min-seq-id "$id" -c 0.8 --cov-mode 0 -s "$SENS" --threads "$THREADS" -v 0 >/dev/null 2>&1
    c=$(cut -f1 "$W/sub_${id}_cluster.tsv" 2>/dev/null | $SORT -u | wc -l); s=$(awk 'END{print NR/2}' "$W/sub.fa")
    awk -v i="$id" -v c="$c" -v s="$s" 'BEGIN{printf "%s\t%s\t0.8\t%d\t%d\t%.2fx\n", i, "'"$SENS"'", c, s, s/c}' >> "$OUT/compression_curve.tsv"
    log "    id=$id -> $c 家族 / $s 序列"
    rm -rf "$W/subtmp_$id"
  done
fi

# ---- B. 最近邻同一性：组特异 vs 共享（子样本搜索）
if [ ! -s "$OUT/nn_identity_summary.tsv" ]; then
  log "[B] 最近邻同一性分析 ..."
  # 14 组模式（每条唯一序列在各组是否出现）
  awk -F'\t' '{print $1"\t"$3}' "$W/all.tsv" | $SORT -u | awk -F'\t' '{m[$1]=m[$1]"|"$2} END{for(s in m) print s"\t"m[s]}' | $SORT -k1,1 > "$W/seq_groups.tsv"
  # AD 只出现 / NC 只出现 / 都在 (以 Cohort4 的 AD/NC 两组为定义, 用家族无关的精确序列层面)
  awk -F'\t' '{a=index($2,"Cohort4_Disease_AD")>0; n=index($2,"Cohort4_Healthy_NC")>0; if(a&&!n) print $1 > "'"$W/onlyAD.txt"'"; else if(n&&!a) print $1 > "'"$W/onlyNC.txt"'"; else if(a&&n) print $1 > "'"$W/both.txt"'"}' "$W/seq_groups.tsv"
  for s in onlyAD onlyNC both; do awk 'NR%30==1' "$W/$s.txt" | head -20000 | awk '{print ">"NR"\n"$0}' > "$W/$s.sample.fa"; log "    $s 采样 $(grep -c '^>' "$W/$s.sample.fa")"; done
  : > "$OUT/nn_identity_dist.tsv"; printf 'query_set\ttarget_set\tfident\n' > "$OUT/nn_identity_dist.tsv"
  for q in onlyAD onlyNC both; do for t in onlyAD onlyNC both; do
      { "$MM" easy-search "$W/$q.sample.fa" "$W/$t.sample.fa" "$W/nn_${q}_${t}.m8" "$W/nn_tmp" --min-seq-id 0.5 -s "$SENS" -c 0.5 --cov-mode 0 --max-seqs 1 --format-output "query,target,fident" --threads "$THREADS" -v 0 >/dev/null 2>&1 || true; }
      { awk -v q="$q" -v t="$t" 'BEGIN{OFS="\t"} NF>=3{print q,t,$3}' "$W/nn_${q}_${t}.m8" >> "$OUT/nn_identity_dist.tsv"; } || true
      rm -rf "$W/nn_tmp"
    done; done
  "$PY" - "$OUT/nn_identity_dist.tsv" "$OUT/nn_identity_summary.tsv" <<'PY'
import sys, collections, statistics as st
inp, out = sys.argv[1], sys.argv[2]
d = collections.defaultdict(list)
for i, ln in enumerate(open(inp)):
    if i == 0: continue
    q, t, f = ln.rstrip().split('\t'); d[(q, t)].append(float(f))
rows = ["query_set\ttarget_set\tn_with_hit\tn_query\tpct_with_hit(>=0.5)\tmedian_fident\tp90_fident\tpct_ident>=0.9"]
with open(out, "w") as o:
    o.write(rows[0] + "\n")
    for (q, t), v in sorted(d.items()):
        v.sort(); n = len(v)
        o.write(f"{q}\t{t}\t{n}\t-\t-\t{v[n//2]:.3f}\t{v[int(n*0.9)]:.3f}\t{100*sum(1 for x in v if x>=0.9)/n:.1f}\n")
print(open(out).read())
PY
fi

# ---- C. 正式阈值下的家族层面重叠
if [ ! -s "$OUT/family_overlap.tsv" ]; then
  log "[C] 家族层面重叠 (FULL_ID=$FULL_ID) ..."
  [ -s "$W/clu_cluster.tsv" ] || { log "  聚类 $NU 条 ..."; "$MM" easy-cluster "$W/uniq.fa" "$W/clu" "$W/mmtmp" --min-seq-id "$FULL_ID" -c 0.8 --cov-mode 0 -s "$SENS" --threads "$THREADS" -v 1 >/dev/null; rm -rf "$W/mmtmp"; }
  NF=$(cut -f1 "$W/clu_cluster.tsv" | $SORT -u | wc -l); log "  家族数 $NF (唯一序列 $NU, 压缩比 $(awk -v a=$NU -v b=$NF 'BEGIN{printf "%.2f",a/b}')x)"
  $SORT -k2,2 "$W/clu_cluster.tsv" | join -t $'\t' -1 2 -2 1 -o 1.1,2.2 - <($SORT -k1,1 "$W/uniq_id2seq.tsv") | awk -F'\t' '{print $2"\t"$1}' | $SORT -k1,1 > "$W/seq2fam.tsv"
  $SORT -k1,1 "$W/all.tsv" | join -t $'\t' - "$W/seq2fam.tsv" | awk -F'\t' '{print $5"\t"$3}' | $SORT -u > "$W/fam_group.tsv"    # fam group
  "$PY" - "$W/fam_group.tsv" "$OUT" <<'PY'
import sys, collections, os
inp, out = sys.argv[1], sys.argv[2]
fam = collections.defaultdict(set)
for ln in open(inp):
    f, g = ln.rstrip('\n').split('\t'); fam[f].add(g)
groups = sorted({g for s in fam.values() for g in s})
ALL = set(groups)
core14 = [f for f, s in fam.items() if s == ALL]
lines = ["set_A\tset_B\tshared\tA_only\tB_only\tunion\tjaccard"]
def pair(a, b):
    A = {f for f, s in fam.items() if a in s}; B = {f for f, s in fam.items() if b in s}
    U = A | B; return f"{a}\t{b}\t{len(A&B)}\t{len(A-B)}\t{len(B-A)}\t{len(U)}\t{len(A&B)/len(U):.4f}"
lines.append(pair("Cohort2_Disease_AD", "Cohort2_Healthy_NC"))
lines.append(pair("Cohort4_Disease_AD", "Cohort4_Healthy_NC"))
for a in ("Cohort3_NC", "Cohort3_SCS", "Cohort3_SCD", "Cohort3_MCI", "Cohort3_AD"):
    lines.append(pair("Cohort1_NC", a))
with open(f"{out}/family_overlap.tsv", "w") as o: o.write("\n".join(lines) + "\n")
with open(f"{out}/core14_families.txt", "w") as o:
    for f in core14: o.write(f + "\n")
print("\n".join(lines))
print(f"家族总数 {len(fam)}；14 组全有 (core14) {len(core14)} ({100*len(core14)/len(fam):.2f}%)")
# 家族在 14 组中的出现次数分布
import collections as C
c = C.Counter(len(s) for s in fam.values())
with open(f"{out}/family_occurrence_hist.tsv", "w") as o:
    o.write("n_groups_out_of_14\tn_families\n")
    for k in sorted(c, reverse=True): o.write(f"{k}\t{c[k]}\n")
PY
  # 代表序列 + FASTA
  $SORT -k1,1 "$W/uniq_id2seq.tsv" > "$W/id2seq.sorted"
  join -t $'\t' <($SORT -u "$OUT/core14_families.txt") "$W/id2seq.sorted" > "$OUT/core14_families.tsv" 2>/dev/null || true
  awk -F'\t' '{print ">"$1"\n"$2}' "$OUT/core14_families.tsv" > "$OUT/core14_families.fa"
  # 家族层面的三组集合 (AD 特异 / NC 特异 / 共享), 以 Cohort4 定义, 供特征对比
  "$PY" - "$W/fam_group.tsv" "$OUT" <<'PY'
import sys, collections
inp, out = sys.argv[1], sys.argv[2]
fam = collections.defaultdict(set)
for ln in open(inp):
    f, g = ln.rstrip('\n').split('\t'); fam[f].add(g)
A, N = "Cohort4_Disease_AD", "Cohort4_Healthy_NC"
w = {"AD_only": [], "NC_only": [], "shared": []}
for f, s in fam.items():
    a, n = A in s, N in s
    if a and n: w["shared"].append(f)
    elif a: w["AD_only"].append(f)
    elif n: w["NC_only"].append(f)
for k, v in w.items():
    with open(f"{out}/families_{k}.txt", "w") as o:
        for f in v: o.write(f + "\n")
    print(k, len(v))
PY
fi

# ---- D. 特征对比（家族代表序列）
if [ ! -s "$OUT/features_family.tsv" ]; then
  log "[D] 家族层面特征对比 ..."
  repf="$OUT/core14_families.tsv"
  for k in AD_only NC_only shared core14; do
    ids="$OUT/families_$k.txt"; [ "$k" = core14 ] && ids="$OUT/core14_families.txt"
    $SORT -u "$ids" > "$W/ids_$k"; join -t $'\t' "$W/ids_$k" "$W/id2seq.sorted" | awk -F'\t' '{print $2"\t1"}' > "$W/set_$k.tsv"
  done
  "$PY" "$SCRIPT_DIR/peptide_features.py" "$OUT/features_family.tsv" "AD_only=$W/set_AD_only.tsv" "NC_only=$W/set_NC_only.tsv" "shared=$W/set_shared.tsv" "core14=$W/set_core14.tsv" || true
fi

# ---- E. 服务器导出清单
cat > "$OUT/NEXT_STEPS_SERVER_FILES.md" <<'EOF'
# 解锁“每个 AMP 在多少人中出现”所需的最小服务器导出

本机的所有分析都只能做到**组层面**（哪些序列/家族出现在哪个组），因为预测用的 sORF 名字形如
`k141_32419_170`，只有 contig+ORF 编号，**不带 MAG/样本信息**。要做 AD vs NC 的流行率检验
（Fisher / logistic / 趋势检验），必须从服务器补下面**两样东西**（都不大，几 GB 以内）：

1. `sorf2mag.tsv`（必需，最关键）
   每行一条 sORF：`sORF_name <TAB> MAG_id <TAB> sample_id`
   - 生成方式：建库脚本 `build_grouped_sorf_fasta.py` 已经做过 MAG→样本 的映射，
     把它改成同时输出这张表即可（或在服务器上用 `MAG_Sample_Mapping.tsv` 反查）。
   - 有它之后：每条 AMP 在 476 个样本中的 0/1 矩阵 → 每家族 Fisher 精确检验 + BH、五阶段趋势检验。
2. `sorf_sample_presence.tsv`（可选，等价但更大）
   直接导出 `sORF_name <TAB> sample_id <TAB> 该样本中该 sORF 的覆盖度/丰度`（若有定量结果就更好）。

> 只有第 1 项也能完成全部“存在/缺失”层面的统计；第 2 项的丰度才需要重回 reads/HPC。
> 这两样东西一旦拿到，本机 1 小时内就能出统计检验结果（脚本已备好：`amp_pipeline/prevalence_test.py`）。
EOF

# ---- SUMMARY
{
  echo "# 组特异性 AMP 分析 v2  $(date '+%F %T')  ($(hostname))"; echo
  echo "## A. 短肽聚类压缩比曲线（子样本）"; echo '```'; cat "$OUT/compression_curve.tsv"; echo '```'; echo
  echo "## B. 最近邻同一性（onlyAD / onlyNC / both 互搜，阈值>=0.5）"; echo '```'; cat "$OUT/nn_identity_summary.tsv" 2>/dev/null | cut -c1-160; echo '```'; echo
  echo "## C. 家族层面重叠 (FULL_ID=$FULL_ID)"; echo '```'; cat "$OUT/family_overlap.tsv"; echo '```'
  echo "家族在 14 组中出现的次数分布:"; echo '```'; head -16 "$OUT/family_occurrence_hist.tsv"; echo '```'; echo
  echo "## D. 家族层面特征"; echo '```'; cut -f1-5 "$OUT/features_family.tsv" 2>/dev/null | head -20; echo '```'; echo
  echo "## E. 下一步（服务器文件清单）"; echo "见 NEXT_STEPS_SERVER_FILES.md"; echo
} > "$OUT/SUMMARY.md"
cat "$OUT/SUMMARY.md"; log "完成: $OUT/SUMMARY.md"
