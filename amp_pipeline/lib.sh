#!/usr/bin/env bash
# ==============================================================================
# amp_pipeline/lib.sh —— 三模型流程的公共函数库 (环境自动探测 / mamba 解析 / 日志)
#
# 被这些脚本 source:
#   install_envs.sh        —— 一键建两个 conda 环境
#   smoke_test_3models.sh  —— 三模型逐条自检 (含端到端小样本)
#   test_models.sh         —— 端到端小样本 (旧入口, 保留)
#   run_pipeline_one.sh    —— 单分组预测
#   run_pipeline_all_groups.sh —— 批量分组预测
#
# 设计目标: **换机器不用改脚本**。
#   旧版本把 conda 环境路径硬编码成 /home/w26/miniconda3/envs/..., 换到
#   wsh@DESKTOP-xxx 这种机器上就必然预检失败。这里改成:
#     1) 环境变量显式指定 (ENV_TF / ENV_BERT)  —— 最高优先级
#     2) `conda info --base` / CONDA_EXE 推断出的 conda root 下的 envs/<name>
#     3) $HOME/{miniconda3,mambaforge,miniforge3,anaconda3}/envs/<name>
#     4) 当前已激活环境的同级 envs 目录
# ==============================================================================

# 注意: 这里 **不用** `set -euo pipefail`, 因为本文件是被 source 的,
#       贸然改调用方的 shell 选项会造成很隐蔽的行为变化。
#       需要严格模式的脚本自己在 source 之后设置。

# ---------------------------------------------------------------- 基础路径 ----
amps_script_dir() {
    # 本文件所在目录 (amp_pipeline/)
    local src="${BASH_SOURCE[0]}"
    # 兼容 source 时 BASH_SOURCE[0] 指向 lib.sh 本身
    [ -f "$src" ] || src="${AMP_PIPELINE_DIR:-}/lib.sh"
    cd "$(dirname "$src")" 2>/dev/null && pwd
}

AMP_PIPELINE_DIR="${AMP_PIPELINE_DIR:-$(amps_script_dir)}"
PROJECT_DIR_DEFAULT="$(cd "$AMP_PIPELINE_DIR/.." && pwd)"

# ------------------------------------------------------------------- 日志 -----
_c_reset=""; _c_red=""; _c_grn=""; _c_ylw=""; _c_cyn=""; _c_bld=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_grn=$'\033[32m'
    _c_ylw=$'\033[33m'; _c_cyn=$'\033[36m'; _c_bld=$'\033[1m'
fi
log_info()  { echo "${_c_cyn}[INFO]${_c_reset}  $*"; }
log_ok()    { echo "${_c_grn}[ OK ]${_c_reset}  $*"; }
log_warn()  { echo "${_c_ylw}[WARN]${_c_reset}  $*" >&2; }
log_error() { echo "${_c_red}[FAIL]${_c_reset}  $*" >&2; }
log_step()  { echo; echo "${_c_bld}==>${_c_reset} ${_c_bld}$*${_c_reset}"; }

die() { log_error "$*"; exit 1; }

# 计时工具: t_start / t_end  <标签>
_T0=0
t_start() { _T0=$(date +%s); }
t_end()   { echo "      (耗时 $(( $(date +%s) - _T0 ))s ${1:+· $1})"; }

# --------------------------------------------------------- conda root 探测 ----
conda_root_guess() {
    local cands=() p base

    # 1) conda / mamba 自己说的 base (最权威)
    for p in "${CONDA_EXE:-}" "$(command -v conda 2>/dev/null || true)" \
             "$(command -v mamba 2>/dev/null || true)"; do
        [ -n "$p" ] || continue
        [ -x "$p" ] || continue
        if base="$(CONDA_PKGS_DIRS="" "$p" info --base 2>/dev/null | tr -d '\r' | tail -1)" && [ -n "$base" ]; then
            case "$base" in /*) cands+=("$base");; esac
        fi
    done

    # 2) 当前激活环境往上剥 (兼容 envs/xxx 与自定义 prefix)
    if [ -n "${CONDA_PREFIX:-}" ]; then
        cands+=("$(dirname "$CONDA_PREFIX")")
        cands+=("$CONDA_PREFIX")
    fi
    if [ -n "${MAMBA_ROOT_PREFIX:-}" ]; then cands+=("$MAMBA_ROOT_PREFIX"); fi

    # 3) 常见安装位置
    cands+=("$HOME/miniconda3" "$HOME/mambaforge" "$HOME/miniforge3"
            "$HOME/anaconda3" "$HOME/micromamba"
            "/opt/conda" "/opt/miniconda3" "/opt/mambaforge")

    local c
    for c in "${cands[@]}"; do
        [ -n "$c" ] || continue
        if [ -d "$c/envs" ]; then (cd "$c" 2>/dev/null && pwd); return 0; fi
    done
    # 一个都没有: 退回家目录
    echo "$HOME"
}

CONDA_ROOT="${CONDA_ROOT:-$(conda_root_guess)}"

# ------------------------------------------------------------------ 求解器 ----
# 优先级: 已装 mamba > micromamba(自动下载) > conda --solver=libmamba > conda classic
# 可用 MAMBA_MODE=off 强制走 conda classic; MAMBA_MODE=auto|micromamba|mamba|libmamba 指定。
SOLVER_CMD=""
SOLVER_LABEL=""

_mamba_probe() {
    local mode="${MAMBA_MODE:-auto}"
    [ "$mode" = "off" ] && { SOLVER_LABEL="conda (classic solver)"; return 1; }

    # --- mamba ---
    if [ "$mode" = "auto" ] || [ "$mode" = "mamba" ]; then
        if command -v mamba >/dev/null 2>&1; then
            SOLVER_CMD=(env CONDA_PKGS_DIRS="" mamba); SOLVER_LABEL="mamba"; return 0
        fi
        if [ -x "$CONDA_ROOT/bin/mamba" ] || [ -x "$CONDA_ROOT/condabin/mamba" ]; then
            local mb="$CONDA_ROOT/bin/mamba"; [ -x "$mb" ] || mb="$CONDA_ROOT/condabin/mamba"
            SOLVER_CMD=(env CONDA_PKGS_DIRS="" "$mb"); SOLVER_LABEL="mamba"; return 0
        fi
        [ "$mode" = "mamba" ] && { log_error "MAMBA_MODE=mamba 但找不到 mamba 可执行文件"; return 1; }
    fi

    # --- micromamba (单文件静态二进制, 不需要 root, 不污染 base) ---
    if [ "$mode" = "auto" ] || [ "$mode" = "micromamba" ]; then
        local mm="${MICROMAMBA_BIN:-$CONDA_ROOT/bin/micromamba}"
        if [ ! -x "$mm" ]; then
            mm="$(command -v micromamba 2>/dev/null || true)"
        fi
        if [ -z "$mm" ] || [ ! -x "$mm" ]; then
            mm="$HOME/.local/bin/micromamba"
        fi
        if [ ! -x "$mm" ]; then
            log_warn "没找到 mamba/micromamba, 尝试下载 micromamba (~8MB) 以加速解析..."
            mkdir -p "$(dirname "$mm")" 2>/dev/null || true
            local url="${MICROMAMBA_URL:-https://micro.mamba.pm/api/micromamba/linux-64/latest}"
            if command -v curl >/dev/null 2>&1; then
                curl -Ls --max-time 180 "$url" | tar -xj -C "$(dirname "$mm")" --strip-components=1 bin/micromamba 2>/dev/null || true
            elif command -v wget >/dev/null 2>&1; then
                wget -qO- --timeout=180 "$url" | tar -xj -C "$(dirname "$mm")" --strip-components=1 bin/micromamba 2>/dev/null || true
            fi
            chmod +x "$mm" 2>/dev/null || true
        fi
        if [ -x "$mm" ]; then
            SOLVER_CMD=(env MAMBA_ROOT_PREFIX="$CONDA_ROOT" CONDA_PKGS_DIRS="" "$mm")
            SOLVER_LABEL="micromamba ($mm)"; return 0
        fi
        [ "$mode" = "micromamba" ] && { log_error "MAMBA_MODE=micromamba 但下载/定位失败"; return 1; }
    fi

    # --- conda + libmamba solver ---
    local conda_bin=""
    [ -n "${CONDA_EXE:-}" ] && [ -x "${CONDA_EXE}" ] && conda_bin="$CONDA_EXE"
    [ -z "$conda_bin" ] && conda_bin="$(command -v conda 2>/dev/null || true)"
    [ -z "$conda_bin" ] && [ -x "$CONDA_ROOT/bin/conda" ] && conda_bin="$CONDA_ROOT/bin/conda"
    if [ -n "$conda_bin" ]; then
        local basepy="$CONDA_ROOT/bin/python"
        if [ -x "$basepy" ]; then
            SOLVER_CMD=("$basepy" "$conda_bin"); SOLVER_LABEL="conda (libmamba solver)"
        else
            SOLVER_CMD=("$conda_bin"); SOLVER_LABEL="conda (libmamba solver)"
        fi
        return 0
    fi

    return 1
}

# mamba_create <env_prefix> <channel...> -- <spec...>
mamba_create() {
    local prefix="$1"; shift
    local -a chans=() specs=()
    local seen_dd=0 a
    for a in "$@"; do
        if [ "$a" = "--" ]; then seen_dd=1; continue; fi
        if [ "$seen_dd" = "0" ]; then chans+=("$a"); else specs+=("$a"); fi
    done
    [ -n "$SOLVER_CMD" ] || _mamba_probe || die "找不到 mamba/micromamba/conda, 无法创建环境。请先装 miniforge: https://github.com/conda-forge/miniforge"

    local -a cc=()
    for a in "${chans[@]}"; do cc+=(-c "$a"); done
    # --override-channels: 避免 base 里配了的其它 channel 干扰老包解析

    log_info "创建环境: $prefix"
    log_info "求解器  : $SOLVER_LABEL"
    log_info "channel : ${chans[*]}"
    log_info "spec    : ${specs[*]}"
    "${SOLVER_CMD[@]}" create -y -p "$prefix" "${cc[@]}" --override-channels "${specs[@]}"
}

mamba_install() {
    local prefix="$1"; shift
    [ -n "$SOLVER_CMD" ] || _mamba_probe || die "找不到求解器"
    "${SOLVER_CMD[@]}" install -y -p "$prefix" "$@"
}

# ------------------------------------------------------------- pip 相关工具 ---
env_pip() {  # env_pip <env_prefix> <pip args...>
    local prefix="$1"; shift
    "$prefix/bin/python" -m pip "$@"
}

# py3.6 自带的 pip 9.0.3 太老, 直接装现代包会报 wheel tag / metadata 不兼容。
# 分两级 bootstrap: 9.0.3 -> 20.3.4 (py3.6 能识别 manylinux2014) -> 21.3.1 (py3.6 最后一版)
bootstrap_pip_py36() {
    local prefix="$1"
    local ver; ver="$("$prefix/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
    if [ "$ver" != "3.6" ]; then return 0; fi
    log_info "bootstrap pip (python3.6 专用两段式升级)..."
    env_pip "$prefix" install --quiet --disable-pip-version-check --no-warn-script-location \
        "pip==20.3.4" || return 1
    env_pip "$prefix" install --quiet --disable-pip-version-check --no-warn-script-location \
        "pip==21.3.1" "setuptools==59.6.0" "wheel==0.37.1" || return 1
    env_pip "$prefix" --version
}

# 国内网络可选加速: PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
pip_index_args() {
    if [ -n "${PIP_INDEX_URL:-}" ]; then
        echo "-i ${PIP_INDEX_URL} --trusted-host $(echo "$PIP_INDEX_URL" | awk -F/ '{print $3}')"
    fi
}

# -------------------------------------------------- 两个预测环境的自动探测 ----
ENV_TF_NAME="${ENV_TF_NAME:-camps-tf114}"
ENV_BERT_NAME="${ENV_BERT_NAME:-camps-bert}"

_find_env_prefix() {
    # $1 = 环境名; 输出 prefix 路径, 找不到返回 1
    local name="$1" p
    for p in \
        "$CONDA_ROOT/envs/$name" \
        "${CONDA_PREFIX:+$(dirname "$CONDA_PREFIX")/envs/$name}" \
        "$HOME/miniconda3/envs/$name" \
        "$HOME/mambaforge/envs/$name" \
        "$HOME/miniforge3/envs/$name" \
        "$HOME/anaconda3/envs/$name" \
        "$HOME/micromamba/envs/$name" \
        "/opt/conda/envs/$name" \
        "$name" ; do
        [ -n "$p" ] || continue
        if [ -x "$p/bin/python" ]; then (cd "$p" && pwd); return 0; fi
    done
    return 1
}

resolve_envs() {
    ENV_TF="${ENV_TF:-$(_find_env_prefix "$ENV_TF_NAME" || true)}"
    # 历史遗留: 老脚本里 BERT 环境叫 py36, 兼容一下
    if [ -z "${ENV_BERT:-}" ]; then
        ENV_BERT="$(_find_env_prefix "$ENV_BERT_NAME" || true)"
        [ -n "$ENV_BERT" ] || ENV_BERT="$(_find_env_prefix py36 || true)"
    fi
    export ENV_TF ENV_BERT
}

env_status_line() {
    resolve_envs
    printf '  TF  环境 (%s): %s\n' "$ENV_TF_NAME" "${ENV_TF:-<未找到>}"
    printf '  BERT环境 (%s): %s\n' "$ENV_BERT_NAME" "${ENV_BERT:-<未找到>}"
    printf '  conda root  : %s\n' "$CONDA_ROOT"
}

# ------------------------------------------------------- GPU / 设备判定 ------
gpu_name() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,memory.total,driver_version \
                   --format=csv,noheader 2>/dev/null | head -4
    elif [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
        echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES (nvidia-smi 不可用)"
    fi
}

# TF_USE_GPU: auto|1|0  —— auto 时会跑一次真实 kernel 探测 (Ampere + CUDA10 常失败)
tf_gpu_works() {
    local prefix="$1"
    [ -x "$prefix/bin/python" ] || return 1
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    [ -f "$prefix/lib/libcudart.so.10.0" ] || [ -f "$prefix/lib/libcudart.so" ] || return 1
    "$prefix/bin/python" - <<'PY' >/dev/null 2>&1
import tensorflow as tf
with tf.Session() as s:
    if not s.list_devices():
        raise SystemExit(1)
    a = tf.constant([[1.0, 2.0]], dtype=tf.float32)
    r = s.run(tf.matmul(a, tf.transpose(a)))   # 真跑一个 kernel, 才能暴露 sm_86 不兼容
    assert abs(float(r[0][0]) - 5.0) < 1e-3
PY
}

# 在 TF 预测前统一注入设备策略。用法: apply_tf_device_policy
apply_tf_device_policy() {
    local mode="${TF_USE_GPU:-auto}"
    case "$mode" in
        0|false|no|cpu|CPU)
            export CUDA_VISIBLE_DEVICES=""
            log_info "TF 设备策略: 强制 CPU (TF_USE_GPU=$mode)"
            ;;
        1|true|yes|gpu|GPU)
            log_info "TF 设备策略: 强制 GPU (TF_USE_GPU=$mode)"
            ;;
        *)
            if [ -n "${ENV_TF:-}" ] && tf_gpu_works "$ENV_TF"; then
                log_info "TF 设备策略: GPU (kernel 探测通过)"
            else
                export CUDA_VISIBLE_DEVICES=""
                log_info "TF 设备策略: CPU (auto 探测未通过 → 小模型走 CPU 更稳, 速度差异不大)"
            fi
            ;;
    esac
}

# --------------------------------------------------------- 模型文件检查 ------
check_model_files() {
    # $1 = project dir; 返回缺失模型列表 (打印), bert.bin 缺失只警告
    local pdir="$1" miss=""
    for m in att.h5 lstm.h5; do
        [ -f "$pdir/Models/$m" ] || miss="$miss $m"
    done
    if [ -n "$miss" ]; then
        log_error "缺少模型文件:$miss  (应在 $pdir/Models/)"
        return 1
    fi
    if [ ! -f "$pdir/Models/bert.bin" ]; then
        log_warn "Models/bert.bin 不存在 —— BERT 这一路会跳过。"
        log_warn "官方只给了 Dropbox 链接, 见 Models/ReadME.txt:"
        log_warn "  https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0"
        log_warn "  md5 = 990d14de053d8080fcca33d712d647b6"
        log_warn "下载后放到 $pdir/Models/bert.bin, 或: bash amp_pipeline/install_envs.sh --bert-bin /path/to/bert.bin"
        return 2
    fi
    return 0
}
