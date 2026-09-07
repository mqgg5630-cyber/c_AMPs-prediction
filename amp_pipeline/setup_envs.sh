#!/bin/bash
# ==============================================================================
# setup_envs.sh —— 一键创建三模型所需的两个 conda 环境 (WSL2 + GTX 1650 适配)
#
#   camps-tf114 : Attention (att.h5) & LSTM (lstm.h5)
#                 Python 3.6 + tensorflow-gpu 1.14 + cudatoolkit 10.0 + cudnn 7.6
#                 + Keras 2.2.4 + h5py 2.10 + numpy 1.16
#   py36        : BERT (bert.bin)
#                 Python 3.6 + torch 1.10.1 (cu113) + pytorch_pretrained_bert 0.6.1
#                 + 本仓库的 bert_sklearn
#
# GTX 1650 = Turing (sm_75):
#   - TF1.14 官方 CUDA 10.0 已支持 sm_75, conda 会自动装 cudatoolkit 10.0 / cudnn 7.6
#   - torch 1.10.1+cu113 内置 sm_75 内核
#   WSL2 只需在 Windows 侧装好 NVIDIA 驱动 (>= 470), 不要在 WSL 内装驱动。
#
# 用法:
#   bash amp_pipeline/setup_envs.sh            # 全部安装
#   bash amp_pipeline/setup_envs.sh tf         # 只装 camps-tf114
#   bash amp_pipeline/setup_envs.sh bert       # 只装 py36
#   FORCE=1 bash amp_pipeline/setup_envs.sh    # 已存在的环境先删除再重建
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHAT="${1:-all}"

ENV_TF_NAME="${ENV_TF_NAME:-camps-tf114}"
ENV_BERT_NAME="${ENV_BERT_NAME:-py36}"

# ---------- 定位 conda ----------
if ! command -v conda >/dev/null 2>&1; then
    for c in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/mambaforge" "$HOME/miniforge3" /opt/conda; do
        if [ -x "$c/bin/conda" ]; then export PATH="$c/bin:$PATH"; break; fi
    done
fi
if ! command -v conda >/dev/null 2>&1; then
    echo "[错误] 找不到 conda, 请先安装 Miniconda: https://docs.conda.io/en/latest/miniconda.html"
    exit 1
fi
CONDA_BASE="$(conda info --base)"
# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

# 优先用 mamba 加速求解 (若存在)
SOLVER="conda"
if command -v mamba >/dev/null 2>&1; then SOLVER="mamba"; fi

echo "=================================================="
echo " conda base : $CONDA_BASE"
echo " solver     : $SOLVER"
echo " 项目目录   : $PROJECT_DIR"
echo " 安装范围   : $WHAT"
echo "=================================================="

# 判定"环境可用": 目录存在且 bin/python 可执行 (上次下载中断会留下无 python 的残缺目录)
env_exists() { [ -x "$CONDA_BASE/envs/$1/bin/python" ]; }

# ---------- 大包预下载 (断点续传 + 多镜像重试) ----------
# 国内镜像对 >100MB 的包经常中途断线 (SSL unexpected eof), mamba 不会续传, 直接失败。
# 这里先用 wget -c 把大包拉到 pkgs 缓存, mamba 创建环境时会直接复用, 不再重复下载。
PKGS_DIR="$CONDA_BASE/pkgs"
MIRRORS=(
    "https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/linux-64"
    "https://mirrors.ustc.edu.cn/anaconda/pkgs/main/linux-64"
    "https://mirrors.bfsu.edu.cn/anaconda/pkgs/main/linux-64"
    "https://repo.anaconda.com/pkgs/main/linux-64"
)
prefetch_pkg() {   # prefetch_pkg <filename>
    local fn="$1" dst="$PKGS_DIR/$1"
    mkdir -p "$PKGS_DIR"
    if [ -f "$dst" ] && [ ! -f "$dst.part" ]; then
        echo "  [已缓存] $fn"; return 0
    fi
    for m in "${MIRRORS[@]}"; do
        echo "  [下载] $fn  <- $m"
        # -c 续传, 断线自动重试 20 次, 每次间隔 3s; 用 .part 标记未完成
        if wget -c -q --show-progress --tries=20 --waitretry=3 --read-timeout=60 \
                -O "$dst" "$m/$fn" 2>&1 && [ -s "$dst" ]; then
            rm -f "$dst.part"; echo "  [完成] $fn"; return 0
        fi
        touch "$dst.part"
        echo "  [失败] 换下一个镜像 ..."
    done
    echo "  [错误] $fn 所有镜像都下载失败, 请检查网络后重跑本脚本 (会自动续传)"
    return 1
}

# mamba/conda create 加重试 (小包偶发断线)
retry() {  # retry <n> <cmd...>
    local n="$1"; shift
    local i
    for ((i=1; i<=n; i++)); do
        "$@" && return 0
        echo "  [重试 $i/$n] 命令失败, 10s 后重试: $*"; sleep 10
    done
    return 1
}

maybe_remove() {
    local d="$CONDA_BASE/envs/$1"
    if env_exists "$1"; then
        if [ "${FORCE:-0}" = "1" ]; then
            echo " [FORCE] 删除已存在环境 $1 ..."
            conda env remove -n "$1" -y || rm -rf "$d"
        else
            echo " [跳过创建] 环境 $1 已存在且完整 (加 FORCE=1 可重建), 继续检查依赖 ..."
            return 1
        fi
    elif [ -d "$d" ]; then
        echo " [清理] 发现残缺环境目录 (无 bin/python, 上次安装中断所致): $d -> 删除后重建"
        rm -rf "$d"
    fi
    return 0
}

# ============================================================
# 1) camps-tf114 : TF 1.14 GPU + Keras 2.2.4
# ============================================================
install_tf() {
    echo ""
    echo "############## [1/2] 创建 $ENV_TF_NAME (TF1.14-GPU) ##############"
    if maybe_remove "$ENV_TF_NAME"; then
        echo " ---- 预下载大包 (cudatoolkit / cudnn / tensorflow-base, 共约 600MB) ----"
        prefetch_pkg "cudatoolkit-10.0.130-0.conda"
        prefetch_pkg "cudnn-7.6.5-cuda10.0_0.conda"
        prefetch_pkg "tensorflow-base-1.14.0-gpu_py36h8d69cac_0.conda"
        # defaults 频道自带 tensorflow-gpu 1.14 + cudatoolkit 10.0 + cudnn 7.6 (py36)
        retry 3 $SOLVER create -n "$ENV_TF_NAME" -y python=3.6 \
            tensorflow-gpu=1.14.0 cudatoolkit=10.0.130 "cudnn=7.6.5" \
            numpy=1.16 "h5py<3" -c defaults
    fi
    PY_TF="$CONDA_BASE/envs/$ENV_TF_NAME/bin/python"
    [ -x "$PY_TF" ] || { echo "[错误] 环境创建失败, 未找到 $PY_TF"; exit 1; }
    # keras 2.2.4 走 pip (conda 版本会拉高依赖); 固定 h5py<3 否则 load_model 报 'str' has no attribute 'decode'
    retry 3 "$PY_TF" -m pip install --timeout 120 --retries 10 "keras==2.2.4" "h5py==2.10.0" "numpy<1.17" "protobuf<3.21" "scipy<1.6"
    echo " ---- $ENV_TF_NAME 版本核对 ----"
    "$PY_TF" - <<'PY'
import tensorflow as tf, keras, h5py, numpy
print("tensorflow", tf.__version__, "| keras", keras.__version__, "| h5py", h5py.__version__, "| numpy", numpy.__version__)
print("TF built with CUDA:", tf.test.is_built_with_cuda())
PY
}

# ============================================================
# 2) py36 : torch 1.10.1 cu113 + bert_sklearn
# ============================================================
install_bert() {
    echo ""
    echo "############## [2/2] 创建 $ENV_BERT_NAME (BERT / PyTorch) ##############"
    if maybe_remove "$ENV_BERT_NAME"; then
        retry 3 $SOLVER create -n "$ENV_BERT_NAME" -y python=3.6 pip
    fi
    PY_BERT="$CONDA_BASE/envs/$ENV_BERT_NAME/bin/python"
    [ -x "$PY_BERT" ] || { echo "[错误] 环境创建失败, 未找到 $PY_BERT"; exit 1; }
    # torch 1.10.1 是最后一个支持 py3.6 的版本, cu113 内置 sm_75 (GTX 1650)
    # torch+cu113 约 1.8GB, 加超时/重试; 断线可直接重跑本脚本 (bert)
    retry 3 "$PY_BERT" -m pip install --timeout 120 --retries 10 torch==1.10.1+cu113 \
        --extra-index-url https://download.pytorch.org/whl/cu113
    retry 3 "$PY_BERT" -m pip install --timeout 120 --retries 10 "numpy<1.20" "pandas<1.2" "scikit-learn<1.0" \
        boto3 requests regex tqdm "pytorch_pretrained_bert==0.6.1"
    # 安装仓库自带的 bert_sklearn (可编辑模式, 改代码即时生效)
    "$PY_BERT" -m pip install -e "$PROJECT_DIR/bert_sklearn"
    echo " ---- $ENV_BERT_NAME 版本核对 ----"
    "$PY_BERT" - <<'PY'
import torch, sklearn, numpy, bert_sklearn, pytorch_pretrained_bert
print("torch", torch.__version__, "| cuda build", torch.version.cuda,
      "| sklearn", sklearn.__version__, "| numpy", numpy.__version__,
      "| bert_sklearn", bert_sklearn.__version__)
PY
}

case "$WHAT" in
    all)  install_tf; install_bert ;;
    tf)   install_tf ;;
    bert) install_bert ;;
    *) echo "用法: bash setup_envs.sh [all|tf|bert]"; exit 1 ;;
esac

echo ""
echo "=================================================="
echo " 安装完成。环境路径:"
echo "   ENV_TF   = $CONDA_BASE/envs/$ENV_TF_NAME"
echo "   ENV_BERT = $CONDA_BASE/envs/$ENV_BERT_NAME"
echo ""
echo " 下一步:"
echo "   1) 测 GPU     : bash $SCRIPT_DIR/test_gpu.sh"
echo "   2) 测三个模型 : bash $SCRIPT_DIR/test_models.sh"
echo "      (bert.bin 需按 Models/ReadME.txt 单独下载到 Models/ 并核对 md5)"
echo "=================================================="
