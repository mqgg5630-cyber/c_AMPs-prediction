#!/usr/bin/env bash
# 全局去重 + Attention/LSTM 全量 + BERT cascade。
# 用法:
#   bash run_unique_cascade_pipeline.sh GROUPED_DIR RESULTS_DIR [strict|any|all|bench]
# bench 默认只跑前 MAX_UNIQUE=10000 条，用于给出本机实际速度和全量 ETA。
set -euo pipefail
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$SCRIPTDIR")"
GROUPED="${1:?请输入分组 FASTA 目录}"
RESULTS="${2:?请输入结果目录}"
MODE="${3:-strict}"
[[ "$MODE" =~ ^(strict|any|all|bench)$ ]] || { echo '模式必须是 strict、any、all 或 bench'; exit 2; }
TF_ENV="${ENV_TF:-}"; BERT_ENV="${ENV_BERT:-}"
find_env(){ local x="$1" n="$2"; if [[ -x "$x/bin/python" ]]; then echo "$x"; return; fi; for b in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3"; do [[ -x "$b/envs/$n/bin/python" ]] && { echo "$b/envs/$n"; return; }; done; echo "$x"; }
TF_ENV="$(find_env "${TF_ENV:-camps-tf114}" camps-tf114)"
BERT_ENV="$(find_env "${BERT_ENV:-py36}" py36)"
WORK="$RESULTS/.unique_cascade_work"
MAX=0
if [[ "$MODE" == bench ]]; then
  MAX="${MAX_UNIQUE:-10000}"; MODE_RUN="strict"; WORK="$RESULTS/.unique_cascade_work_bench"
else
  MODE_RUN="$MODE"
fi
mkdir -p "$WORK"
[[ -d "$GROUPED" ]] || { echo "找不到分组目录: $GROUPED"; exit 1; }
[[ -x "$TF_ENV/bin/python" && -x "$BERT_ENV/bin/python" ]] || { echo "找不到环境: TF=$TF_ENV BERT=$BERT_ENV"; exit 1; }
for x in att.h5 lstm.h5 bert.bin; do [[ -f "$PROJECT/Models/$x" ]] || { echo "缺少 Models/$x"; exit 1; }; done
T0=$(date +%s); stamp(){ echo "[$(( $(date +%s)-T0 ))s] $*"; }
count_fa(){ awk '/^>/{n++} END{print n+0}' "$1"; }
TOTAL="$GROUPED/sORF_All_Total.fa"
# 优先从分组脚本生成的 manifest 读取总数，避免为了启动 bench 再扫描数 GB 的 FASTA。
TOTAL_N=""
MANIFEST="$GROUPED/group_manifest.tsv"
if [[ -s "$MANIFEST" ]]; then
  TOTAL_N=$(awk -F '\t' '$1=="All" && $2=="Total" {print $4; exit}' "$MANIFEST")
fi
if [[ -z "$TOTAL_N" ]]; then
  echo "[准备] 未找到 group_manifest.tsv，正在统计 FASTA 记录数；大文件可能需要几分钟..." >&2
  if [[ -f "$TOTAL" ]]; then TOTAL_N=$(count_fa "$TOTAL"); else TOTAL_N=$(find "$GROUPED" -type f -name '*.fa' ! -name sORF_All_Total.fa -print0 | xargs -0 awk '/^>/{n++} END{print n+0}') ; fi
fi
TOTAL_N="${TOTAL_N:-0}"
stamp "模式=$MODE_RUN；输入记录约 $TOTAL_N 条；严格三票筛选: att>0.5 且 lstm>0.5"
if [[ "$MODE" == bench ]]; then stamp "bench 只取前 $MAX 条唯一序列；正式运行请把第三参数改为 strict"; fi

# 1. 建立全局唯一 FASTA 和磁盘 SQLite 索引
"$BERT_ENV/bin/python" "$SCRIPTDIR/cascade_manifest.py" prepare --grouped "$GROUPED" --work "$WORK" --max-unique "$MAX" | tee "$WORK/prepare.log"
UNIQUE=$(sed -n 's/^UNIQUE_COUNT=//p' "$WORK/prepare.log" | tail -1)
[[ -n "$UNIQUE" ]] || { echo '无法读取唯一序列数'; exit 1; }
if (( UNIQUE == 0 )); then echo '没有可预测序列'; exit 0; fi

# 2. format + Attention + LSTM。模型脚本只看到标准 20-AA 序列，因此行数可严格对齐。
FORM="$WORK/unique_formatted_300.txt"
if [[ ! -s "$FORM" ]]; then perl "$PROJECT/script/format.pl" "$WORK/unique.fa" none > "$FORM"; fi
export TF_CHUNK_SIZE="${TF_CHUNK_SIZE:-20000}" TF_PREDICT_BATCH_SIZE="${TF_PREDICT_BATCH_SIZE:-1024}"
ATT="$WORK/attention.tsv"; LSTM="$WORK/lstm.tsv"
if [[ ! -s "$ATT" ]]; then (cd "$PROJECT/script" && "$TF_ENV/bin/python" prediction_attention.py "$FORM" "$ATT"); fi
if [[ ! -s "$LSTM" ]]; then (cd "$PROJECT/script" && "$TF_ENV/bin/python" prediction_lstm.py "$FORM" "$LSTM"); fi
NOW=$(date +%s); RATE=$(awk -v n="$UNIQUE" -v t="$((NOW-T0))" 'BEGIN{if(t>0)printf "%.2f",n/t;else print 0}')
ETA=$(awk -v n="$TOTAL_N" -v r="$RATE" 'BEGIN{if(r>0)printf "%.1f",n/r/3600;else print "NA"}')
stamp "Attention+LSTM 完成；唯一序列=$UNIQUE；阶段总速率约 ${RATE}/秒；按输入量估算 Keras 阶段约 ${ETA} 小时"

# 3. 只把可能成为三票的序列交给 BERT
"$BERT_ENV/bin/python" "$SCRIPTDIR/cascade_manifest.py" select --grouped "$GROUPED" --work "$WORK" --att "$ATT" --lstm "$LSTM" --mode "$MODE_RUN" | tee "$WORK/select.log"
CAND=$(sed -n 's/^CANDIDATE_COUNT=//p' "$WORK/select.log" | tail -1)
PCT=$(sed -n 's/^CANDIDATE_PERCENT=//p' "$WORK/select.log" | tail -1)
: > "$WORK/bert.tsv"
if (( CAND > 0 )); then
  export BERT_USE_CUDA="${BERT_USE_CUDA:-auto}" BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-64}"
  (cd "$PROJECT/script" && "$BERT_ENV/bin/python" prediction_bert.py "$WORK/candidates.fa" "$WORK/bert.tsv")
fi
NOW=$(date +%s); BRATE=$(awk -v n="$CAND" -v t="$((NOW-T0))" 'BEGIN{if(t>0)printf "%.2f",n/t;else print 0}')
BETA=$(awk -v n="$CAND" -v r="$BRATE" 'BEGIN{if(r>0)printf "%.1f",n/r/3600;else print "NA"}')
stamp "BERT strict 候选=$CAND，占有效序列 ${PCT}%；当前累计 BERT 速率约 ${BRATE}/秒，候选阶段约 ${BETA} 小时"
if [[ "$MODE" == bench ]]; then
  stamp "BENCH 完成：以上是本机实测上限参考；正式运行: bash $0 '$GROUPED' '$RESULTS' strict"
  exit 0
fi

# 4. 回填每个分组，并使用原始 result.pl 生成三票结果。
"$BERT_ENV/bin/python" "$SCRIPTDIR/cascade_manifest.py" materialize --grouped "$GROUPED" --work "$WORK" --bert "$WORK/bert.tsv" | tee "$WORK/materialize.log"
while IFS=$'\t' read -r group path count; do :; done < /dev/null
while IFS= read -r d; do
  [[ -f "$d/input.fa" ]] || continue
  "$PROJECT/script/result.pl" "$d/attention_proba.tsv" "$d/lstm_proba.tsv" "$d/bert_proba.tsv" "$d/input.fa" > "$d/final_prediction.txt"
done < <(find "$WORK/results" -type f -name input.fa -printf '%h\n')
# 将工作结果复制到用户指定结果目录（保留工作目录以支持续跑）
rm -rf "$RESULTS/cascade_results"
cp -a "$WORK/results" "$RESULTS/cascade_results"
NOW=$(date +%s); stamp "全部完成；结果目录=$RESULTS/cascade_results；总耗时 $((NOW-T0)) 秒 ($(( (NOW-T0)/3600 )) 小时)"
echo "三票结果文件: $RESULTS/cascade_results/*/*/final_prediction.txt"
