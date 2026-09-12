#!/bin/bash
# ==============================================================================
# extract_amp2_fasta.sh —— 从 run_unique_pipeline.sh 的结果中提取 Attention & LSTM 两票都 >0.5 的肽段
#
# 产物 (默认写到 <out_dir>/amp2_fasta/):
#   <Cohort>/<group>.amp2.fa        每组的两票 AMP 候选 (FASTA, header 为原 name, 保留组内重复记录)
#   <Cohort>/<group>.amp2.tsv       同上, 表格: name seq len att_prob lstm_prob
#   unique_amp2.fa / unique_amp2.txt 全部唯一两票序列 (跨组去重, 给 BERT 用; header 为 u<序号>)
#   amp2_counts.tsv                  每组条数汇总
#
# 用法:
#   bash amp_pipeline/extract_amp2_fasta.sh amp_results               # 默认阈值 0.5
#   THRESH=0.9 bash amp_pipeline/extract_amp2_fasta.sh amp_results    # 更严格阈值 (两模型都 >0.9)
#   bash amp_pipeline/extract_amp2_fasta.sh amp_results /path/out     # 指定输出目录
# ==============================================================================
set -e
set -o pipefail
export LC_ALL=C

RES_ROOT="${1:?用法: bash extract_amp2_fasta.sh <amp_results 目录> [输出目录]}"
RES="$RES_ROOT/results"; WORK="$RES_ROOT/work"
OUT="${2:-$RES_ROOT/amp2_fasta}"
THRESH="${THRESH:-0.5}"
[ -d "$RES" ] || { echo "[错误] 找不到 $RES (请传 run_unique_pipeline.sh 的输出目录)"; exit 1; }
mkdir -p "$OUT"

echo "=================================================="
echo " 提取两票 (Attention>$THRESH 且 LSTM>$THRESH) 肽段"
echo " 结果目录 : $RES"
echo " 输出目录 : $OUT"
echo "=================================================="

COUNTS="$OUT/amp2_counts.tsv"
printf 'cohort\tgroup\tn_seq\tn_amp2\tamp2_pct\n' > "$COUNTS"

# ---- 每组 ----
for f in "$RES"/*/*/aggregated_results.tsv; do
    [ -s "$f" ] || continue
    gdir="$(dirname "$f")"; grp="$(basename "$gdir")"; cohort="$(basename "$(dirname "$gdir")")"
    mkdir -p "$OUT/$cohort"
    fa="$OUT/$cohort/$grp.amp2.fa"; tsv="$OUT/$cohort/$grp.amp2.tsv"
    if [ -f "$fa.done" ] && [ "$(cat "$fa.done")" = "$THRESH" ]; then
        echo "  [已存在] $cohort/$grp"; continue
    fi
    # 列: 1 name 2 seq 3 len 4 att 5 lstm 6 bert ...
    awk -F'\t' -v t="$THRESH" -v fa="$fa" -v tsv="$tsv" '
        BEGIN{OFS="\t"; print "name","seq","len","att_prob","lstm_prob" > tsv}
        NR>1 && $4!="NA" && $5!="NA" && $4>t && $5>t {
            print ">"$1 > fa; print $2 > fa
            print $1,$2,$3,$4,$5 > tsv
            n++
        }
        END{ printf "%d\t%d\n", NR-1, n+0 > "/dev/stderr" }' "$f" 2> "$OUT/.cnt"
    read n_all n_amp < "$OUT/.cnt"
    printf '%s\t%s\t%d\t%d\t%.2f\n' "$cohort" "$grp" "$n_all" "$n_amp" "$(awk -v a=$n_amp -v b=$n_all 'BEGIN{print b?100*a/b:0}')" >> "$COUNTS"
    echo "$THRESH" > "$fa.done"
    echo "  $cohort/$grp: $n_amp / $n_all"
done
rm -f "$OUT/.cnt"

# ---- 全局唯一两票序列 (跨组去重, 给 BERT 用) ----
UNIQ_TXT="$OUT/unique_amp2.txt"; UNIQ_FA="$OUT/unique_amp2.fa"
if [ -f "$UNIQ_TXT.done" ] && [ "$(cat "$UNIQ_TXT.done")" = "$THRESH" ]; then
    echo "  [已存在] unique_amp2"
elif [ -s "$WORK/unique_seqs.txt" ] && [ -s "$WORK/keras_proba.tsv" ]; then
    # 快路径: 直接用 pipeline 的唯一序列表
    paste "$WORK/unique_seqs.txt" "$WORK/keras_proba.tsv" \
        | awk -F'\t' -v t="$THRESH" '$2!="NA" && $2>t && $3>t {print $1}' > "$UNIQ_TXT"
    awk '{print ">u"NR; print $0}' "$UNIQ_TXT" > "$UNIQ_FA"
    echo "$THRESH" > "$UNIQ_TXT.done"
else
    cat "$OUT"/*/*.amp2.tsv | awk -F'\t' 'NR>1 && $1!="name"{print $2}' | sort -u -S 40% > "$UNIQ_TXT"
    awk '{print ">u"NR; print $0}' "$UNIQ_TXT" > "$UNIQ_FA"
    echo "$THRESH" > "$UNIQ_TXT.done"
fi
N_U=$(wc -l < "$UNIQ_TXT")

echo ""
column -t -s $'\t' "$COUNTS" 2>/dev/null || cat "$COUNTS"
echo ""
echo " 唯一两票序列 (跨组去重): $N_U 条  -> $UNIQ_FA"
echo " 若跑 BERT: 按 78 条/s ≈ $(awk -v n=$N_U 'BEGIN{printf "%.0f", n/78/3600}') 小时; 按 150 条/s ≈ $(awk -v n=$N_U 'BEGIN{printf "%.0f", n/150/3600}') 小时"
echo ""
echo " 长度分布 (唯一两票序列):"
awk '{print length($0)}' "$UNIQ_TXT" | sort -n | awk '{a[NR]=$1} END{if(NR) printf "   n=%d  中位数=%d  P90=%d  P99=%d  最大=%d\n", NR, a[int(NR*0.5)+1], a[int(NR*0.9)+1], a[int(NR*0.99)+1], a[NR]}'
echo ""
echo " 完成。每组 FASTA: $OUT/<Cohort>/<group>.amp2.fa"
