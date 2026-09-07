#!/usr/bin/env bash
# ==============================================================================
# env.sh —— 三模型环境路径的「单一事实来源」(可 source, 也可直接执行看输出)
#
# 用法:
#   source amp_pipeline/env.sh          # 把 ENV_TF / ENV_BERT 导进当前 shell
#   bash   amp_pipeline/env.sh          # 只打印, 顺便跑一遍预检
#
# install_envs.sh 跑完会在文件末尾追加一段 "# ---- BEGIN generated ----" 的
# 固化路径, 这样以后即使 conda root 变了也能用。
# ==============================================================================
_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "$_ENV_SH_DIR/lib.sh"

resolve_envs

# 运行期默认参数 (都能被外部 export 覆盖)
export TF_USE_GPU="${TF_USE_GPU:-auto}"          # auto | 1 | 0
export BERT_USE_CUDA="${BERT_USE_CUDA:-auto}"    # auto | 1 | 0
export BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-64}"
export BERT_MAX_SEQ_LENGTH="${BERT_MAX_SEQ_LENGTH:-64}"
export BERT_NUM_WORKERS="${BERT_NUM_WORKERS:-0}"
export TF_PREDICT_BATCH_SIZE="${TF_PREDICT_BATCH_SIZE:-1024}"
export TF_CHUNK_SIZE="${TF_CHUNK_SIZE:-20000}"
export BERT_CHUNK_SIZE="${BERT_CHUNK_SIZE:-10000}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"
export CUDA_DEVICE_ORDER="${CUDA_DEVICE_ORDER:-PCI_BUS_ID}"

# 多卡机器上想指定用哪张卡: export BERT_GPU=2  (会映射成 CUDA_VISIBLE_DEVICES=2)
if [ -n "${BERT_GPU:-}" ]; then
    export CUDA_VISIBLE_DEVICES="$BERT_GPU"
fi

if [ "${1:-}" = "--print" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "============== c_AMPs-prediction 环境 =============="
    env_status_line
    echo "  TF_USE_GPU=$TF_USE_GPU  BERT_USE_CUDA=$BERT_USE_CUDA  BERT_EVAL_BATCH_SIZE=$BERT_EVAL_BATCH_SIZE"
    g="$(gpu_name)" && [ -n "$g" ] && echo "  GPU: $g"
    pdir="$(cd "$_ENV_SH_DIR/.." && pwd)"
    for m in att.h5 lstm.h5 bert.bin bert-base-uncased/vocab.txt; do
        if [ -f "$pdir/Models/$m" ]; then
            echo "  [有] Models/$m  ($(du -h "$pdir/Models/$m" | cut -f1))"
        else
            echo "  [缺] Models/$m"
        fi
    done
    echo "===================================================="
fi
