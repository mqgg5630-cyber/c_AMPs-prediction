#!/bin/bash
# ==============================================================================
# setup_envs_mamba.sh —— 用 mamba 在本机创建 c_AMPs-prediction 所需的两个 conda 环境
#
# 需要创建的环境(与 run_pipeline_one.sh 默认一致):
#   camps-tf114 : Attention(att.h5) & LSTM(lstm.h5)   -> TensorFlow 1.14 / Keras 2.2.4
#   py36        : BERT(bert.bin)                      -> PyTorch 1.10 / bert-sklearn 0.2.0
#
# 用法:
#   bash setup_envs_mamba.sh                 # 同时创建两个环境(默认, 会较久)
#   bash setup_envs_mamba.sh tf              # 只创建 camps-tf114 (Attention+LSTM)
#   bash setup_envs_mamba.sh bert            # 只创建 py36 (BERT)
#   TF_BACKEND=gpu bash setup_envs_mamba.sh  # camps-tf114 里装 tensorflow-gpu==1.14.0
#   TF_BACKEND=auto bash setup_envs_mamba.sh # 默认: 先试 GPU, 装不上回退 CPU
#
# 说明:
#   * TF 1.14 是很老的版本, 只支持 Python 3.6/3.7, 我们统一用 python=3.7。
#   * TF1.14 的 GPU wheel 需要老 CUDA10/cuDNN7 运行库; 在 2026 新驱动/WSL2 上
#     极大概率只能跑 CPU。装不上 GPU 版时脚本会自动回退 CPU 版(功能完全一致)。
#   * BERT 模型 bert.bin 需单独下载并放入 Models/, 见 Models/ReadME.txt(脚本末尾也有)。
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDA_ROOT=""
TF_BACKEND="${TF_BACKEND:-auto}"        # gpu | cpu | auto
ENV_TF_NAME="${ENV_TF_NAME:-camps-tf114}"
ENV_BERT_NAME="${ENV_BERT_NAME:-py36}"

echo "=================================================="
echo " c_AMPs-prediction 环境安装 (mamba)"
echo "=================================================="
echo " 项目目录 : $REPO_DIR"
echo " TF 环境   : $ENV_TF_NAME  (backend=$TF_BACKEND)"
echo " BERT 环境 : $ENV_BERT_NAME"
echo "=================================================="

# ---------- 定位 mamba / conda ----------
find_conda() {
    local cand
    if command -v mamba >/dev/null 2>&1; then echo "mamba"; return; fi
    if command -v conda  >/dev/null 2>&1; then echo "conda"; return; fi
    for cand in "$HOME/miniconda3/bin/mamba" "$HOME/miniconda3/bin/conda" \
                "$HOME/miniforge3/bin/mamba" "$HOME/anaconda3/bin/conda"; do
        if [ -x "$cand" ]; then echo "$cand"; return; fi
    done
    return 1
}
CONDA_BIN="$(find_conda || true)"
if [ -z "$CONDA_BIN" ]; then
    echo "!! 未找到 mamba/conda。请先安装 miniconda 或 mambaforge 后再运行本脚本。"
    exit 1
fi
# 若只给了命令名(mamba/conda), 解析出完整路径并定位 base
case "$CONDA_BIN" in
    mamba|conda)
        CONDA_BIN="$(command -v "$CONDA_BIN")"
        CONDA_ROOT="$(dirname "$(dirname "$CONDA_BIN")")"
        ;;
    *)
        CONDA_ROOT="$(dirname "$(dirname "$CONDA_BIN")")"   # .../bin/xxx -> 前缀
        ;;
esac
CONDA_BIN_PATH="$CONDA_ROOT/bin/conda"
MAMBA_OR_CONDA="$CONDA_BIN"
echo "  使用: $CONDA_BIN   (root: $CONDA_ROOT)"
echo ""

# 常用源码镜像, 加快下载(可自行去掉)
SOLVE_EXTRA=(--solver=libmamba)          # 若你的 conda 版本支持 libmamba 求解器可提速

env_exists() { "$CONDA_ROOT/bin/conda" env list | awk '{print $1}' | grep -qx "$1"; }

# ======================================================================
# 1) camps-tf114 —— Attention & LSTM
# ======================================================================
maybe_setup_tf() {
    if env_exists "$ENV_TF_NAME"; then
        echo ">> 环境 $ENV_TF_NAME 已存在, 跳过创建。"
        return
    fi
    echo ">> 正在用 mamba 创建 $ENV_TF_NAME (python=3.7)..."
    "$CONDA_BIN" create -y -n "$ENV_TF_NAME" python=3.7 pip

    local PY="$CONDA_ROOT/envs/$ENV_TF_NAME/bin/python"
    local PIP="$CONDA_ROOT/envs/$ENV_TF_NAME/bin/pip"
    echo ">> 安装基础依赖 (numpy/h5py/keras)..."
    "$PIP" install "numpy==1.16.2" "h5py==2.9.0" "Keras==2.2.4" "pillow"

    # 只装一种后端, 避免 CPU 版覆盖 GPU 版(二选一)
    if [ "$TF_BACKEND" = "gpu" ]; then
        echo ">> 安装 tensorflow-gpu==1.14.0 ..."
        "$PIP" install "tensorflow-gpu==1.14.0"
    elif [ "$TF_BACKEND" = "cpu" ]; then
        echo ">> 安装 tensorflow==1.14.0 (CPU)..."
        "$PIP" install "tensorflow==1.14.0"
    else  # auto: 先试 GPU, 失败即回退 CPU
        echo ">> 尝试安装 tensorflow-gpu==1.14.0 (可能需要老 CUDA10/cuDNN7 运行库)..."
        if ! "$PIP" install "tensorflow-gpu==1.14.0"; then
            echo "   !! tensorflow-gpu 安装失败, 自动回退 CPU 版 (功能等价)。"
            "$PIP" install "tensorflow==1.14.0"
        fi
    fi

    # TF1.14 很老, 与 protobuf>=4 不兼容 (Descriptors cannot be created directly);
    # 必须把 protobuf 钉在 3.20 以下才能 import tensorflow。
    echo ">> 钉 protobuf<3.20 (兼容 TF1.14 必要步骤)..."
    "$PIP" install "protobuf==3.19.6"

    echo ">> $ENV_TF_NAME 就绪。验证:"
    "$PY" -c "import tensorflow as tf, keras; print('TF', tf.__version__, '| Keras', keras.__version__, '| GPU devices:', tf.test.is_gpu_available())"
    echo ""
}

# ======================================================================
# 2) py36 —— BERT
# ======================================================================
maybe_setup_bert() {
    if env_exists "$ENV_BERT_NAME"; then
        echo ">> 环境 $ENV_BERT_NAME 已存在, 跳过创建。"
        return
    fi
    echo ">> 正在用 mamba 创建 $ENV_BERT_NAME (python=3.7)..."
    "$CONDA_BIN" create -y -n "$ENV_BERT_NAME" python=3.7 pip

    local PY="$CONDA_ROOT/envs/$ENV_BERT_NAME/bin/python"
    local PIP="$CONDA_ROOT/envs/$ENV_BERT_NAME/bin/pip"
    echo ">> 安装 PyTorch 1.10 (CPU 版; bert 推理够用, 也可换装对应 CUDA 版)..."
    "$PIP" install "torch==1.10.0+cpu" -f https://download.pytorch.org/whl/torch_stable.html \
        || "$PIP" install "torch==1.10.0"
    "$PIP" install "numpy" "pandas" "scikit-learn" "regex" "tqdm" "boto3" "requests"

    echo ">> 安装本仓库自带 bert_sklearn (v0.2.0)..."
    # 说明: 该 repo 的 bert_sklearn/setup.py 位于包目录内部, `pip install .` 装不齐,
    #       官方 README 的做法是把整个 bert_sklearn 目录放进 site-packages, 这里用软链实现。
    local SP
    SP="$("$PY" -c 'import site,sys; print(site.getsitepackages()[0])')"
    if [ ! -e "$SP/bert_sklearn" ]; then
        ln -s "$REPO_DIR/bert_sklearn" "$SP/bert_sklearn"
        echo "   已软链 bert_sklearn -> $SP/bert_sklearn"
    else
        echo "   $SP/bert_sklearn 已存在, 跳过。"
    fi

    echo ">> $ENV_BERT_NAME 就绪。验证:"
    "$PY" -c "import torch; from bert_sklearn import BertClassifier; print('torch', torch.__version__, '| bert_sklearn OK')"
    echo ""
}

# ======================================================================
# BERT 模型下载提示
# ======================================================================
print_bert_model_note() {
    echo ""
    echo "=================================================="
    echo " 还需要 BERT 预训练微调模型 bert.bin (不入库, 单独下载)"
    echo "=================================================="
    echo " 下载地址: https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0"
    echo " md5 校验 : 990d14de053d8080fcca33d712d647b6"
    echo " 放到     : $REPO_DIR/Models/bert.bin"
    echo " 然后(在 Linux/WSL):"
    echo "   md5sum Models/bert.bin     # 应输出 990d14de053d8080fcca33d712d647b6"
    echo "=================================================="
}

MODE="${1:-all}"
case "$MODE" in
    tf)    maybe_setup_tf ;;
    bert)  maybe_setup_bert ;;
    all)
        maybe_setup_tf
        maybe_setup_bert
        print_bert_model_note
        ;;
    *)
        echo "用法: bash setup_envs_mamba.sh [all|tf|bert]"; exit 1 ;;
esac

echo ""
echo "全部完成。下一步在本机跑三模型自检:"
echo "  bash amp_pipeline/test_models_gpu.sh"
