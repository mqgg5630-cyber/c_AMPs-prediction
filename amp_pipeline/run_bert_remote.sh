#!/bin/bash
# ==============================================================================
# run_bert_remote.sh —— 在另一台 GPU 机器上单独跑 BERT (输入: 两票唯一序列 unique_amp2.txt)
#
# 前提 (另一台机器上):
#   1. 有本仓库 (git clone) + Models/bert.bin + conda 环境 py36
#   2. 从主机拷来 unique_amp2.txt (或 unique_amp2.fa, 脚本会自动转成 txt)
#
# 用法:
#   bash amp_pipeline/run_bert_remote.sh <unique_amp2.txt 或 .fa> [输出目录]   # 默认输出目录 bert_remote/
#   MODE=bench bash amp_pipeline/run_bert_remote.sh unique_amp2.txt           # 先抽 5 万条测速并外推
#   支持断点续跑: 中断后重跑同一命令自动接着算 (已完成的行会快速跳过)
#
# 产物:
#   <out>/unique_amp2.txt          与输出逐行对应的输入 (C 序排序, 与主机上的 work/bert_needed.txt 一致)
#   <out>/bert_needed_proba.tsv    BERT 概率, 每行一个, 与 unique_amp2.txt 逐行对应
#   <out>/bert_remote.log
# 拷回主机后: 见脚本末尾打印的接入命令
# ==============================================================================
set -e
set -o pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IN="${1:?用法: bash run_bert_remote.sh <unique_amp2.txt|.fa> [输出目录]}"
IN="$(readlink -f "$IN")"
OUT="$(readlink -f "${2:-$PROJECT_DIR/bert_remote}")"; mkdir -p "$OUT"
MODE="${MODE:-run}"
CONDA_BASE="$(conda info --base 2>/dev/null | grep -m1 "^/" || true)"; [ -d "$CONDA_BASE" ] || CONDA_BASE="$HOME/miniconda3"
PY_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}/bin/python"
[ -x "$PY_BERT" ] || { echo "[错误] 找不到 $PY_BERT (可用 ENV_BERT=/path/to/env 指定)"; exit 1; }
[ -s "$PROJECT_DIR/Models/bert.bin" ] || { echo "[错误] 缺 Models/bert.bin"; exit 1; }

# 大卡默认参数 (A4000 16GB): batch 2048; 1650 请用 512
export BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-2048}"
export BERT_MAX_SEQ_LENGTH="${BERT_MAX_SEQ_LENGTH:-52}"
export BERT_FP16="${BERT_FP16:-1}"
export BERT_NUM_WORKERS="${BERT_NUM_WORKERS:-4}"
export PYTHONIOENCODING=utf-8
LOG="$OUT/bert_remote.log"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# 本地 bert-base-uncased 三件套 (免联网, 秒开)
bash "$SCRIPT_DIR/stage_local_bert_base.sh" 2>&1 | tee -a "$LOG" || true

# 输入统一为 txt (每行一条序列), 并做 C 序排序 (与主机 work/bert_needed.txt 一致, 便于回填)
TXT="$OUT/unique_amp2.txt"
if [ ! -f "$TXT.done" ]; then
    if head -c1 "$IN" | grep -q '>'; then
        grep -v '^>' "$IN" | tr -d '\r' | sort -u -S 40% -T "$OUT" > "$TXT"
    else
        tr -d '\r' < "$IN" | sort -u -S 40% -T "$OUT" > "$TXT"
    fi
    touch "$TXT.done"
fi
N=$(wc -l < "$TXT")
log "输入 $N 条唯一序列  batch=$BERT_EVAL_BATCH_SIZE max_len=$BERT_MAX_SEQ_LENGTH fp16=$BERT_FP16"
nvidia-smi --query-gpu=name,memory.total,power.limit --format=csv,noheader 2>/dev/null | tee -a "$LOG" || true

# ---- bench: 抽样测速 ----
if [ "$MODE" = "bench" ]; then
    NB="${N_BENCH:-50000}"
    shuf -n "$NB" --random-source=<(yes) "$TXT" | sort > "$OUT/bench_sample.txt"
    rm -f "$OUT/bench_proba.tsv"
    t0=$(date +%s)
    (cd "$PROJECT_DIR/script" && "$PY_BERT" predict_bert_unique.py "$OUT/bench_sample.txt" "$OUT/bench_proba.tsv" "$NB" 2> >(grep -v "apex\|^$" >&2))
    el=$(( $(date +%s) - t0 ))
    rate=$(awk -v n=$NB -v e=$el 'BEGIN{print n/e}')
    echo "=================================================="
    printf " 吞吐 %.0f 条/s (含加载, %d 条 / %d s)\n" "$rate" "$NB" "$el"
    printf " 外推全部 %d 条: ≈ %.1f 小时\n" "$N" "$(awk -v n=$N -v r=$rate 'BEGIN{print n/r/3600}')"
    echo " 若 GPU-Util 不到 90%%, 试 BERT_EVAL_BATCH_SIZE=4096 或 BERT_NUM_WORKERS=8"
    echo "=================================================="
    exit 0
fi

# ---- 正式跑 (可断点续跑) ----
PROBA="$OUT/bert_needed_proba.tsv"
done_n=$([ -f "$PROBA" ] && wc -l < "$PROBA" || echo 0)
if [ "$done_n" -ge "$N" ]; then
    log "已完成 ($done_n / $N), 无需再跑"
else
    log "开始 BERT (已完成 $done_n / $N, 继续) ..."
    GPU_LOG="$OUT/gpu_util.log"
    ( while true; do echo "$(date '+%T') $(nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader 2>/dev/null)"; sleep 60; done ) >> "$GPU_LOG" 2>/dev/null &
    GPU_PID=$!
    t0=$(date +%s)
    (cd "$PROJECT_DIR/script" && "$PY_BERT" predict_bert_unique.py "$TXT" "$PROBA" "$N" 2> >(grep -v "apex\|^$" >&2)) 2>&1 | tee -a "$LOG"
    kill "$GPU_PID" 2>/dev/null || true
    log "BERT 用时 $(( $(date +%s) - t0 )) s"
fi
[ "$(wc -l < "$PROBA")" -eq "$N" ] || { log "[错误] 输出行数 $(wc -l < "$PROBA") != $N"; exit 1; }

cat <<EOF

==================================================
 完成: $PROBA  ($N 行)
 拷回主机 (在主机上执行, 改成实际 IP/用户):
   scp -P 2222 wsh@<这台机的IP>:$OUT/{unique_amp2.txt,bert_needed_proba.tsv} ~/c_AMPs-prediction/amp_results/work/
 然后在主机上接入原流程:
   bash amp_pipeline/import_bert_remote.sh amp_results
==================================================
EOF
