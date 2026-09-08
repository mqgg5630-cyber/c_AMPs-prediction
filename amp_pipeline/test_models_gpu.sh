#!/bin/bash
# ==============================================================================
# test_models_gpu.sh —— 用一小段真实 AMP 序列验证三模型(Attention/LSTM/BERT)能跑通,
#                        并在每个模型启动前打印该步使用的后端(GPU / CPU)。
#
# 用法:
#   bash amp_pipeline/test_models_gpu.sh                 # Data/AMPs.fa 前 20 条
#   N=50 bash amp_pipeline/test_models_gpu.sh            # 前 50 条
#   bash amp_pipeline/test_models_gpu.sh /path/x.fa      # 指定小 FASTA
#
# 可选环境变量(默认自动在 conda base/envs 中按名字查找):
#   ENV_TF_NAME=camps-tf114 ENV_BERT_NAME=py36
#   ENV_TF=<绝对路径>  ENV_BERT=<绝对路径>               # 直接用路径, 跳过探测
#   TEST_OUT=自定义输出目录
#
# 返回码: 0=全部可跑模型通过; 2=缺少 bert.bin(仍会跑通 Attention/LSTM 并提示)。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
N="${N:-20}"
INPUT_FA="${1:-$PROJECT_DIR/Data/AMPs.fa}"
OUT_DIR="${TEST_OUT:-$PROJECT_DIR/test_run}"

ENV_TF_NAME="${ENV_TF_NAME:-camps-tf114}"
ENV_BERT_NAME="${ENV_BERT_NAME:-py36}"

# ---------- 解析 conda base ----------
find_conda_root() {
    local c
    c="$(command -v conda 2>/dev/null)" && { echo "$(dirname "$(dirname "$c")")"; return; }
    c="$(command -v mamba 2>/dev/null)" && { echo "$(dirname "$(dirname "$c")")"; return; }
    for cand in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3"; do
        [ -x "$cand/bin/conda" ] && { echo "$cand"; return; }
    done
    echo ""
}
CONDA_ROOT="$(find_conda_root)"

# ---------- 把 "环境名" 解析成绝对路径 ----------
resolve_env() {
    local want="${1:-}" name="${2:-}" root="${3:-}"
    if [ -z "$want" ]; then want="$name"; fi
    if [ -x "$want/bin/python" ]; then echo "$want"; return; fi          # 已是路径
    if [ -n "$root" ] && [ -x "$root/envs/$want/bin/python" ]; then echo "$root/envs/$want"; return; fi
    for cand in "$HOME/miniconda3/envs/$want" "$HOME/miniforge3/envs/$want" \
                "$HOME/anaconda3/envs/$want"; do
        [ -x "$cand/bin/python" ] && { echo "$cand"; return; }
    done
    echo ""                                                              # 未找到
}

ENV_TF="${ENV_TF:-$(resolve_env "" "$ENV_TF_NAME" "$CONDA_ROOT")}"
ENV_BERT="${ENV_BERT:-$(resolve_env "" "$ENV_BERT_NAME" "$CONDA_ROOT")}"

echo "=================================================="
echo " 三模型 GPU 自检 (前 $N 条序列)"
echo "=================================================="
echo " 项目目录 : $PROJECT_DIR"
echo " 输入 FA   : $INPUT_FA"
echo " 输出目录 : $OUT_DIR"
echo " conda    : ${CONDA_ROOT:-未找到}"
echo " TF 环境  : ${ENV_TF:-未找到} ($ENV_TF_NAME)"
echo " BERT环境 : ${ENV_BERT:-未找到} ($ENV_BERT_NAME)"
echo "=================================================="
echo " 本机 GPU (nvidia-smi):"
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=index,name,memory.total,utilization.gpu --format=csv; else echo "   (nvidia-smi 不可用 -> 无可用 GPU, 只能 CPU 预测)"; fi

RC=0
# bert.bin 不入库; 若缺, 仍跑 Attention+LSTM 并在最后提示
if [ ! -f "$PROJECT_DIR/Models/bert.bin" ]; then
    echo ""
    echo "  [注意] Models/bert.bin 不存在 -> 本次跳过 BERT, 仅测 Attention+LSTM。"
    echo "         下载 bert.bin 后重跑本脚本即可补测 BERT (见 Models/ReadME.txt)。"
    RC=2
fi

# ---------- 准备输入子集 ----------
mkdir -p "$OUT_DIR"
TMP_FA="$OUT_DIR/test_input.fa"
python3 "$SCRIPT_DIR/subset_fasta.py" "$INPUT_FA" "$N" > "$TMP_FA"
echo ""
echo " 已生成子集: $TMP_FA  (记录数 $(grep -c '^>' "$TMP_FA"))"

# ---------- 后端探测: TF ----------
echo ""
echo "======== TF 后端(Attention/LSTM) ========"
if [ -n "$ENV_TF" ] && [ -x "$ENV_TF/bin/python" ]; then
    "$ENV_TF/bin/python" - <<'PY'
import tensorflow as tf, keras
try:
    gpus = tf.test.is_gpu_available(cuda_only=True)
    dev = "GPU" if gpus else "CPU(未检测到可用 GPU)"
    print(f"  TF {tf.__version__} | Keras {keras.__version__} | 后端: {dev}")
    if not gpus:
        print("  (TF1.14 GPU 需老 CUDA10/cuDNN7 运行库; 新版驱动下常不可用 -> 以 CPU 运行, 结果一致)")
except Exception as e:
    print("  TF 导入失败:", e); raise SystemExit(3)
PY
else
    echo "  !! 未找到 TF 环境 ($ENV_TF_NAME)。请先运行: bash amp_pipeline/setup_envs_mamba.sh tf"
    RC=4
fi

# ---------- 后端探测: BERT/PyTorch ----------
echo ""
echo "======== BERT/PyTorch 后端 ========"
if [ -n "$ENV_BERT" ] && [ -x "$ENV_BERT/bin/python" ]; then
    "$ENV_BERT/bin/python" - <<'PY'
import torch
print(f"  torch {torch.__version__} | CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  device: {torch.cuda.get_device_name(0)}")
else:
    print("  -> 以 CPU 运行 BERT (需 CUDA 版 torch 才会用 GPU)")
PY
else
    echo "  !! 未找到 BERT 环境 ($ENV_BERT_NAME)。请先运行: bash amp_pipeline/setup_envs_mamba.sh bert"
    RC=4
fi

# ---------- 若 TF 或 BERT 环境缺失, 直接终止 ----------
if [ "$RC" -ge 4 ]; then
    echo ""; echo "  环境缺失, 中止测试。请先运行 setup_envs_mamba.sh。"; exit "$RC"
fi

# ---------- 跑 pipeline (单分组) ----------
# 需要 MODEL_DIR 内已有 att.h5/lstm.h5; bert.bin 缺失时 run_pipeline_one 的预检会报错,
# 所以我们用分阶段方式手动触发三大模型, 保证能单独看到每步后端与结果。
echo ""
echo "=================================================="
echo " 阶段 A/Attention ($ENV_TF_NAME)"
echo "=================================================="
perl "$PROJECT_DIR/script/format.pl" "$TMP_FA" none > "$OUT_DIR/input_formatted_300.txt"
FORMAT_ROWS=$(wc -l < "$OUT_DIR/input_formatted_300.txt")
echo "  特征矩阵行数: $FORMAT_ROWS"
( cd "$PROJECT_DIR/script" && \
  TF_CPP_MIN_LOG_LEVEL=2 "$ENV_TF/bin/python" prediction_attention.py \
      "$OUT_DIR/input_formatted_300.txt" "$OUT_DIR/attention_proba.tsv" )
echo "  Attention 输出行数: $(wc -l < "$OUT_DIR/attention_proba.tsv")"

echo ""
echo "=================================================="
echo " 阶段 B/LSTM ($ENV_TF_NAME)"
echo "=================================================="
( cd "$PROJECT_DIR/script" && \
  TF_CPP_MIN_LOG_LEVEL=2 "$ENV_TF/bin/python" prediction_lstm.py \
      "$OUT_DIR/input_formatted_300.txt" "$OUT_DIR/lstm_proba.tsv" )
echo "  LSTM 输出行数: $(wc -l < "$OUT_DIR/lstm_proba.tsv")"

BERT_RC=0
if [ -f "$PROJECT_DIR/Models/bert.bin" ]; then
    echo ""
    echo "=================================================="
    echo " 阶段 C/BERT ($ENV_BERT_NAME)"
    echo "=================================================="
    ( cd "$PROJECT_DIR/script" && \
      BERT_USE_CUDA=auto "$ENV_BERT/bin/python" prediction_bert.py \
          "$TMP_FA" "$OUT_DIR/bert_proba.tsv" ) || BERT_RC=1
    echo "  BERT 输出行数: $(wc -l < "$OUT_DIR/bert_proba.tsv" 2>/dev/null || echo 0)"
else
    echo "  [跳过] 缺 Models/bert.bin。"
fi

echo ""
echo "=================================================="
echo " 汇总"
echo "=================================================="
echo "  attention_proba.tsv : $(wc -l < "$OUT_DIR/attention_proba.tsv") 行"
echo "  lstm_proba.tsv      : $(wc -l < "$OUT_DIR/lstm_proba.tsv") 行"
if [ -f "$PROJECT_DIR/Models/bert.bin" ]; then
    echo "  bert_proba.tsv      : $(wc -l < "$OUT_DIR/bert_proba.tsv") 行"
fi
echo "  输出目录: $OUT_DIR"

if [ "$BERT_RC" -ne 0 ]; then
    echo ""; echo "  [失败] BERT 阶段出错, 请检查 py36 环境与 bert.bin。"
    exit 1
fi
if [ "$RC" -eq 2 ]; then
    echo ""; echo "  Attention + LSTM 已跑通。下载 bert.bin 后重跑即可补测 BERT(完成三模型)。"
    echo "  下载: https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0"
    exit 2
fi
echo ""
echo "  三模型全部跑通 ✓"
exit 0
