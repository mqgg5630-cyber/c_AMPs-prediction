#!/bin/bash
# ==============================================================================
# import_bert_remote.sh —— 把另一台机器算好的 BERT 结果接入主机的 run_unique_pipeline 流程,
#                          然后重新合并/回填/汇总 (得到 n_AMP3 / is_AMP 三票结果)
#
# 前提: 已把远端的 unique_amp2.txt 与 bert_needed_proba.tsv 拷到 <amp_results>/work/
# 用法: bash amp_pipeline/import_bert_remote.sh amp_results [grouped_dir]
# ==============================================================================
set -e
set -o pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES_ROOT="$(readlink -f "${1:?用法: bash import_bert_remote.sh <amp_results 目录>}")"
WORK="$RES_ROOT/work"
UNIQ="$WORK/unique_seqs.txt"; KERAS="$WORK/keras_proba.tsv"
NEED="$WORK/bert_needed.txt"; NEED_P="$WORK/bert_needed_proba.tsv"
REMOTE_IN="$WORK/unique_amp2.txt"
for f in "$UNIQ" "$KERAS" "$REMOTE_IN" "$NEED_P"; do [ -s "$f" ] || { echo "[错误] 缺 $f"; exit 1; }; done

N_U=$(wc -l < "$UNIQ"); N_R=$(wc -l < "$REMOTE_IN"); N_P=$(wc -l < "$NEED_P")
[ "$N_R" -eq "$N_P" ] || { echo "[错误] 远端输入 $N_R 行 != 概率 $N_P 行"; exit 1; }
echo "唯一序列 $N_U 条, 远端 BERT 结果 $N_R 条"

# 主机侧按 strict 规则重建 bert_needed.txt, 与远端输入逐行比对, 保证一致
paste "$UNIQ" "$KERAS" | awk -F'\t' '$2!="NA" && $2>0.5 && $3>0.5{print $1}' > "$NEED"
if ! cmp -s "$NEED" "$REMOTE_IN"; then
    echo "[错误] 远端输入与主机两票集合不一致 (可能远端 sort 顺序或阈值不同), 前几处差异:"
    diff "$NEED" "$REMOTE_IN" | head; exit 1
fi
echo strict > "$NEED.mode"; touch "$NEED.done"

# 对齐回全部唯一序列 (未跑 BERT 的记 NA), 与 run_unique_pipeline.sh 内部完全相同
paste "$NEED" "$NEED_P" > "$WORK/.need_p"
join -t $'\t' -a1 -e NA -o 2.2 "$UNIQ" "$WORK/.need_p" > "$WORK/bert_proba.tsv"
rm -f "$WORK/.need_p"
[ "$(wc -l < "$WORK/bert_proba.tsv")" -eq "$N_U" ] || { echo "[错误] 对齐后行数不对"; exit 1; }
touch "$WORK/bert_proba.tsv.done"
rm -f "$WORK/merged_proba.tsv.done" "$RES_ROOT"/results/*/*/aggregated_results.tsv.done 2>/dev/null
echo "bert_proba.tsv 已生成 ($N_U 行, 其中真实 BERT $N_R 条). 现在重新合并/回填/汇总 ..."

# 重新跑流程: 步骤 1~3 都有 .done 会直接跳过, 只做合并/回填/汇总
GROUPED_DIR="${GROUPED_DIR:-${2:-}}"
if [ -z "$GROUPED_DIR" ]; then
    echo "现在运行 (grouped_dir 为当初跑 run_unique_pipeline.sh 用的分组目录):"
    echo "  BERT_CASCADE=strict bash amp_pipeline/run_unique_pipeline.sh <grouped_dir> $RES_ROOT"
else
    BERT_CASCADE=strict bash "$SCRIPT_DIR/run_unique_pipeline.sh" "$GROUPED_DIR" "$RES_ROOT"
fi
