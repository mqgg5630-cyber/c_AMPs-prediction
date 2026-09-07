#!/bin/bash
# ==============================================================================
# run_unique_pipeline.sh —— 大规模分组 FASTA 的高吞吐三模型预测 (去重一次预测, 结果回填各组)
#
# 为什么不用 run_pipeline_all_groups.sh 直接跑 33 GB:
#   1) 四个队列 (Cohort1..4) 是对同一批 MAG 的不同切分, 同一条肽段会在多个分组里重复出现,
#      逐组跑 = 同一序列被三个模型算 3~4 遍。
#   2) format.pl 会为每条序列生成 300 列 CSV (~900 字节/条), 33 GB FASTA 会膨胀成几百 GB 中间文件。
#   3) 原 prediction_bert.py 的 tokenizer 是纯 Python 逐条 wordpiece, GPU 利用率不到 20%。
#
# 本脚本流程 (全部可断点续跑):
#   [1] 抽取所有分组 .fa 的序列 -> sort -u 全局去重 -> work/unique_seqs.txt   (磁盘排序, 不吃内存)
#   [2] Attention+LSTM 一次性预测唯一序列 -> work/keras_proba.tsv  (att\tlstm)
#   [3] BERT 预测唯一序列 (长度分桶 + fp16)  -> work/bert_proba.tsv
#   [4] 用 join 把概率回填到每个分组 -> results/<Cohort>/<group>/aggregated_results.tsv
#   [5] 汇总 -> results/amp_summary.tsv, results/amp_all_peptides.tsv
#
# 用法:
#   bash amp_pipeline/run_unique_pipeline.sh <grouped_dir> <out_dir>            # 全量
#   bash amp_pipeline/run_unique_pipeline.sh <grouped_dir> <out_dir> bench     # 只抽 20 万条测速 + 预估总时长
#   STEP=join bash amp_pipeline/run_unique_pipeline.sh <grouped_dir> <out_dir> # 只重跑回填/汇总
#
# 后台运行:
#   nohup bash amp_pipeline/run_unique_pipeline.sh /mnt/e/0yzy-ad/comparable_sorf_grouped_catalog amp_results \
#         > run_unique.log 2>&1 &
#   tail -f run_unique.log
#
# 可调环境变量 (GTX 1650 4GB 默认值已调好):
#   BERT_EVAL_BATCH_SIZE=256  BERT_MAX_SEQ_LENGTH=66  BERT_FP16=1
#   TF_PREDICT_BATCH_SIZE=1024 TF_CHUNK_SIZE=50000
#   BENCH_N=200000   SKIP_TOTAL=1 (跳过 sORF_All_Total.fa)   SORT_MEM=40% (sort 可用内存)
#   BERT_CASCADE     级联模式, 决定哪些序列需要跑 BERT (GTX 1650 上 BERT 仅 ~80 条/s, 是唯一瓶颈):
#     strict (默认)  只跑 "Attention >0.5 且 LSTM >0.5" 的序列。三票 is_AMP 与全量跑 BERT 完全一致;
#                    但 is_AMP_flex(>=2票) 对未跑 BERT 的序列不再可信 (汇总表会标注)。BERT 量最少 (~1%)。
#     any            只跑 "Attention 或 LSTM 至少一个 >0.5" 的序列。is_AMP 与 is_AMP_flex 都与全量一致。
#     0              全量跑 BERT (每条都有 bert_prob)。
# ==============================================================================
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GROUPED_DIR="${1:?用法: bash run_unique_pipeline.sh <grouped_dir> <out_dir> [bench]}"
OUT_DIR="${2:?用法: bash run_unique_pipeline.sh <grouped_dir> <out_dir> [bench]}"
MODE="${3:-full}"
STEP="${STEP:-all}"
SKIP_TOTAL="${SKIP_TOTAL:-1}"
BENCH_N="${BENCH_N:-200000}"
BERT_CASCADE="${BERT_CASCADE:-strict}"
case "$BERT_CASCADE" in 1|any) BERT_CASCADE=any;; strict|3|and) BERT_CASCADE=strict;; 0|no|off) BERT_CASCADE=0;; *) echo "[错误] BERT_CASCADE 取值 strict|any|0"; exit 1;; esac
SORT_MEM="${SORT_MEM:-40%}"

CONDA_BASE="$(conda info --base 2>/dev/null || true)"
[ -z "$CONDA_BASE" ] && for c in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/mambaforge" /opt/conda; do [ -d "$c/envs" ] && CONDA_BASE="$c" && break; done
ENV_TF="${ENV_TF:-$CONDA_BASE/envs/camps-tf114}"
ENV_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}"
PY_TF="$ENV_TF/bin/python"
PY_BERT="$ENV_BERT/bin/python"

export BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-512}"
export BERT_MAX_SEQ_LENGTH="${BERT_MAX_SEQ_LENGTH:-66}"
export BERT_FP16="${BERT_FP16:-1}"
export BERT_USE_CUDA="${BERT_USE_CUDA:-auto}"
export TF_PREDICT_BATCH_SIZE="${TF_PREDICT_BATCH_SIZE:-1024}"
export TF_CHUNK_SIZE="${TF_CHUNK_SIZE:-50000}"
export TF_CPP_MIN_LOG_LEVEL=2
export LC_ALL=C   # sort/join 按字节序, 快且一致
# Python 3.6 在 LC_ALL=C 下 stdout 会退化成 ASCII, 打印中文报 UnicodeEncodeError; 强制 UTF-8
export PYTHONIOENCODING=utf-8

# ---------- 预检 ----------
for f in "$PY_TF" "$PY_BERT"; do [ -x "$f" ] || { echo "[错误] 找不到 $f (先跑 setup_envs.sh)"; exit 1; }; done
for m in att.h5 lstm.h5 bert.bin; do [ -f "$PROJECT_DIR/Models/$m" ] || { echo "[错误] 缺 Models/$m"; exit 1; }; done
[ -d "$GROUPED_DIR" ] || { echo "[错误] 分组目录不存在: $GROUPED_DIR"; exit 1; }
GROUPED_DIR="$(readlink -f "$GROUPED_DIR")"

if [ "$MODE" = "bench" ]; then
    OUT_DIR="${OUT_DIR%/}_bench"
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(readlink -f "$OUT_DIR")"
WORK="$OUT_DIR/work"; RES="$OUT_DIR/results"
mkdir -p "$WORK" "$RES"
export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"

LOG() { echo "[$(date '+%F %T')] $*"; }

# 分组文件清单
mapfile -t GROUP_FAS < <(find "$GROUPED_DIR" -mindepth 2 -maxdepth 2 -name '*.fa' | sort)
if [ "$SKIP_TOTAL" = "1" ]; then
    mapfile -t GROUP_FAS < <(printf '%s\n' "${GROUP_FAS[@]}" | grep -v 'sORF_All_Total\.fa$' || true)
fi
[ "${#GROUP_FAS[@]}" -gt 0 ] || { echo "[错误] $GROUPED_DIR 下没有 <Cohort>/<group>.fa"; exit 1; }

echo "=================================================="
echo " 去重一次预测 pipeline"
echo "=================================================="
echo " 分组目录 : $GROUPED_DIR   (${#GROUP_FAS[@]} 个分组 .fa)"
echo " 输出目录 : $OUT_DIR"
echo " 模式     : $MODE   STEP=$STEP"
echo " BERT     : batch=$BERT_EVAL_BATCH_SIZE max_len=$BERT_MAX_SEQ_LENGTH fp16=$BERT_FP16"
echo " Keras    : batch=$TF_PREDICT_BATCH_SIZE chunk=$TF_CHUNK_SIZE"
case "$BERT_CASCADE" in
  strict) echo " 级联     : strict —— BERT 只跑 att>0.5 且 lstm>0.5 的序列 (只保证三票 is_AMP 精确)";;
  any)    echo " 级联     : any —— BERT 只跑 att 或 lstm 至少一票的序列 (三票/两票均精确)";;
  0)      echo " 级联     : 关闭 —— BERT 全量";;
esac
echo "=================================================="

UNIQ="$WORK/unique_seqs.txt"
KERAS_OUT="$WORK/keras_proba.tsv"
BERT_OUT="$WORK/bert_proba.tsv"
MERGED="$WORK/unique_with_proba.tsv"

count_lines() { [ -f "$1" ] && wc -l < "$1" || echo 0; }

# ============================================================
# [1] 全局去重
# ============================================================
if [ "$STEP" = "all" ] || [ "$STEP" = "dedup" ]; then
    if [ -s "$UNIQ" ] && [ -f "$UNIQ.done" ]; then
        LOG "[1/5] 去重结果已存在 ($(count_lines "$UNIQ") 条), 跳过"
    else
        LOG "[1/5] 抽取序列并全局去重 (sort -u, 内存 $SORT_MEM, 临时目录 $TMPDIR) ..."
        t0=$(date +%s)
        if [ "$MODE" = "bench" ]; then
            # 从多个分组各取一段, 拼成 BENCH_N 条 (只做测速)
            per=$(( BENCH_N / ${#GROUP_FAS[@]} + 1 ))
            for fa in "${GROUP_FAS[@]}"; do
                grep -v '^>' "$fa" | head -n "$per" || true
            done | tr 'a-z' 'A-Z' | sort -u -S "$SORT_MEM" --parallel="$(nproc)" | awk -v n="$BENCH_N" 'NR<=n' > "$UNIQ"
        else
            cat "${GROUP_FAS[@]}" | grep -v '^>' | tr 'a-z' 'A-Z' \
                | sort -u -S "$SORT_MEM" --parallel="$(nproc)" -T "$TMPDIR" > "$UNIQ"
        fi
        touch "$UNIQ.done"
        LOG "      唯一序列: $(count_lines "$UNIQ") 条, 用时 $(( $(date +%s) - t0 )) s"
    fi
fi
N_UNIQ=$(count_lines "$UNIQ")

# ============================================================
# [2] Attention + LSTM
# ============================================================
if [ "$STEP" = "all" ] || [ "$STEP" = "keras" ]; then
    if [ "$(count_lines "$KERAS_OUT")" -ge "$N_UNIQ" ] && [ "$N_UNIQ" -gt 0 ]; then
        LOG "[2/5] Keras 结果已完整 ($N_UNIQ 条), 跳过"
    else
        LOG "[2/5] Attention + LSTM 预测 $N_UNIQ 条 (camps-tf114) ..."
        t0=$(date +%s)
        (cd "$PROJECT_DIR/script" && "$PY_TF" predict_keras_unique.py "$UNIQ" "$KERAS_OUT" "$N_UNIQ" 2> >(grep -v -i "numa\|deprecat\|instructions for updating\|^$\|keep_prob\|tf.where" >&2))
        KERAS_SEC=$(( $(date +%s) - t0 ))
        LOG "      Keras 用时 $KERAS_SEC s"
    fi
fi

# ============================================================
# [3] BERT  (级联: 只跑需要 BERT 才能定论的序列)
# ============================================================
BERT_NEED="$WORK/bert_needed.txt"
BERT_NEED_OUT="$WORK/bert_needed_proba.tsv"
GPU_LOG="$WORK/gpu_util.log"
if [ "$STEP" = "all" ] || [ "$STEP" = "bert" ]; then
    # 级联模式与上次不同 -> 旧的 BERT 输出作废
    if [ -f "$BERT_NEED.mode" ] && [ "$(cat "$BERT_NEED.mode")" != "$BERT_CASCADE" ]; then
        LOG "      级联模式由 $(cat "$BERT_NEED.mode") 改为 $BERT_CASCADE, 重新生成 BERT 输入"
        rm -f "$BERT_NEED" "$BERT_NEED.done" "$BERT_NEED.mode" "$BERT_NEED_OUT" "$BERT_OUT" "$BERT_OUT.done"
    fi
    if [ "$(count_lines "$BERT_OUT")" -ge "$N_UNIQ" ] && [ "$N_UNIQ" -gt 0 ] && [ -f "$BERT_OUT.done" ]; then
        LOG "[3/5] BERT 结果已完整 ($N_UNIQ 条), 跳过"
    else
        [ "$(count_lines "$KERAS_OUT")" -ge "$N_UNIQ" ] || { echo "[错误] 需先完成 Keras 步骤"; exit 1; }
        if [ "$BERT_CASCADE" != "0" ]; then
            if [ ! -f "$BERT_NEED.done" ] || [ "$(cat "$BERT_NEED.mode" 2>/dev/null)" != "$BERT_CASCADE" ]; then
                if [ "$BERT_CASCADE" = "strict" ]; then
                    paste "$UNIQ" "$KERAS_OUT" | awk -F'\t' '$2!="NA" && $2>0.5 && $3>0.5{print $1}' > "$BERT_NEED"
                else
                    paste "$UNIQ" "$KERAS_OUT" | awk -F'\t' '$2!="NA" && ($2>0.5 || $3>0.5){print $1}' > "$BERT_NEED"
                fi
                echo "$BERT_CASCADE" > "$BERT_NEED.mode"; touch "$BERT_NEED.done"
                rm -f "$BERT_NEED_OUT" "$BERT_OUT" "$BERT_OUT.done"   # 模式变了, 旧输出作废
            fi
            BERT_INPUT="$BERT_NEED"
        else
            BERT_INPUT="$UNIQ"
        fi
        N_BERT=$(count_lines "$BERT_INPUT")
        LOG "[3/5] BERT 预测 $N_BERT 条 (占唯一序列 $(awk -v a="$N_BERT" -v b="$N_UNIQ" 'BEGIN{printf "%.2f", (b?100*a/b:0)}')%) (py36, GPU) ..."
        # 后台每 30s 采样一次 GPU 利用率, 便于诊断
        if command -v nvidia-smi >/dev/null 2>&1; then
            ( while true; do echo "$(date '+%T') $(nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw,clocks.sm --format=csv,noheader)"; sleep 30; done ) >> "$GPU_LOG" 2>/dev/null &
            GPU_PID=$!
        fi
        t0=$(date +%s)
        if [ "$N_BERT" -gt 0 ]; then
            (cd "$PROJECT_DIR/script" && "$PY_BERT" predict_bert_unique.py "$BERT_INPUT" "$BERT_NEED_OUT" "$N_BERT" 2> >(grep -v "apex\|^$" >&2))
        else
            : > "$BERT_NEED_OUT"
        fi
        [ -n "${GPU_PID:-}" ] && kill "$GPU_PID" 2>/dev/null || true
        BERT_SEC=$(( $(date +%s) - t0 ))
        # 对齐回全部唯一序列: 未跑 BERT 的记 NA (UNIQ 与 BERT_INPUT 均为 C 序排序)
        if [ "$BERT_CASCADE" != "0" ]; then
            paste "$BERT_INPUT" "$BERT_NEED_OUT" > "$WORK/.need_p"
            join -t $'\t' -a1 -e NA -o 2.2 "$UNIQ" "$WORK/.need_p" > "$BERT_OUT"
            rm -f "$WORK/.need_p"
        else
            cp "$BERT_NEED_OUT" "$BERT_OUT"
        fi
        [ "$(count_lines "$BERT_OUT")" -eq "$N_UNIQ" ] || { echo "[错误] BERT 对齐后行数 $(count_lines "$BERT_OUT") != $N_UNIQ"; exit 1; }
        touch "$BERT_OUT.done"
        LOG "      BERT 用时 $BERT_SEC s"
        [ -s "$GPU_LOG" ] && LOG "      GPU 利用率采样 (util, mem, power, sm_clock) 最近 5 条:" && tail -5 "$GPU_LOG" | sed 's/^/        /'
    fi
fi

# ============================================================
# bench 模式: 打印吞吐并预估全量时间
# ============================================================
if [ "$MODE" = "bench" ]; then
    echo ""
    echo "=================================================="
    echo " 测速结果 (唯一序列 $N_UNIQ 条)"
    echo "=================================================="
    KERAS_SEC="${KERAS_SEC:-0}"; BERT_SEC="${BERT_SEC:-0}"
    [ "$KERAS_SEC" -gt 0 ] && echo "  Attention+LSTM : $KERAS_SEC s  => $(( N_UNIQ / KERAS_SEC )) 条/s"
    N_BERT="${N_BERT:-$N_UNIQ}"
    [ "$BERT_SEC" -gt 0 ]  && echo "  BERT           : $BERT_SEC s  => $(( N_BERT / BERT_SEC )) 条/s  (实际跑了 $N_BERT 条)"
    echo ""
    echo "  序列长度分布 (唯一序列):"
    awk '{print length($0)}' "$UNIQ" | sort -n | awk '{a[NR]=$1} END{printf "    n=%d  中位数=%d  P90=%d  P99=%d  最大=%d  >64AA占比=%.1f%%\n", NR, a[int(NR*0.5)], a[int(NR*0.9)], a[int(NR*0.99)], a[NR], 0}' 
    awk '{if(length($0)>64)c++} END{printf "    >64 AA 的序列占 %.2f%% (BERT_MAX_SEQ_LENGTH=66 时这些会被截断到 64 AA)\n", NR?100*c/NR:0}' "$UNIQ"
    echo ""
    NEED_PCT=$(awk -v a="$N_BERT" -v b="$N_UNIQ" 'BEGIN{printf "%.2f", (b?100*a/b:0)}')
    N_AND=$(paste "$UNIQ" "$KERAS_OUT" | awk -F'\t' '$2!="NA" && $2>0.5 && $3>0.5' | wc -l)
    N_OR=$(paste "$UNIQ" "$KERAS_OUT"  | awk -F'\t' '$2!="NA" && ($2>0.5 || $3>0.5)' | wc -l)
    echo "  Keras 初筛 (唯一序列 $N_UNIQ 条):"
    echo "    att>0.5 且 lstm>0.5 (strict, 三票候选) : $N_AND 条  ($(awk -v a=$N_AND -v b=$N_UNIQ 'BEGIN{printf "%.2f",b?100*a/b:0}')%)"
    echo "    att>0.5 或 lstm>0.5 (any)              : $N_OR 条  ($(awk -v a=$N_OR -v b=$N_UNIQ 'BEGIN{printf "%.2f",b?100*a/b:0}')%)"
    echo "  本次级联模式 $BERT_CASCADE, BERT 实际跑 ${NEED_PCT}%"
    echo ""
    echo "  估算全量:"
    TOTAL_RECS=$(cat "${GROUP_FAS[@]}" | grep -c '^>' || echo 0)
    echo "    分组记录总数(含跨队列重复) = $TOTAL_RECS"
    if [ "$BERT_SEC" -gt 0 ] && [ "$N_BERT" -gt 0 ]; then
        rate_b=$(( N_BERT / BERT_SEC )); rate_k=$(( N_UNIQ / (KERAS_SEC>0?KERAS_SEC:1) ))
        for frac in 25 50 100; do
            n=$(( TOTAL_RECS * frac / 100 ))
            nb=$(awk -v n="$n" -v p="$NEED_PCT" 'BEGIN{printf "%d", n*p/100}')
            hk=$(awk -v n="$n" -v r="$rate_k" 'BEGIN{printf "%.1f", n/(r>0?r:1)/3600}')
            hb=$(awk -v n="$nb" -v r="$rate_b" 'BEGIN{printf "%.1f", n/(r>0?r:1)/3600}')
            hb_full=$(awk -v n="$n" -v r="$rate_b" 'BEGIN{printf "%.0f", n/(r>0?r:1)/3600}')
            echo "    若唯一序列占 ${frac}% (= $n 条): Keras ≈ $hk h;  BERT($BERT_CASCADE, ${nb} 条) ≈ $hb h;  [BERT 全量 ≈ $hb_full h]"
        done
    fi
    echo ""
    echo "  测速文件在 $OUT_DIR, 可删除。正式运行去掉 bench 参数。"
    exit 0
fi

# ============================================================
# [4] 回填到各分组 (join 按序列字符串)
# ============================================================
if [ "$STEP" = "all" ] || [ "$STEP" = "join" ]; then
    LOG "[4/5] 合并概率并回填各分组 ..."
    [ "$(count_lines "$KERAS_OUT")" -ge "$N_UNIQ" ] || { echo "[错误] keras_proba.tsv 不完整"; exit 1; }
    [ "$(count_lines "$BERT_OUT")"  -ge "$N_UNIQ" ] || { echo "[错误] bert_proba.tsv 不完整"; exit 1; }
    if [ ! -f "$MERGED.done" ]; then
        # unique_seqs.txt 本身是 sort -u 的输出 (已按 C 序排好) -> 直接 paste
        paste "$UNIQ" "$KERAS_OUT" "$BERT_OUT" > "$MERGED"
        touch "$MERGED.done"
    fi
    for fa in "${GROUP_FAS[@]}"; do
        cohort="$(basename "$(dirname "$fa")")"; grp="$(basename "$fa" .fa)"
        gdir="$RES/$cohort/$grp"; mkdir -p "$gdir"
        if [ -f "$gdir/aggregated_results.tsv.done" ]; then continue; fi
        # 1) 每条记录: idx \t name \t SEQ  (SEQ 大写, 与去重时一致)
        awk 'BEGIN{OFS="\t"} /^>/{name=substr($1,2); next} {i++; print i, name, toupper($0)}' "$fa" \
            | sort -t $'\t' -k3,3 -S "$SORT_MEM" -T "$TMPDIR" > "$gdir/.recs_by_seq"
        # 2) join on SEQ:  SEQ idx name att lstm bert -> 按 idx 还原顺序
        # 输出列: idx name SEQ att lstm bert
        join -t $'\t' -1 3 -2 1 -o 1.1,1.2,0,2.2,2.3,2.4 "$gdir/.recs_by_seq" "$MERGED" \
            | sort -t $'\t' -k1,1n -S "$SORT_MEM" -T "$TMPDIR" \
            | awk 'BEGIN{OFS="\t"; print "name","seq","len","att_prob","lstm_prob","bert_prob","n_votes","is_AMP","AMP_pred","is_AMP_flex"}
                   { v=0; if($4!="NA"&&$4>0.5)v++; if($5!="NA"&&$5>0.5)v++; if($6!="NA"&&$6>0.5)v++;
                     a=(v==3)?1:0; f=(v>=2)?1:0; print $2,$3,length($3),$4,$5,$6,v,a,a,f }' \
            > "$gdir/aggregated_results.tsv"
        n_in=$(grep -c '^>' "$fa" || echo 0); n_out=$(( $(wc -l < "$gdir/aggregated_results.tsv") - 1 ))
        rm -f "$gdir/.recs_by_seq"
        touch "$gdir/aggregated_results.tsv.done"
        LOG "      $cohort/$grp: 输入 $n_in 条, 回填 $n_out 条"
    done
fi

# ============================================================
# [5] 汇总
# ============================================================
if [ "$STEP" = "all" ] || [ "$STEP" = "join" ] || [ "$STEP" = "summary" ]; then
    LOG "[5/5] 生成汇总表 ..."
    SUMMARY="$RES/amp_summary.tsv"; ALL="$RES/amp_all_peptides.tsv"
    printf 'cohort\tgroup\tn_seq\tn_AMP3\tAMP3_pct\tn_AMP_flex2\tAMP_flex2_pct\n' > "$SUMMARY"
    MODE_USED="$(cat "$BERT_NEED.mode" 2>/dev/null || echo 0)"
    if [ "$MODE_USED" = "strict" ]; then
        echo "  [注意] 级联模式 strict: n_AMP3/is_AMP 精确; n_AMP_flex2/is_AMP_flex 为下界 (未跑 BERT 的序列按 0 票计)"
        echo "级联模式 strict: 仅三票 is_AMP 精确; is_AMP_flex 为下界。" > "$RES/README_cascade.txt"
    fi
    printf 'cohort\tgroup\tname\tseq\tlen\tatt_prob\tlstm_prob\tbert_prob\tn_votes\tis_AMP\tis_AMP_flex\n' > "$ALL"
    for fa in "${GROUP_FAS[@]}"; do
        cohort="$(basename "$(dirname "$fa")")"; grp="$(basename "$fa" .fa)"
        f="$RES/$cohort/$grp/aggregated_results.tsv"; [ -s "$f" ] || continue
        awk -v c="$cohort" -v g="$grp" 'BEGIN{OFS="\t"} NR>1{n++; a+=$8; fl+=$10}
             END{printf "%s\t%s\t%d\t%d\t%.2f\t%d\t%.2f\n", c, g, n, a, (n?100*a/n:0), fl, (n?100*fl/n:0)}' "$f" >> "$SUMMARY"
        awk -v c="$cohort" -v g="$grp" 'BEGIN{OFS="\t"} NR>1{print c,g,$1,$2,$3,$4,$5,$6,$7,$8,$10}' "$f" >> "$ALL"
    done
    echo ""; column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
    echo ""
    LOG "完成!  分组汇总: $SUMMARY"
    LOG "        全量肽段: $ALL"
    LOG "        每组明细: $RES/<Cohort>/<group>/aggregated_results.tsv"
fi
