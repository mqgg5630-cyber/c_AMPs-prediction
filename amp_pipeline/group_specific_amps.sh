#!/bin/bash
# ==============================================================================
# group_specific_amps.sh —— 基于三票 (is_AMP=1) 结果做“组特异性 AMP”集合分析
#
# 思路 (presence/absence, 泛基因组式比较):
#   每组的候选 AMP 视为一个唯一序列集合 S_g。
#   二分类队列 (Cohort2/4):  AD 特异 = S_AD \ S_NC,  NC 特异 = S_NC \ S_AD,  共享 = 交集
#   五阶段队列 (Cohort1/3):  每条 AMP 的“成员模式” (在哪几个阶段出现, 5 位 0/1),
#                            阶段特异 = 只在该阶段出现; 核心 = 五阶段都出现; 并统计全部 31 种模式
#   对特异/共享集合比较: 数量与占比、长度、净电荷、疏水比例、各氨基酸组成, 并给出按三模型平均概率排序的 Top 列表
#
# 用法: bash group_specific_amps.sh <amp_results 目录> [输出目录]
#   默认输出 <仓库>/results/group_specific/ ; 大 FASTA 写到 <输出>/fasta/ (已 gitignore), 汇总表进 git
# ==============================================================================
set -e
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RES_ROOT="$(readlink -f "${1:?用法: bash group_specific_amps.sh <amp_results 目录> [输出目录]}")"
RES="$RES_ROOT/results"
OUT="$(readlink -f -m "${2:-$PROJECT_DIR/results/group_specific}")"
SETS="$OUT/sets"; FA="$OUT/fasta"; mkdir -p "$SETS" "$FA"
SORT="sort -S ${SORT_MEM:-30%} --parallel=$(nproc) -T ${TMPDIR:-$OUT}"
PY="$(command -v python3 || command -v python)"
log(){ echo "[$(date '+%F %T')] $*"; }
[ -d "$RES" ] || { echo "[错误] 找不到 $RES"; exit 1; }

log "输出目录: $OUT"
# ---------------------------------------------------------------- 1. 每组三票 AMP 唯一序列集合
# sets/<Cohort>__<group>.tsv : seq \t mean_prob(att,lstm,bert)   (组内去重, 概率取该序列的值—同一序列各组概率相同)
for f in "$RES"/*/*/aggregated_results.tsv; do
    cohort="$(basename "$(dirname "$(dirname "$f")")")"; grp="$(basename "$(dirname "$f")")"
    o="$SETS/${cohort}__${grp}.tsv"
    [ -s "$o.done" ] && { log "  [已存在] $cohort/$grp"; continue; }
    awk -F'\t' 'NR>1 && $8==1 {print $2"\t"($4+$5+$6)/3}' "$f" | $SORT -u -k1,1 > "$o"
    n=$(wc -l < "$o"); echo "$n" > "$o.done"; log "  $cohort/$grp: 三票唯一 AMP $n 条"
done

# ---------------------------------------------------------------- 2. 二分类队列: AD vs NC 集合运算
binary_cohort() {  # <cohort> <NC group> <AD group>
    local c="$1" nc="$2" ad="$3"
    local A="$SETS/${c}__${ad}.tsv" N="$SETS/${c}__${nc}.tsv"
    local d="$OUT/$c"; mkdir -p "$d"
    join -t $'\t' -v1 "$A" "$N" > "$d/AD_specific.tsv"
    join -t $'\t' -v2 "$A" "$N" > "$d/NC_specific.tsv"
    join -t $'\t' -o 0,1.2 "$A" "$N" > "$d/shared.tsv"
    local nA nN nAs nNs nS
    nA=$(wc -l < "$A"); nN=$(wc -l < "$N"); nAs=$(wc -l < "$d/AD_specific.tsv"); nNs=$(wc -l < "$d/NC_specific.tsv"); nS=$(wc -l < "$d/shared.tsv")
    {
      printf 'set\tn\tpct_of_group\tpct_of_union\n'
      awk -v a=$nA -v n=$nN -v as=$nAs -v ns=$nNs -v s=$nS 'BEGIN{u=as+ns+s; OFS="\t"
        print "AD_total",a,"100.00",sprintf("%.2f",100*a/u)
        print "NC_total",n,"100.00",sprintf("%.2f",100*n/u)
        print "shared",s,sprintf("%.2f",100*s/a)" (of AD) / "sprintf("%.2f",100*s/n)" (of NC)",sprintf("%.2f",100*s/u)
        print "AD_specific",as,sprintf("%.2f",100*as/a),sprintf("%.2f",100*as/u)
        print "NC_specific",ns,sprintf("%.2f",100*ns/n),sprintf("%.2f",100*ns/u)
        print "Jaccard(AD,NC)",sprintf("%.4f",s/u),"",""}'
    } > "$d/set_summary.tsv"
    for s in AD_specific NC_specific shared; do
        { $SORT -t $'\t' -k2,2gr "$d/$s.tsv" 2>/dev/null || true; } | head -200 | awk -F'\t' 'BEGIN{OFS="\t"; print "rank","seq","len","mean_prob"}{print NR,$1,length($1),$2}' > "$d/top200_$s.tsv"
        awk -F'\t' -v p="$s" '{print ">"p"_"NR"\n"$1}' "$d/$s.tsv" > "$FA/${c}_$s.fa"
    done
    "$PY" "$SCRIPT_DIR/peptide_features.py" "$d/features.tsv" "AD_specific=$d/AD_specific.tsv" "NC_specific=$d/NC_specific.tsv" "shared=$d/shared.tsv"
    log "  $c: AD $nA | NC $nN | 共享 $nS | AD特异 $nAs | NC特异 $nNs"
}
log "[2] 二分类队列集合运算"
binary_cohort Cohort2_Matched265_NCvsAD Cohort2_Healthy_NC Cohort2_Disease_AD
binary_cohort Cohort4_Full476_NCvsAD    Cohort4_Healthy_NC Cohort4_Disease_AD

# ---------------------------------------------------------------- 3. 五阶段队列: 成员模式
stage_cohort() {  # <cohort> <prefix>
    local c="$1" p="$2"; local d="$OUT/$c"; mkdir -p "$d"
    local stages=(NC SCS SCD MCI AD)
    # 合并: seq \t prob \t stage  -> 按 seq 聚合成 5 位模式
    for s in "${stages[@]}"; do awk -F'\t' -v s="$s" '{print $1"\t"$2"\t"s}' "$SETS/${c}__${p}_$s.tsv"; done \
      | $SORT -t $'\t' -k1,1 \
      | awk -F'\t' 'BEGIN{OFS="\t"; split("NC SCS SCD MCI AD",S," "); for(i=1;i<=5;i++) idx[S[i]]=i}
          function flush(){ if(seq!=""){ pat=""; k=0; for(i=1;i<=5;i++){pat=pat m[i]; k+=m[i]} print seq,prob,pat,k } }
          $1!=seq { flush(); seq=$1; prob=$2; for(i=1;i<=5;i++) m[i]=0 }
          { m[idx[$3]]=1 }
          END{ flush() }' > "$d/membership.tsv"          # seq prob pattern(NC,SCS,SCD,MCI,AD) n_stages
    # 模式计数
    awk -F'\t' '{c[$3]++} END{for(p in c) print p"\t"c[p]}' "$d/membership.tsv" | $SORT -t $'\t' -k2,2nr \
      | awk -F'\t' 'BEGIN{OFS="\t"; print "pattern_NC_SCS_SCD_MCI_AD","n","stages"}{split("NC SCS SCD MCI AD",S," "); lab=""; for(i=1;i<=5;i++) if(substr($1,i,1)=="1") lab=lab (lab==""?"":"+") S[i]; print $1,$2,lab}' > "$d/pattern_counts.tsv"
    # 每阶段: 总数 / 该阶段特异 / 核心
    {
      printf 'stage\tn_total\tn_stage_specific\tspecific_pct\tn_in_core5\n'
      for i in 1 2 3 4 5; do s=${stages[$((i-1))]}
        awk -F'\t' -v i=$i -v s=$s 'BEGIN{OFS="\t"} substr($3,i,1)=="1"{t++; if($4==1) sp++; if($4==5) co++} END{print s,t,sp,sprintf("%.2f",100*sp/t),co}' "$d/membership.tsv"
      done
    } > "$d/stage_summary.tsv"
    # 阶段特异 FASTA + Top; 核心集
    for i in 1 2 3 4 5; do s=${stages[$((i-1))]}
        awk -F'\t' -v i=$i '$4==1 && substr($3,i,1)=="1"{print $1"\t"$2}' "$d/membership.tsv" > "$d/${s}_specific.tsv"
        { $SORT -t $'\t' -k2,2gr "$d/${s}_specific.tsv" 2>/dev/null || true; } | head -100 | awk -F'\t' 'BEGIN{OFS="\t"; print "rank","seq","len","mean_prob"}{print NR,$1,length($1),$2}' > "$d/top100_${s}_specific.tsv"
        awk -F'\t' -v p="${s}_specific" '{print ">"p"_"NR"\n"$1}' "$d/${s}_specific.tsv" > "$FA/${c}_${s}_specific.fa"
    done
    awk -F'\t' '$4==5{print $1"\t"$2}' "$d/membership.tsv" > "$d/core5.tsv"
    # 单调趋势候选: 只在 MCI+AD (疾病后期) 出现 vs 只在 NC+SCS (早期/健康) 出现
    awk -F'\t' '$3=="00011"{print $1"\t"$2}' "$d/membership.tsv" > "$d/late_only_MCI_AD.tsv"
    awk -F'\t' '$3=="11000"{print $1"\t"$2}' "$d/membership.tsv" > "$d/early_only_NC_SCS.tsv"
    "$PY" "$SCRIPT_DIR/peptide_features.py" "$d/features.tsv" "NC_specific=$d/NC_specific.tsv" "AD_specific=$d/AD_specific.tsv" "core5=$d/core5.tsv" "late_only_MCI_AD=$d/late_only_MCI_AD.tsv" "early_only_NC_SCS=$d/early_only_NC_SCS.tsv"
    log "  $c: 模式表 $d/pattern_counts.tsv ; 核心 $(wc -l < "$d/core5.tsv") 条 ; 仅 MCI+AD $(wc -l < "$d/late_only_MCI_AD.tsv") ; 仅 NC+SCS $(wc -l < "$d/early_only_NC_SCS.tsv")"
}
log "[3] 五阶段队列成员模式"
stage_cohort Cohort1_Matched265_5Stage Cohort1
stage_cohort Cohort3_Full476_5Stage    Cohort3

# ---------------------------------------------------------------- 4. 汇总
{
  echo "# 组特异性 AMP 集合分析 — 自动汇总  ($(date '+%F %T'), $(hostname))"; echo
  for c in Cohort2_Matched265_NCvsAD Cohort4_Full476_NCvsAD; do
    echo "## $c"; echo; echo '```'; column -t -s $'\t' "$OUT/$c/set_summary.tsv" 2>/dev/null || cat "$OUT/$c/set_summary.tsv"; echo '```'; echo
    echo "特征对比 (features.tsv):"; echo '```'; column -t -s $'\t' "$OUT/$c/features.tsv" 2>/dev/null || cat "$OUT/$c/features.tsv"; echo '```'; echo
  done
  for c in Cohort1_Matched265_5Stage Cohort3_Full476_5Stage; do
    echo "## $c"; echo; echo '```'; column -t -s $'\t' "$OUT/$c/stage_summary.tsv" 2>/dev/null || cat "$OUT/$c/stage_summary.tsv"; echo '```'; echo
    echo "成员模式 Top 12:"; echo '```'; head -13 "$OUT/$c/pattern_counts.tsv" | column -t -s $'\t' 2>/dev/null || head -13 "$OUT/$c/pattern_counts.tsv"; echo '```'; echo
    echo "特征对比:"; echo '```'; column -t -s $'\t' "$OUT/$c/features.tsv" 2>/dev/null || cat "$OUT/$c/features.tsv"; echo '```'; echo
  done
} > "$OUT/SUMMARY.md"
rm -rf "$SETS"/*.tsv   # 中间集合较大, 不进 git (保留 .done 计数)
cat "$OUT/SUMMARY.md"
log "完成. 汇总: $OUT/SUMMARY.md ; FASTA: $FA/"
