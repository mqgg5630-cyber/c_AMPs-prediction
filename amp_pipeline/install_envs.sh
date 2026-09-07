#!/usr/bin/env bash
# ==============================================================================
# install_envs.sh —— 一键安装 c_AMPs-prediction 的三模型运行环境 (mamba 加速)
#
# 会建两个 conda 环境 (官方 requirement.txt 就是要求两套, 无法合并):
#   camps-tf114  python 3.6 + tensorflow 1.14 + Keras 2.2.4  → Attention(att.h5) + LSTM(lstm.h5)
#   camps-bert   python 3.9 + torch 2.4.1  + bert_sklearn 0.2 → BERT(bert.bin)
#
# 用法:
#   bash amp_pipeline/install_envs.sh                     # 推荐: TF 走 CPU, BERT 走 GPU
#   bash amp_pipeline/install_envs.sh --tf-gpu            # 想赌 TF1.14 在 A4000 上跑 GPU
#   bash amp_pipeline/install_envs.sh --bert-cpu          # BERT 也不要 GPU (省 ~5GB 下载)
#   bash amp_pipeline/install_envs.sh --only bert         # 只装其中一个
#   bash amp_pipeline/install_envs.sh --bert-bin /mnt/c/Users/xxx/Downloads/bert.bin
#   MAMBA_MODE=off bash amp_pipeline/install_envs.sh      # 不用 mamba, 走 conda classic
#
# 可选环境变量:
#   ENV_TF / ENV_BERT   直接指定环境 prefix (优先级最高)
#   ENV_TF_NAME=camps-tf114  ENV_BERT_NAME=camps-bert   环境名
#   TF_PY=3.6           TF 环境的 python 版本 (只能 3.6 或 3.7)
#   BERT_PY=3.9         BERT 环境的 python 版本 (3.8~3.11)
#   TORCH_CUDA=12.1     BERT 环境 torch 的 CUDA 版本 (仅 GPU 模式有意义)
#   PIP_INDEX_URL=...   pip 换源 (如清华 TUNA)
#   CONDA_ROOT=...      手动指定 conda root
#
# 幂等: 已装好的环境会自动跳过 (FORCE=1 可强制重建)。
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="${ENV_DIR:-$CONDA_ROOT/envs}"
ENV_TF_NAME="${ENV_TF_NAME:-camps-tf114}"
ENV_BERT_NAME="${ENV_BERT_NAME:-camps-bert}"
TF_PY="${TF_PY:-3.6}"
BERT_PY="${BERT_PY:-3.9}"
TORCH_CUDA="${TORCH_CUDA:-12.1}"
FORCE="${FORCE:-0}"

DO_TF=1; DO_BERT=1
TF_FLAVOR="${TF_FLAVOR:-cpu}"          # cpu | gpu
BERT_FLAVOR="${BERT_FLAVOR:-auto}"     # auto | gpu | cpu
BERT_BIN_SRC=""

usage() { awk 'NR>1 && /^set -/{exit} NR>1{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --tf-gpu)      TF_FLAVOR=gpu ;;
        --tf-cpu)      TF_FLAVOR=cpu ;;
        --bert-gpu)    BERT_FLAVOR=gpu ;;
        --bert-cpu)    BERT_FLAVOR=cpu ;;
        --only)        shift
                       case "${1:-}" in
                           tf|tf114|tensorflow) DO_TF=1; DO_BERT=0 ;;
                           bert|py36)           DO_BERT=1; DO_TF=0 ;;
                           *) die "--only 只接受 tf 或 bert" ;;
                       esac ;;
        --bert-bin)    shift; BERT_BIN_SRC="${1:-}" ;;
        --env-dir)     shift; ENV_DIR="${1:-}" ;;
        --force)       FORCE=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) die "未知参数: $1 (用 --help 看用法)" ;;
    esac
    shift
done

# BERT auto: 有 nvidia-smi 就 GPU
if [ "$BERT_FLAVOR" = "auto" ]; then
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        BERT_FLAVOR=gpu
    else
        BERT_FLAVOR=cpu
    fi
fi

ENV_TF="${ENV_TF:-$ENV_DIR/$ENV_TF_NAME}"
ENV_BERT="${ENV_BERT:-$ENV_DIR/$ENV_BERT_NAME}"

echo "=============================================================="
echo " c_AMPs-prediction 三模型环境安装器"
echo "=============================================================="
echo "  项目目录     : $PROJECT_DIR"
echo "  conda root   : $CONDA_ROOT"
echo "  环境目录     : $ENV_DIR"
echo "  TF  环境     : $ENV_TF   (python $TF_PY, tensorflow 1.14 ${TF_FLAVOR})"
echo "  BERT环境     : $ENV_BERT (python $BERT_PY, torch 2.4.1 ${BERT_FLAVOR})"
echo "  要装的模块   : $([ $DO_TF = 1 ] && echo -n 'Attention+LSTM ')$([ $DO_BERT = 1 ] && echo -n 'BERT')"
echo "  求解器偏好   : MAMBA_MODE=${MAMBA_MODE:-auto}"
echo "=============================================================="

# ---- 前置: 网络 / 磁盘 ----
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || \
    die "需要 curl 或 wget 来下载包"
avail_kb=$(df -Pk "$HOME" | awk 'NR==2{print $4}')
if [ "${avail_kb:-0}" -lt 12582912 ]; then   # < 12GB
    log_warn "可用磁盘只有 $(( avail_kb / 1024 / 1024 ))GB, 两个环境 + torch(cu121) 大概需要 12~15GB。"
fi

_mamba_probe && log_ok "求解器: $SOLVER_LABEL" || log_warn "没找到 mamba/conda, 后面会报错退出"

t_start
NEED_VOCAB=0

# =============================================================================
#  1) camps-tf114 : tensorflow 1.14 + Keras 2.2.4  (Attention / LSTM)
# =============================================================================
install_tf_env() {
    log_step "[1/2] 创建 TF 环境 $ENV_TF_NAME (Attention + LSTM)"

    if [ -x "$ENV_TF/bin/python" ] && [ "$FORCE" != "1" ]; then
        if "$ENV_TF/bin/python" -c 'import tensorflow as tf, keras; print(tf.__version__, keras.__version__)' >/dev/null 2>&1; then
            log_ok "已存在且可导入 tensorflow+keras, 跳过 (FORCE=1 可强制重建)"
            "$ENV_TF/bin/python" -c 'import tensorflow as tf, keras, numpy, sys; print("     python %s | tf %s | keras %s | numpy %s" % (sys.version.split()[0], tf.__version__, keras.__version__, numpy.__version__))'
            return 0
        fi
        log_warn "环境存在但导入失败, 继续补装依赖"
    elif [ "$FORCE" = "1" ] && [ -d "$ENV_TF" ]; then
        log_warn "FORCE=1 → 删除旧环境 $ENV_TF"
        rm -rf "$ENV_TF"
    fi

    # python 3.6 在 conda-forge 的当前 repodata 里可能已经找不到 (太老了),
    # 所以按 "conda-forge 3.6 → anaconda free 3.6 → conda-forge 3.7" 依次回退。
    # tensorflow 1.14 只有 cp36 / cp37 的 wheel, 3.7 也完全可用。
    local created=0 spec
    for spec in \
        "conda-forge|python=$TF_PY" \
        "https://repo.anaconda.com/pkgs/free|python=$TF_PY" \
        "conda-forge|python=3.7" ; do
        local chan="${spec%%|*}" want="${spec##*|}"
        log_info "尝试: -c $chan  $want"
        if mamba_create "$ENV_TF" "$chan" -- "$want" "pip"; then
            created=1
            local got; got="$("$ENV_TF/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
            log_ok "python $got 环境创建成功 (channel: $chan)"
            break
        fi
        log_warn "  → 失败, 换下一个方案 (可能是 channel 里已经没有这么老的 python)"
        rm -rf "$ENV_TF" 2>/dev/null || true
    done
    [ "$created" = 1 ] || die "三种方案都没建出 python3.6/3.7 环境。检查网络, 或手动:
    mamba create -p $ENV_TF -c https://repo.anaconda.com/pkgs/free python=3.6 pip"

    bootstrap_pip_py36 "$ENV_TF" || die "pip bootstrap 失败 (py3.6 网络问题?)"

    # requirements_tf114.txt 里钉的是 CPU 版 tensorflow==1.14.0。
    # 选 --tf-gpu 时先把这一行摘掉, 改装 tensorflow-gpu==1.14.0 (两者依赖声明完全一致)。
    local tmpreq tfpkg
    tmpreq="$(mktemp)"
    grep -viE '^\s*tensorflow(-gpu)?\s*==' "$SCRIPT_DIR/requirements_tf114.txt" > "$tmpreq"
    tfpkg="tensorflow==1.14.0"
    [ "$TF_FLAVOR" = "gpu" ] && tfpkg="tensorflow-gpu==1.14.0"

    log_info "pip 安装 TF 依赖 (这一步最久, ~5-10 分钟)..."
    # shellcheck disable=SC2046
    env_pip "$ENV_TF" install --no-input --disable-pip-version-check --no-warn-script-location \
        $(pip_index_args) -r "$tmpreq" "$tfpkg" || {
            rm -f "$tmpreq"
            die "pip 安装 TF 依赖失败 (完整日志见上)。常见原因: 网络中断 / pip 源被墙 / 磁盘满。"
        }
    rm -f "$tmpreq"

    if [ "$TF_FLAVOR" = "gpu" ]; then
        log_info "GPU 模式: 补装 cudatoolkit=10.0 + cudnn=7.6 (TF1.14 官方要求)"
        mamba_install "$ENV_TF" -c conda-forge --override-channels \
            "cudatoolkit=10.0" "cudnn=7.6" || \
            log_warn "cudatoolkit/cudnn 安装失败 —— TF 会自动退回 CPU, 不影响出结果。"
        log_warn "提醒: RTX A4000 是 Ampere(sm_86), CUDA 10.0 的 kernel 没编到 sm_86,"
        log_warn "      很可能报 'no kernel image is available'。真遇到就 export TF_USE_GPU=0。"
    fi

    log_info "自检 TF 环境..."
    "$ENV_TF/bin/python" - <<'PY' || die "TF 环境自检失败"
import sys, numpy, keras, tensorflow as tf
print("     python %s | numpy %s | keras %s | tf %s" % (
    sys.version.split()[0], numpy.__version__, keras.__version__, tf.__version__))
print("     keras backend =", keras.backend.backend())
try:
    from tensorflow.python.client import device_lib
    print("     TF 可见设备 =", [d.name for d in device_lib.list_local_devices()])
except Exception as e:
    print("     列设备失败:", e)
PY
    log_ok "TF 环境就绪: $ENV_TF"
}

# =============================================================================
#  2) camps-bert : torch + bert_sklearn 0.2.0  (BERT)
# =============================================================================
install_bert_env() {
    log_step "[2/2] 创建 BERT 环境 $ENV_BERT_NAME (bert.bin)"

    if [ -x "$ENV_BERT/bin/python" ] && [ "$FORCE" != "1" ]; then
        if "$ENV_BERT/bin/python" -c 'import torch, bert_sklearn, sklearn' >/dev/null 2>&1; then
            log_ok "已存在且可导入 torch+bert_sklearn, 跳过 (FORCE=1 可强制重建)"
            "$ENV_BERT/bin/python" -c 'import torch, sys; print("     python %s | torch %s | cuda_built=%s | cuda_avail=%s" % (sys.version.split()[0], torch.__version__, torch.version.cuda, torch.cuda.is_available()))'
            NEED_VOCAB=1
            return 0
        fi
        log_warn "环境存在但导入失败, 继续补装依赖"
    elif [ "$FORCE" = "1" ] && [ -d "$ENV_BERT" ]; then
        log_warn "FORCE=1 → 删除旧环境 $ENV_BERT"
        rm -rf "$ENV_BERT"
    fi

    mamba_create "$ENV_BERT" conda-forge -- "python=$BERT_PY" "pip" || \
        die "创建 python=$BERT_PY 环境失败"

    # ---- torch: GPU / CPU 走不同 index; 版本按 2.4.1 → 2.3.1 → 2.2.2 回退 ----
    # (钉 <2.6 是为了 torch.load 的 weights_only 默认值; 仓库里已加 torch_load_compat 双保险)
    local tv ok=0
    for tv in "${TORCH_VER:-2.4.1}" 2.3.1 2.2.2; do
        if [ "$BERT_FLAVOR" = "gpu" ]; then
            log_info "安装 torch==$tv (CUDA ${TORCH_CUDA} 版, 下载约 2.5GB + nvidia 运行库约 3GB)..."
            # shellcheck disable=SC2046
            if env_pip "$ENV_BERT" install --no-input --disable-pip-version-check \
                       --no-warn-script-location $(pip_index_args) "torch==$tv"; then
                ok=1; break
            fi
            log_warn "  → torch==$tv (GPU) 失败, 换 $([ "$tv" = 2.4.1 ] && echo 2.3.1 || echo 2.2.2) 再试"
        else
            log_info "安装 torch==$tv+cpu (下载约 190MB)..."
            if env_pip "$ENV_BERT" install --no-input --disable-pip-version-check \
                       --no-warn-script-location \
                       --index-url "https://download.pytorch.org/whl/cpu" "torch==$tv+cpu"; then
                ok=1; break
            fi
            # shellcheck disable=SC2046
            if env_pip "$ENV_BERT" install --no-input --disable-pip-version-check \
                       --no-warn-script-location $(pip_index_args) "torch==$tv"; then
                ok=1; break
            fi
            log_warn "  → torch==$tv (CPU) 失败, 换下一个版本再试"
        fi
    done
    if [ "$ok" != 1 ]; then
        die "torch 安装失败。磁盘不够或网络受限时: bash $0 --bert-cpu / 设置 PIP_INDEX_URL 换源"
    fi

    log_info "安装 BERT 侧其余依赖..."
    # shellcheck disable=SC2046
    env_pip "$ENV_BERT" install --no-input --disable-pip-version-check --no-warn-script-location \
        $(pip_index_args) -r "$SCRIPT_DIR/requirements_bert.txt" || \
        die "pip 安装 requirements_bert.txt 失败"

    # ---- 装仓库自带的 bert_sklearn 0.2.0 ----
    # 注意: setup.py 在 bert_sklearn/ 目录 **里面**, 所以要在仓库根目录执行 `pip install ./bert_sklearn`
    # (README 里写的 `cd bert-sklearn && pip install .` 是错的, 那样 find_packages 找不到顶层包)
    # --no-deps: 依赖已在上一步全部钉死, 否则它会把 torch 拉到最新版
    log_info "安装仓库自带 bert_sklearn 0.2.0 (--no-deps)..."
    env_pip "$ENV_BERT" install --no-input --disable-pip-version-check --no-warn-script-location \
        --no-deps --force-reinstall "$PROJECT_DIR/bert_sklearn" || \
        die "bert_sklearn 安装失败"

    log_info "自检 BERT 环境..."
    "$ENV_BERT/bin/python" - <<'PY' || die "BERT 环境自检失败"
import sys, numpy, sklearn, torch
import bert_sklearn
from bert_sklearn import load_model
print("     python %s | numpy %s | sklearn %s | torch %s | bert_sklearn %s" % (
    sys.version.split()[0], numpy.__version__, sklearn.__version__,
    torch.__version__, bert_sklearn.__version__))
print("     torch.version.cuda = %s | torch.cuda.is_available() = %s" % (
    torch.version.cuda, torch.cuda.is_available()))
if torch.cuda.is_available():
    print("     GPU = %s (sm_%d%d)" % (torch.cuda.get_device_name(0),
                                        *torch.cuda.get_device_capability(0)))
PY
    log_ok "BERT 环境就绪: $ENV_BERT"
    NEED_VOCAB=1
}

# =============================================================================
#  3) BERT tokenizer 需要的 vocab.txt (bert-base-uncased, 231KB)
# =============================================================================
ensure_vocab() {
    [ "$NEED_VOCAB" = "1" ] || return 0
    log_step "[3/3] 准备 bert-base-uncased vocab.txt (tokenizer 必需)"

    local d1="$PROJECT_DIR/Models/bert-base-uncased"
    local d2="$HOME/.cache/torch/pretrained_bert"
    local f1="$d1/vocab.txt" f2="$d2/bert-base-uncased-vocab.txt"
    mkdir -p "$d1" "$d2" 2>/dev/null || true

    if [ -s "$f1" ] || [ -s "$f2" ]; then
        log_ok "vocab.txt 已存在, 跳过"
        [ -s "$f1" ] && echo "     $f1 ($(wc -l < "$f1") 行)"
        [ -s "$f2" ] && echo "     $f2 ($(wc -l < "$f2") 行)"
        return 0
    fi

    # prediction_bert.py / restore_finetuned_model 都会在这两个位置找 vocab
    local urls=(
        "${HF_VOCAB_URL:-https://huggingface.co/bert-base-uncased/resolve/main/vocab.txt}"
        "https://hf-mirror.com/bert-base-uncased/resolve/main/vocab.txt"
        "https://s3.amazonaws.com/models.huggingface.co/bert/bert-base-uncased-vocab.txt"
    )
    local u ok=0
    for u in "${urls[@]}"; do
        log_info "尝试下载: $u"
        if command -v curl >/dev/null 2>&1; then
            curl -fLs --max-time 120 "$u" -o "$f1.tmp" && [ -s "$f1.tmp" ] && ok=1
        else
            wget -q --timeout=120 -O "$f1.tmp" "$u" && [ -s "$f1.tmp" ] && ok=1
        fi
        [ "$ok" = "1" ] && break
    done

    if [ "$ok" != "1" ]; then
        rm -f "$f1.tmp"
        log_warn "vocab.txt 下载失败 (离线环境?)。BERT 会因 tokenizer 无法解析而退出 (exit 2)。"
        log_warn "手动解决: 把 bert-base-uncased 的 vocab.txt 放到 $f1"
        return 0
    fi

    # 合理性校验: 标准 vocab 是 30522 行
    local n; n=$(wc -l < "$f1.tmp")
    if [ "$n" -lt 20000 ]; then
        log_warn "下载到的 vocab.txt 只有 $n 行 (标准应 30522 行), 疑似被代理拦截, 已丢弃。"
        rm -f "$f1.tmp"; return 0
    fi
    mv "$f1.tmp" "$f1"
    cp "$f1" "$f2" 2>/dev/null || true
    log_ok "vocab.txt 就位 ($n 行)"
    echo "     $f1"
    echo "     $f2"
}

# =============================================================================
#  4) bert.bin (官方只给 Dropbox, 无法自动下载 → 支持从本地拷)
# =============================================================================
ensure_bert_bin() {
    if [ -n "$BERT_BIN_SRC" ]; then
        [ -f "$BERT_BIN_SRC" ] || die "--bert-bin 指定的文件不存在: $BERT_BIN_SRC"
        log_step "拷贝 bert.bin: $BERT_BIN_SRC → $PROJECT_DIR/Models/bert.bin"
        cp -f "$BERT_BIN_SRC" "$PROJECT_DIR/Models/bert.bin" || die "拷贝失败"
    fi

    if [ -f "$PROJECT_DIR/Models/bert.bin" ]; then
        log_ok "Models/bert.bin 已存在 ($(du -h "$PROJECT_DIR/Models/bert.bin" | cut -f1))"
        if command -v md5sum >/dev/null 2>&1; then
            local real want=990d14de053d8080fcca33d712d647b6
            real=$(md5sum "$PROJECT_DIR/Models/bert.bin" | cut -d' ' -f1)
            if [ "$real" = "$want" ]; then
                log_ok "md5 校验通过: $real"
            else
                log_warn "md5 不匹配! 期望 $want, 实际 $real (文件可能没下完整)"
            fi
        fi
    else
        log_warn "Models/bert.bin 缺失 —— Attention/LSTM 照常可用, BERT 那一路会跳过。"
        log_warn "官方下载地址 (Dropbox, 需要浏览器):"
        log_warn "  https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0"
        log_warn "  md5 = 990d14de053d8080fcca33d712d647b6"
        log_warn "拿到文件后: bash amp_pipeline/install_envs.sh --bert-bin /path/to/bert.bin"
    fi
}

# =============================================================================
#  5) 收尾: 写一个 env.sh 方便以后 source
# =============================================================================
write_env_sh() {
    local f="$PROJECT_DIR/amp_pipeline/env.sh"
    cat > "$f" <<EOF
# 由 install_envs.sh 于 $(date '+%Y-%m-%d %H:%M:%S') 生成
# 用法:  source amp_pipeline/env.sh
export ENV_TF="$ENV_TF"
export ENV_BERT="$ENV_BERT"
export CONDA_ROOT="$CONDA_ROOT"
export TF_USE_GPU="\${TF_USE_GPU:-auto}"
export BERT_USE_CUDA="\${BERT_USE_CUDA:-auto}"
export BERT_EVAL_BATCH_SIZE="\${BERT_EVAL_BATCH_SIZE:-64}"
export BERT_MAX_SEQ_LENGTH="\${BERT_MAX_SEQ_LENGTH:-64}"
EOF
    log_ok "已写出 $f  (以后 source 它就不用再传环境路径)"
}

# ------------------------------------------------------------------ 执行 ----
[ "$DO_TF" = "1" ]   && install_tf_env
[ "$DO_BERT" = "1" ] && install_bert_env
[ "$DO_BERT" = "1" ] && ensure_vocab
ensure_bert_bin
write_env_sh

t_end
echo
echo "=============================================================="
echo " 安装完成。下一步跑三模型自检:"
echo "=============================================================="
echo "   bash amp_pipeline/smoke_test_3models.sh"
echo
echo " 环境路径 (已写入 amp_pipeline/env.sh):"
echo "   ENV_TF   = $ENV_TF"
echo "   ENV_BERT = $ENV_BERT"
echo
echo " 手动激活的话:"
echo "   conda activate $ENV_TF      # Attention / LSTM"
echo "   conda activate $ENV_BERT    # BERT"
echo "=============================================================="
