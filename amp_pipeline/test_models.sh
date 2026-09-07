#!/bin/bash
# ==============================================================================
# test_models.sh —— 在本地用一小段真实 AMP 序列跑「端到端」三模型流程
#
# 目的: 在等待服务器生成完整 sorf_grouped_catalog 的间隙, 先确认
#       Attention / LSTM / BERT 三条模型 + format.pl/result.pl/汇总 整条链路能出结果。
#
# 用法:
#   bash test_models.sh                        # 用仓库自带 Data/AMPs.fa 前 20 条
#   N=50 bash test_models.sh                   # 用前 50 条
#   bash test_models.sh /path/to/any.fa        # 指定任意小 FASTA
#
# 环境(与 run_pipeline_one.sh 一致, 全部自动探测, 不再硬编码 /home/w26):
#   camps-tf114 : Attention & LSTM     camps-bert(或老名 py36) : BERT
#   显式覆盖: ENV_TF=/path/to/env ENV_BERT=/path/to/env bash test_models.sh
#
# 想做更细的「逐个模型 PASS/FAIL」体检, 用:
#   bash amp_pipeline/smoke_test_3models.sh
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

resolve_envs                       # → ENV_TF / ENV_BERT (可被外部 export 覆盖)
N="${N:-20}"

INPUT_FA="${1:-$PROJECT_DIR/Data/AMPs.fa}"
OUT_DIR="${TEST_OUT:-$PROJECT_DIR/test_run}"
SKIP_BERT_ARG=""
[ ! -f "$PROJECT_DIR/Models/bert.bin" ] && SKIP_BERT_ARG="skip-bert"

echo "=================================================="
echo " 三模型端到端自检 (前 $N 条序列)"
echo "=================================================="
echo " 项目目录 : $PROJECT_DIR"
echo " 输入 FA   : $INPUT_FA"
echo " 输出目录 : $OUT_DIR"
echo " 序列数   : $N"
echo " TF  环境 : ${ENV_TF:-<未找到>}"
echo " BERT环境 : ${ENV_BERT:-<未找到>}"
if [ -n "$SKIP_BERT_ARG" ]; then
    echo " BERT     : 缺 Models/bert.bin → 用占位概率只验证流程 (结论不代表真实预测)"
fi
echo "=================================================="

TMP_FA="$OUT_DIR/test_input.fa"
mkdir -p "$OUT_DIR"
PY3="${PYTHON:-$(command -v python3 || echo "${ENV_BERT:+$ENV_BERT/bin/python}")}"
"$PY3" "$SCRIPT_DIR/subset_fasta.py" "$INPUT_FA" "$N" > "$TMP_FA"
echo " 已生成: $TMP_FA  (记录数 $(grep -c '^>' "$TMP_FA"))"

bash "$SCRIPT_DIR/run_pipeline_one.sh" \
    "$TMP_FA" "$OUT_DIR/run_output" "$PROJECT_DIR" "$ENV_TF" "$ENV_BERT" $SKIP_BERT_ARG

echo ""
echo "=================================================="
echo " 汇总测试结果"
echo "=================================================="
"$PY3" "$SCRIPT_DIR/aggregate_amp_results.py" "$OUT_DIR/run_output" 2>&1 || true

echo ""
echo " 自检完成。若上方看到 attention/lstm/bert 三行 '完成' 且无 Traceback, 说明三模型可跑通。"
echo " 明细: $OUT_DIR/run_output/aggregated_results.tsv"
echo " 想要逐模型 PASS/FAIL 报告: bash amp_pipeline/smoke_test_3models.sh"
