#!/bin/bash
# ==============================================================================
# run_pipeline_one.sh —— 对【单个分组 FASTA】跑 c_AMPs 三模型预测并生成最终结果
#
# 环境分配 (与官方一致):
#   - camps-tf114 : Attention 模型 (att.h5) & LSTM 模型 (lstm.h5)  [TF1.14/Keras2.2.4]
#   - py36        : BERT 模型 (bert.bin)                            [PyTorch1.10/bert-sklearn]
#
# 用法:
#   bash run_pipeline_one.sh <input.fa> <output_dir> [project_dir] [env_tf] [env_bert]
# 示例:
#   bash run_pipeline_one.sh sorf_grouped_catalog/Cohort1_Matched265_5Stage/Cohort1_NC.fa \
#        out_Cohort1_NC
#
# 说明: 本脚本会自动推断项目根目录 (即 script/ 的上一级)。
#       若你的 Models/ 下没有 bert.bin, 请按 Models/ReadME.txt 下载并校验 md5。
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_FA="$1"
OUTPUT_DIR="$2"
PROJECT_DIR="${3:-$(dirname "$SCRIPT_DIR")}"                 # script/ 上一级
ENV_TF="${4:-/home/w26/miniconda3/envs/camps-tf114}"
ENV_BERT="${5:-/home/w26/miniconda3/envs/py36}"

# BERT 运行时环境: 默认 auto 探测 GPU (有 CUDA 自动开启), 支持大批次加速
export BERT_NUM_WORKERS="${BERT_NUM_WORKERS:-0}"
export BERT_USE_CUDA="${BERT_USE_CUDA:-auto}"
export BERT_EVAL_BATCH_SIZE="${BERT_EVAL_BATCH_SIZE:-128}"

if [ -z "$INPUT_FA" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "用法: bash run_pipeline_one.sh <input.fa> <output_dir> [project_dir] [env_tf] [env_bert]"
    echo "示例: bash run_pipeline_one.sh Group.fa out_group"
    exit 1
fi

# 预处理用的 perl 脚本路径
FORMAT_PL="$PROJECT_DIR/script/format.pl"
RESULT_PL="$PROJECT_DIR/script/result.pl"

echo "=================================================="
echo "[0/5] 环境预检 (fail-fast) ..."
echo "=================================================="
# 1) 项目根目录脚本
if [ ! -f "$FORMAT_PL" ]; then
    echo "  [错误] 找不到 format.pl: $FORMAT_PL"
    echo "         请确认 PROJECT_DIR 正确, 或传第 3 个参数指定项目根目录。"
    exit 1
fi
if [ ! -f "$RESULT_PL" ]; then
    echo "  [错误] 找不到 result.pl: $RESULT_PL"
    exit 1
fi
# 2) 三个模型文件
for m in att.h5 lstm.h5 bert.bin; do
    if [ ! -f "$PROJECT_DIR/Models/$m" ]; then
        echo "  [错误] 缺模型文件: Models/$m"
        echo "         请按 Models/ReadME.txt 放置 (bert.bin 需单独下载)。"
        exit 1
    fi
done
# 3) 两个 conda 环境
if [ ! -x "$ENV_TF/bin/python" ]; then
    echo "  [错误] 找不到 TF 环境 python: $ENV_TF/bin/python"
    echo "         请传第 4 个参数, 或 conda env list 确认环境名。"
    exit 1
fi
if [ ! -x "$ENV_BERT/bin/python" ]; then
    echo "  [错误] 找不到 BERT 环境 python: $ENV_BERT/bin/python"
    echo "         请传第 5 个参数, 或 conda env list 确认环境名。"
    exit 1
fi
# 4) 输入文件
if [ ! -f "$INPUT_FA" ]; then
    echo "  [错误] 找不到输入 FASTA: $INPUT_FA"
    exit 1
fi
echo "  预检通过 ✓ (模型齐全, 环境存在, 脚本在位)"

mkdir -p "$OUTPUT_DIR"
INPUT_ABS=$(readlink -f "$INPUT_FA")
OUTPUT_ABS=$(readlink -f "$OUTPUT_DIR")

# 保存原始输入 FASTA 副本, 便于后续 aggregate 对齐名称/长度/序列
cp "$INPUT_ABS" "$OUTPUT_ABS/input.fa"

# 空文件/无序列保护: 直接跳过, 免得 Attention/LSTM 因空输入崩溃
SEQ_COUNT=$(grep -c "^>" "$INPUT_ABS" || true)
if [ "$SEQ_COUNT" -eq 0 ]; then
    echo "  [跳过] 输入 FASTA 无任何序列记录: $INPUT_ABS"
    echo "         分组文件可能为空 (如服务器端 MAG 未匹配到该组, 或该组确实无 sORF)。"
    exit 0
fi
echo "  输入序列总数: $SEQ_COUNT"

echo "=================================================="
echo "  项目根目录 : $PROJECT_DIR"
echo "  输入 FASTA : $INPUT_ABS"
echo "  输出目录   : $OUTPUT_ABS"
echo "  TF 环境     : $ENV_TF"
echo "  BERT 环境   : $ENV_BERT"
echo "  format.pl   : $FORMAT_PL"
echo "  result.pl   : $RESULT_PL"
echo "  Models      : $(ls -1 "$PROJECT_DIR/Models/" 2>/dev/null | tr '\n' ' ')"

echo "=================================================="
echo "[1/5] 预处理输入序列 (format.pl) ..."
echo "=================================================="
perl "$FORMAT_PL" "$INPUT_ABS" none > "$OUTPUT_ABS/input_formatted_300.txt"
FORMAT_COUNT=$(wc -l < "$OUTPUT_ABS/input_formatted_300.txt")
echo "format 后行数: $FORMAT_COUNT"

echo "=================================================="
echo "[2/5] Attention 模型预测 (camps-tf114) ..."
echo "=================================================="
cd "$PROJECT_DIR/script"
"$ENV_TF/bin/python" prediction_attention.py \
    "$OUTPUT_ABS/input_formatted_300.txt" "$OUTPUT_ABS/attention_proba.tsv"
echo "Attention 完成 -> $OUTPUT_ABS/attention_proba.tsv ($(wc -l < "$OUTPUT_ABS/attention_proba.tsv") 条)"

echo "=================================================="
echo "[3/5] LSTM 模型预测 (camps-tf114) ..."
echo "=================================================="
"$ENV_TF/bin/python" prediction_lstm.py \
    "$OUTPUT_ABS/input_formatted_300.txt" "$OUTPUT_ABS/lstm_proba.tsv"
echo "LSTM 完成 -> $OUTPUT_ABS/lstm_proba.tsv ($(wc -l < "$OUTPUT_ABS/lstm_proba.tsv") 条)"

echo "=================================================="
echo "[4/5] BERT 模型预测 (py36) ..."
echo "=================================================="
"$ENV_BERT/bin/python" prediction_bert.py \
    "$INPUT_ABS" "$OUTPUT_ABS/bert_proba.tsv"
echo "BERT 完成 -> $OUTPUT_ABS/bert_proba.tsv ($(wc -l < "$OUTPUT_ABS/bert_proba.tsv") 条)"

echo "=================================================="
echo "[5/5] 三模型投票生成最终预测 (result.pl) ..."
echo "=================================================="
cd "$PROJECT_DIR/script"
perl "$RESULT_PL" \
    "$OUTPUT_ABS/attention_proba.tsv" \
    "$OUTPUT_ABS/lstm_proba.tsv" \
    "$OUTPUT_ABS/bert_proba.tsv" \
    "$INPUT_ABS" > "$OUTPUT_ABS/final_prediction.txt"

echo "=================================================="
echo " 单个分组预测完成！"
echo " 结果: $OUTPUT_ABS/final_prediction.txt"
echo "=================================================="
