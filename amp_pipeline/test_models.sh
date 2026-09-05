#!/bin/bash
# ==============================================================================
# test_models.sh —— 在 WSL 本地用一小段真实 AMP 序列快速验证三个模型能否跑通
#
# 目的: 在等待服务器生成完整 sorf_grouped_catalog 的间隙, 先确认
#       Attention / LSTM / BERT 三条模型在你的 camps-tf114 + py36 环境里能正常出结果。
#
# 用法:
#   bash test_models.sh                        # 用仓库自带 Data/AMPs.fa 前 20 条
#   N=50 bash test_models.sh                   # 用前 50 条
#   bash test_models.sh /path/to/any.fa        # 指定任意小 FASTA
#
# 环境(与 run_pipeline_one.sh 一致):
#   camps-tf114 : Attention & LSTM   py36 : BERT
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_TF="${ENV_TF:-/home/w26/miniconda3/envs/camps-tf114}"
ENV_BERT="${ENV_BERT:-/home/w26/miniconda3/envs/py36}"
N="${N:-20}"

INPUT_FA="$1"
if [ -z "$INPUT_FA" ]; then
    INPUT_FA="$PROJECT_DIR/Data/AMPs.fa"
fi

OUT_DIR="${TEST_OUT:-$PROJECT_DIR/test_run}"

echo "=================================================="
echo " 三模型快速自检 (前 $N 条序列)"
echo "=================================================="
echo " 项目目录 : $PROJECT_DIR"
echo " 输入 FA   : $INPUT_FA"
echo " 输出目录 : $OUT_DIR"
echo " 序列数   : $N"
echo "=================================================="

TMP_FA="$OUT_DIR/test_input.fa"
mkdir -p "$OUT_DIR"
python3 "$SCRIPT_DIR/subset_fasta.py" "$INPUT_FA" "$N" > "$TMP_FA"
echo " 已生成: $TMP_FA  (记录数 $(grep -c '^>' "$TMP_FA"))"

bash "$SCRIPT_DIR/run_pipeline_one.sh" \
    "$TMP_FA" "$OUT_DIR/run_output" "$PROJECT_DIR" "$ENV_TF" "$ENV_BERT"

echo ""
echo "=================================================="
echo " 汇总测试结果"
echo "=================================================="
python3 "$SCRIPT_DIR/aggregate_amp_results.py" "$OUT_DIR/run_output" 2>&1 || true

echo ""
echo " 自检完成。若上方看到 attention/lstm/bert 三行 '完成' 且无 Traceback, 说明三模型可跑通。"
echo " 明细: $(dirname "$OUT_DIR")/run_output/(aggregated_results.tsv)"
