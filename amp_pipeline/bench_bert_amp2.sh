#!/bin/bash
# ==============================================================================
# bench_bert_amp2.sh —— 在两票唯一序列上抽样测 BERT 吞吐, 外推全部两票序列所需时间
#
# 用法:
#   bash amp_pipeline/bench_bert_amp2.sh amp_results                 # 默认抽 20000 条, batch 512
#   N=50000 BERT_EVAL_BATCH_SIZE=1024 bash amp_pipeline/bench_bert_amp2.sh amp_results
#   BERT_MAX_SEQ_LENGTH=52 bash amp_pipeline/bench_bert_amp2.sh amp_results   # 序列都 <=50AA 时可再提速
# 先运行 extract_amp2_fasta.sh 生成 amp2_fasta/unique_amp2.txt
# ==============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RES_ROOT="${1:?用法: bash bench_bert_amp2.sh <amp_results 目录>}"
UNIQ="$RES_ROOT/amp2_fasta/unique_amp2.txt"
[ -s "$UNIQ" ] || { echo "[错误] 找不到 $UNIQ, 先运行: bash amp_pipeline/extract_amp2_fasta.sh $RES_ROOT"; exit 1; }
N="${N:-20000}"
CONDA_BASE="$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")"
PY_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}/bin/python"
export BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-512}"
export BERT_MAX_SEQ_LENGTH="${BERT_MAX_SEQ_LENGTH:-66}"
export BERT_FP16="${BERT_FP16:-1}"
export PYTHONIOENCODING=utf-8

W="$RES_ROOT/bert_bench"; mkdir -p "$W"
TOTAL=$(wc -l < "$UNIQ")
shuf -n "$N" --random-source=<(yes) "$UNIQ" > "$W/sample.txt"
echo "=================================================="
echo " BERT 测速: 从 $TOTAL 条两票唯一序列中抽 $N 条"
echo " batch=$BERT_EVAL_BATCH_SIZE max_len=$BERT_MAX_SEQ_LENGTH fp16=$BERT_FP16"
echo "=================================================="
nvidia-smi --query-gpu=name,power.draw,clocks.sm,clocks.max.sm --format=csv 2>/dev/null || true
rm -f "$W/sample_proba.tsv"
t0=$(date +%s.%N)
(cd "$PROJECT_DIR/script" && "$PY_BERT" predict_bert_unique.py "$W/sample.txt" "$W/sample_proba.tsv" "$N" 2>&1 | grep -v "apex\|INFO\|^ *\"\|^}\|^{\|Defaulting\|Building\|Loading model")
t1=$(date +%s.%N)
# 用脚本自身报告的纯预测耗时更准; 这里再算一遍含加载的总时长
n_done=$(wc -l < "$W/sample_proba.tsv")
el=$(awk -v a=$t0 -v b=$t1 'BEGIN{print b-a}')
rate=$(awk -v n=$n_done -v e=$el 'BEGIN{print n/e}')
echo ""
echo "=================================================="
printf " 含模型加载的总吞吐: %.0f 条/s (%d 条 / %.0f s)\n" "$rate" "$n_done" "$el"
echo " (上方 [BERT] 完成 行里的 条/s 是纯预测吞吐, 以它外推更准)"
for r in "$rate"; do
  h=$(awk -v n=$TOTAL -v r=$r 'BEGIN{printf "%.1f", n/r/3600}')
  echo " 外推全部 $TOTAL 条两票序列: ≈ $h 小时 (≈ $(awk -v h=$h 'BEGIN{printf "%.1f", h/24}') 天)"
done
echo "=================================================="
echo " 想更快: 插电+Windows 电源'最佳性能'; 试 BERT_EVAL_BATCH_SIZE=1024; 序列都<=50AA 时 BERT_MAX_SEQ_LENGTH=52"
echo " 阈值收紧 (THRESH=0.8/0.9 重跑 extract_amp2_fasta.sh) 可大幅减少需要 BERT 的条数"
