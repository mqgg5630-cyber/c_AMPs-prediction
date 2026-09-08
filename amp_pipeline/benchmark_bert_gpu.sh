#!/usr/bin/env bash
# 只测试 BERT CUDA 推理吞吐，不运行 Attention/LSTM。
# 用法: BERT_N=10000 BERT_BATCH=64 bash amp_pipeline/benchmark_bert_gpu.sh [total.fa] [outdir]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INPUT="${1:-/home/wsh/UniDL4BioPep-main/comparable_sorf_grouped_catalog/sORF_All_Total.fa}"
OUT="${2:-$PROJECT_DIR/bert_gpu_bench}"
N="${BERT_N:-10000}"
BATCH="${BERT_BATCH:-64}"
ENV_BERT="${ENV_BERT:-$HOME/miniconda3/envs/py36}"
INPUT="$(readlink -f "$INPUT")"; OUT="$(mkdir -p "$OUT" && readlink -f "$OUT")"
[[ -f "$INPUT" ]] || { echo "找不到 FASTA: $INPUT"; exit 1; }
PY="$ENV_BERT/bin/python"; [[ -x "$PY" ]] || { echo "找不到 Python: $PY"; exit 1; }
TOTAL=""
MANIFEST="$(dirname "$INPUT")/group_manifest.tsv"
if [[ -s "$MANIFEST" ]]; then TOTAL=$(awk -F '\t' '$1=="All" && $2=="Total" {print $4; exit}' "$MANIFEST"); fi
TOTAL="${TOTAL:-$(awk '/^>/{n++} END{print n+0}' "$INPUT")}" 
rm -f "$OUT/bench.fa" "$OUT/bert.tsv"
python3 "$SCRIPT_DIR/subset_fasta.py" "$INPUT" "$N" > "$OUT/bench.fa"
ACTUAL=$(awk '/^>/{n++} END{print n+0}' "$OUT/bench.fa")
[[ "$ACTUAL" -gt 0 ]] || { echo 'FASTA 为空'; exit 1; }
export BERT_USE_CUDA=1 BERT_EVAL_BATCH_SIZE="$BATCH" BERT_CHUNK_SIZE="${BERT_CHUNK:-10000}"
"$PY" -c 'import torch; print("torch",torch.__version__,"CUDA",torch.cuda.is_available(),"GPU",torch.cuda.get_device_name(0) if torch.cuda.is_available() else "NONE"); assert torch.cuda.is_available()'
START=$(date +%s)
(cd "$PROJECT_DIR/script" && "$PY" prediction_bert.py "$OUT/bench.fa" "$OUT/bert.tsv")
END=$(date +%s); SEC=$((END-START))
RATE=$(awk -v n="$ACTUAL" -v t="$SEC" 'BEGIN{if(t>0)printf "%.2f",n/t;else print 0}')
ETA=$(awk -v n="$TOTAL" -v r="$RATE" 'BEGIN{if(r>0)printf "%.1f",n/r/3600;else print "NA"}')
REMAIN=$(awk -v n="$TOTAL" -v x="$ACTUAL" 'BEGIN{printf "%.0f",n-x}')
ETA_REMAIN=$(awk -v n="$REMAIN" -v r="$RATE" 'BEGIN{if(r>0)printf "%.1f",n/r/3600;else print "NA"}')
echo "=================================================="
echo "BERT GPU benchmark 完成（只跑 BERT）"
echo "输入总记录 : $TOTAL"
echo "本次测试   : $ACTUAL"
echo "batch      : $BATCH"
echo "耗时       : ${SEC} 秒"
echo "速度       : ${RATE} 条/秒"
echo "全量估算   : ${ETA} 小时"
echo "剩余估算   : ${ETA_REMAIN} 小时"
echo "输出       : $OUT/bert.tsv"
echo "=================================================="
