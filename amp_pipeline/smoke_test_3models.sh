#!/usr/bin/env bash
# ==============================================================================
# smoke_test_3models.sh —— 「三个模型跑通」一键自检
#
#   模型1 Attention (Models/att.h5)   ┐
#   模型2 LSTM      (Models/lstm.h5)  ├─ camps-tf114 环境 (tensorflow 1.14 / Keras 2.2.4)
#   模型3 BERT      (Models/bert.bin) ── camps-bert   环境 (torch / bert_sklearn 0.2.0)
#
# 分 5 段:
#   [0] 环境预检 (conda 环境 / 模型文件 / perl / GPU)
#   [1] TF 侧真实加载 att.h5 + lstm.h5 并各跑一次 predict
#   [2] BERT 侧真实加载 bert.bin + tokenizer 并跑一次 predict_proba
#   [3] 端到端小样本: Data/AMPs.fa 前 N 条 → format.pl → 三模型 → result.pl → 汇总
#   [4] 结论表 (PASS/FAIL/SKIP + 耗时)
#
# 用法:
#   bash amp_pipeline/smoke_test_3models.sh                # N=20, 全跑
#   N=100 bash amp_pipeline/smoke_test_3models.sh          # 用 100 条
#   bash amp_pipeline/smoke_test_3models.sh --no-e2e       # 只做 [1][2] 模型自检
#   bash amp_pipeline/smoke_test_3models.sh --only tf      # 只测 Attention+LSTM
#   bash amp_pipeline/smoke_test_3models.sh --only bert    # 只测 BERT
#   SMOKE_SKIP_BERT=1 bash amp_pipeline/smoke_test_3models.sh   # 没有 bert.bin 时测另两个 + 端到端链路
#   TF_USE_GPU=1 BERT_USE_CUDA=1 bash amp_pipeline/smoke_test_3models.sh   # 强制走 GPU
#   bash amp_pipeline/smoke_test_3models.sh /path/to/your.fa               # 换输入
#
# 退出码: 0 = 该测的都过了; 1 = 有 FAIL
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

N="${N:-20}"
OUT_DIR="${SMOKE_OUT:-$PROJECT_DIR/test_run/smoke}"
ONLY="${ONLY:-all}"          # all | tf | bert
DO_E2E=1
INPUT_FA=""

while [ $# -gt 0 ]; do
    case "$1" in
        --no-e2e)   DO_E2E=0 ;;
        --only)     shift; ONLY="${1:-all}" ;;
        --n|-n)     shift; N="${1:-20}" ;;
        --out)      shift; OUT_DIR="${1:-$OUT_DIR}" ;;
        -h|--help)  awk 'NR>1 && /^set -/{exit} NR>1{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
        -*)         die "未知参数: $1 (--help 看用法)" ;;
        *)          INPUT_FA="$1" ;;
    esac
    shift
done

export PROJECT_DIR
mkdir -p "$OUT_DIR"
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"

# ------------------------------------------------------------ 结果收集 ------
declare -a R_NAME=() R_STAT=() R_TIME=() R_NOTE=()
add_result() { R_NAME+=("$1"); R_STAT+=("$2"); R_TIME+=("$3"); R_NOTE+=("$4"); }

print_summary_and_exit() {
    local i nfail=0 nskip=0 npass=0
    echo
    echo "=============================================================="
    echo " 自检结论"
    echo "=============================================================="
    printf '  %-32s %-6s %-8s %s\n' "项目" "结果" "耗时" "备注"
    printf '  %-32s %-6s %-8s %s\n' "--------------------------------" "------" "--------" "--------------------"
    for i in "${!R_NAME[@]}"; do
        case "${R_STAT[$i]}" in
            PASS) npass=$((npass + 1)) ;;
            SKIP) nskip=$((nskip + 1)) ;;
            *)    nfail=$((nfail + 1)) ;;
        esac
        printf '  %-32s %-6s %-8s %s\n' \
            "${R_NAME[$i]}" "${R_STAT[$i]}" "${R_TIME[$i]}" "${R_NOTE[$i]}"
    done
    echo "=============================================================="
    if [ "$nfail" = 0 ]; then
        echo " ${_c_grn}${_c_bld}PASS $npass / SKIP $nskip / FAIL 0${_c_reset}"
        echo " 该测的模型都能加载并出概率, 端到端链路可用。"
    else
        echo " ${_c_red}${_c_bld}PASS $npass / SKIP $nskip / FAIL $nfail${_c_reset}"
        echo " 有失败项, 按上面各段日志逐个排查 (日志都在 $LOG_DIR)。"
    fi
    echo " 产物目录: $OUT_DIR"
    echo "=============================================================="
    if [ "$nfail" = 0 ]; then exit 0; else exit 1; fi
}

# run_stage <名字> <logfile> <命令...>   (子命令退出码 2 = SKIP)
run_stage() {
    local label="$1" logf="$2"; shift 2
    log_step "$label"
    echo "      日志: $logf"
    local t0 t1 rc stat note
    t0=$(date +%s)
    "$@" >"$logf" 2>&1
    rc=$?
    t1=$(date +%s)
    sed 's/^/    | /' "$logf"
    case "$rc" in
        0) stat="PASS"; note="" ;;
        2) stat="SKIP"; note="exit=2, 见日志" ;;
        *) stat="FAIL"; note="exit=$rc, 详见 $(basename "$logf")" ;;
    esac
    add_result "$label" "$stat" "$((t1 - t0))s" "$note"
    return $rc
}

# 端到端用哪个 python 跑 subset_fasta / aggregate
pick_py3() {
    local p
    for p in "${PYTHON:-}" "$(command -v python3 2>/dev/null || true)" \
             "${ENV_BERT:+$ENV_BERT/bin/python}" "${ENV_TF:+$ENV_TF/bin/python}" \
             "$(command -v python 2>/dev/null || true)"; do
        [ -n "$p" ] && [ -x "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

echo "=============================================================="
echo " c_AMPs-prediction · 三模型跑通自检"
echo "=============================================================="
echo "  时间      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  主机      : $(hostname 2>/dev/null || echo '?') / $(uname -sr)"
echo "  项目目录  : $PROJECT_DIR"
echo "  输出目录  : $OUT_DIR"
echo "  样本条数  : $N"
echo "  测试范围  : $ONLY $([ "$DO_E2E" = 1 ] && echo '(含端到端)' || echo '(不含端到端)')"
echo "--------------------------------------------------------------"
echo "  CPU       : $(nproc 2>/dev/null || echo '?') 核"
echo "  内存      : $(free -h 2>/dev/null | awk '/^Mem:/{print $2" 总 / "$7" 可用"}')"
echo "  磁盘      : $(df -Ph "$PROJECT_DIR" 2>/dev/null | awk 'NR==2{print $4" 可用 ("$5" 已用)"}')"
g="$(gpu_name || true)"
if [ -n "$g" ]; then
    echo "  GPU       : $(echo "$g" | head -1)"
    echo "              驱动 $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1) | $(nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9.]*' | head -1)"
    ngpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    [ "$ngpu" -gt 1 ] && echo "              共 $ngpu 张卡; 想指定某张: BERT_GPU=1 bash $0"
else
    echo "  GPU       : 未检测到 nvidia-smi → 全部走 CPU"
fi
echo "=============================================================="

# =============================================================================
#  [0] 环境预检
# =============================================================================
log_step "[0] 环境预检 (fail-fast)"
resolve_envs
env_status_line

PRE_OK=1
MISS_BERT=0

check_model_files "$PROJECT_DIR"
rc_model=$?
[ "$rc_model" = "1" ] && PRE_OK=0
[ "$rc_model" = "2" ] && MISS_BERT=1

for f in script/format.pl script/result.pl script/Attention.py \
         script/prediction_attention.py script/prediction_lstm.py script/prediction_bert.py; do
    [ -f "$PROJECT_DIR/$f" ] || { log_error "缺文件: $f"; PRE_OK=0; }
done
command -v perl >/dev/null 2>&1 || { log_error "找不到 perl (format.pl / result.pl 需要)"; PRE_OK=0; }

NEED_TF=0; NEED_BERT=0
case "$ONLY" in
    all)  NEED_TF=1; NEED_BERT=1 ;;
    tf)   NEED_TF=1 ;;
    bert) NEED_BERT=1 ;;
    *)    die "--only 只接受 all / tf / bert" ;;
esac

if [ "$NEED_TF" = 1 ]; then
    if [ -z "${ENV_TF:-}" ] || [ ! -x "${ENV_TF}/bin/python" ]; then
        log_error "找不到 TF 环境 ($ENV_TF_NAME) → 先跑: bash amp_pipeline/install_envs.sh --only tf"
        PRE_OK=0
    else
        v="$("$ENV_TF/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
        log_ok "TF 环境可用: $ENV_TF (python $v)"
    fi
fi
if [ "$NEED_BERT" = 1 ] && [ "$MISS_BERT" = 0 ]; then
    if [ -z "${ENV_BERT:-}" ] || [ ! -x "${ENV_BERT}/bin/python" ]; then
        log_error "找不到 BERT 环境 ($ENV_BERT_NAME) → 先跑: bash amp_pipeline/install_envs.sh --only bert"
        PRE_OK=0
    else
        v="$("$ENV_BERT/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
        log_ok "BERT 环境可用: $ENV_BERT (python $v)"
    fi
fi

if [ "$PRE_OK" != 1 ]; then
    add_result "[0] 环境预检" "FAIL" "0s" "见上方 FAIL 行"
    print_summary_and_exit
fi
add_result "[0] 环境预检" "PASS" "0s" ""

# =============================================================================
#  [1] TF 侧: Attention + LSTM
# =============================================================================
rc_att=0; rc_lstm=0
if [ "$NEED_TF" = 1 ]; then
    apply_tf_device_policy

    run_stage "[1a] Attention (att.h5)" "$LOG_DIR/attention.log" \
        env PYTHONPATH="$PROJECT_DIR/script" CUDA_DEVICE_ORDER=PCI_BUS_ID \
            "$ENV_TF/bin/python" "$PROJECT_DIR/script/_smoke_tf.py" att "$N"
    rc_att=$?

    run_stage "[1b] LSTM (lstm.h5)" "$LOG_DIR/lstm.log" \
        env PYTHONPATH="$PROJECT_DIR/script" CUDA_DEVICE_ORDER=PCI_BUS_ID \
            "$ENV_TF/bin/python" "$PROJECT_DIR/script/_smoke_tf.py" lstm "$N"
    rc_lstm=$?
fi

# =============================================================================
#  [2] BERT 侧
# =============================================================================
# 显式跳过 BERT: SMOKE_SKIP_BERT=1 (或 bert.bin 本来就缺失)
if [ "${SMOKE_SKIP_BERT:-0}" = "1" ]; then MISS_BERT=1; fi

if [ "$NEED_BERT" = 1 ]; then
    if [ "$MISS_BERT" = 1 ]; then
        log_step "[2] BERT (bert.bin)"
        if [ "${SMOKE_SKIP_BERT:-0}" = "1" ]; then
            log_warn "SMOKE_SKIP_BERT=1 → 本段 SKIP"
            add_result "[2] BERT (bert.bin)" "SKIP" "0s" "SMOKE_SKIP_BERT=1"
        else
            log_warn "Models/bert.bin 不存在 → 本段 SKIP (Attention/LSTM 不受影响)"
            add_result "[2] BERT (bert.bin)" "SKIP" "0s" "bert.bin 未下载"
        fi
    else
        run_stage "[2] BERT (bert.bin)" "$LOG_DIR/bert.log" \
            env PYTHONPATH="$PROJECT_DIR/script" CUDA_DEVICE_ORDER=PCI_BUS_ID \
                OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}" \
                "$ENV_BERT/bin/python" "$PROJECT_DIR/script/_smoke_bert.py" "$N"
    fi
fi

# =============================================================================
#  [3] 端到端小样本
# =============================================================================
if [ "$DO_E2E" = 1 ]; then
    log_step "[3] 端到端小样本 (format.pl → 三模型 → result.pl → 汇总)"

    if [ "$NEED_TF" = 1 ] && { [ "$rc_att" = 1 ] || [ "$rc_lstm" = 1 ]; }; then
        log_warn "TF 侧有 FAIL → 端到端必然失败, 本段 SKIP"
        add_result "[3] 端到端小样本" "SKIP" "0s" "TF 侧未通过"
    elif [ "$MISS_BERT" = 1 ] && [ "$NEED_BERT" = 1 ] && [ "$NEED_TF" = 0 ]; then
        add_result "[3] 端到端小样本" "SKIP" "0s" "bert.bin 缺失"
    else
        [ -n "$INPUT_FA" ] || INPUT_FA="$PROJECT_DIR/Data/AMPs.fa"
        PY3="$(pick_py3 || true)"
        if [ ! -f "$INPUT_FA" ]; then
            log_warn "输入 FASTA 不存在: $INPUT_FA → SKIP"
            add_result "[3] 端到端小样本" "SKIP" "0s" "无输入 FASTA"
        elif [ -z "$PY3" ]; then
            log_warn "找不到可用的 python3 → SKIP"
            add_result "[3] 端到端小样本" "SKIP" "0s" "无 python3"
        else
            E2E_DIR="$OUT_DIR/e2e"
            rm -rf "$E2E_DIR"; mkdir -p "$E2E_DIR"
            TMP_FA="$OUT_DIR/test_input.fa"
            "$PY3" "$SCRIPT_DIR/subset_fasta.py" "$INPUT_FA" "$N" > "$TMP_FA"
            echo "      输入: $INPUT_FA"
            echo "      取样: 前 $N 条 → $TMP_FA (实际 $(grep -c '^>' "$TMP_FA" || echo 0) 条)"
            echo "      python: $PY3"

            # bert.bin 缺失时造一份占位概率, 让 format.pl/result.pl/汇总 链路也能验证
            SKIP_BERT_ARG=""
            if [ "$MISS_BERT" = 1 ]; then
                log_warn "bert.bin 缺失 → 端到端用【占位 BERT 概率】验证流程 (结论不代表真实预测)"
                SKIP_BERT_ARG="skip-bert"
            fi

            t0=$(date +%s)
            if [ -n "$SKIP_BERT_ARG" ]; then
                bash "$SCRIPT_DIR/run_pipeline_one.sh" \
                    "$TMP_FA" "$E2E_DIR/run_output" "$PROJECT_DIR" "$ENV_TF" "$ENV_BERT" \
                    "$SKIP_BERT_ARG" >"$LOG_DIR/e2e.log" 2>&1
            else
                bash "$SCRIPT_DIR/run_pipeline_one.sh" \
                    "$TMP_FA" "$E2E_DIR/run_output" "$PROJECT_DIR" "$ENV_TF" "$ENV_BERT" \
                    >"$LOG_DIR/e2e.log" 2>&1
            fi
            rc_e2e=$?
            t1=$(date +%s)
            sed 's/^/    | /' "$LOG_DIR/e2e.log"

            if [ "$rc_e2e" = 0 ] && [ -s "$E2E_DIR/run_output/final_prediction.txt" ]; then
                add_result "[3] 端到端小样本" "PASS" "$((t1 - t0))s" \
                           "$([ -n "$SKIP_BERT_ARG" ] && echo 'BERT 为占位概率')"
                echo
                log_ok "final_prediction.txt (前 8 行):"
                head -8 "$E2E_DIR/run_output/final_prediction.txt" | sed 's/^/      /'
                n_amp=$(awk -F';' '$NF==1{c++} END{print c+0}' "$E2E_DIR/run_output/final_prediction.txt")
                n_tot=$(grep -c '^>' "$E2E_DIR/run_output/final_prediction.txt" || echo 0)
                echo "      → 三票一致判为 AMP: $n_amp / $n_tot 条"
                [ "$MISS_BERT" = 1 ] && echo "      (BERT 是占位概率, 所以这里必然为 0, 属正常)"

                log_info "跑汇总 aggregate_amp_results.py ..."
                "$PY3" "$SCRIPT_DIR/aggregate_amp_results.py" "$E2E_DIR/run_output" \
                    >"$LOG_DIR/aggregate.log" 2>&1
                rc_agg=$?
                tail -25 "$LOG_DIR/aggregate.log" | sed 's/^/    | /'
                if [ "$rc_agg" = 0 ]; then
                    add_result "[3b] 三模型汇总 aggregate" "PASS" "-" ""
                    if [ -f "$E2E_DIR/run_output/aggregated_results.tsv" ]; then
                        echo
                        log_ok "明细表 aggregated_results.tsv 前 6 行:"
                        { column -t -s"$(printf '\t')" < "$E2E_DIR/run_output/aggregated_results.tsv" 2>/dev/null \
                          || cat "$E2E_DIR/run_output/aggregated_results.tsv"; } | head -6 | sed 's/^/      /'
                    fi
                else
                    add_result "[3b] 三模型汇总 aggregate" "FAIL" "-" "exit=$rc_agg"
                fi
            else
                add_result "[3] 端到端小样本" "FAIL" "$((t1 - t0))s" \
                           "exit=$rc_e2e, 详见 $(basename "$LOG_DIR")/e2e.log"
            fi
        fi
    fi
fi

print_summary_and_exit
