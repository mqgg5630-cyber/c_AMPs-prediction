#!/bin/bash
# ==============================================================================
# run_pipeline_all_groups.sh —— 遍历「分组总 FASTA 文件夹」逐个跑三模型预测
#
# 输入: 由 build_grouped_sorf_fasta.py 生成的目录 (默认 sorf_grouped_catalog)
#       该目录下每个 Cohort*_*文件夹 里的 *.fa 都是一个分组。
#       注意: 会跳过 sORF_All_Total.fa (总库可选), 见下方 SKIP_TOTAL。
# 输出: <results_root>/<Cohort文件夹>/<分组名>/final_prediction.txt
#
# 用法:
#   bash run_pipeline_all_groups.sh [grouped_dir] [results_root] [project_dir] [env_tf] [env_bert]
# 示例:
#   bash run_pipeline_all_groups.sh sorf_grouped_catalog amp_results
#
# 并行: 默认逐个跑。若想并行, 把每个 python 预测放后台+wait,
#        但注意 Attention/LSTM 依序写同一 model 文件是安全的(只读加载)。
#        这里保持简单串行; 如需并行请自行用 xargs -P。
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUPED_DIR="${1:-sorf_grouped_catalog}"
RESULTS_ROOT="${2:-amp_results}"
PROJECT_DIR="${3:-$(dirname "$SCRIPT_DIR")}"
ENV_TF="${4:-/home/w26/miniconda3/envs/camps-tf114}"
ENV_BERT="${5:-/home/w26/miniconda3/envs/py36}"

SKIP_TOTAL="${SKIP_TOTAL:-1}"    # 1 = 跳过 sORF_All_Total.fa; 0 = 也跑

# ---- 自动定位分组目录 ----
# 用户可能把 sorf_grouped_catalog 放在仓库根目录、仓库上一级、或仓库父目录, 逐级探测。
resolve_grouped_dir() {
    local cand="$1"
    if [ -d "$cand" ]; then echo "$cand"; return; fi
    # 仓库内
    local in_repo="$PROJECT_DIR/$(basename "$cand")"
    if [ -d "$in_repo" ]; then echo "$in_repo"; return; fi
    # 仓库上一级 (用户当前情况: .../c_AMPs-prediction-master/sorf_grouped_catalog)
    local up_one="$PROJECT_DIR/../$(basename "$cand")"
    if [ -d "$up_one" ]; then echo "$up_one"; return; fi
    # 仓库父目录的上一级
    local up_two="$PROJECT_DIR/../../$(basename "$cand")"
    if [ -d "$up_two" ]; then echo "$up_two"; return; fi
    echo ""
}

GROUPED_DIR="$(resolve_grouped_dir "$GROUPED_DIR")"
if [ -z "$GROUPED_DIR" ]; then
    echo "错误: 找不到分组目录 (自动探测了仓库内/上一级/上两级均失败)。"
    echo "请显式指定: bash amp_pipeline/run_pipeline_all_groups.sh <绝对路径/sorf_grouped_catalog>"
    exit 1
fi

echo "=================================================="
echo " 分组 FASTA 批量预测"
echo "=================================================="
echo " 分组目录 : $GROUPED_DIR"
echo " 结果目录 : $RESULTS_ROOT"
echo " 项目目录 : $PROJECT_DIR"
echo "=================================================="
# 校验结果目录里是否真的有分组 fa
found=$(find "$GROUPED_DIR" -maxdepth 2 -name '*.fa' | wc -l)
echo " 分组 FASTA 文件数: $found"
if [ "$found" -eq 0 ]; then
    echo " [警告] 未在该目录找到任何 .fa 文件, 请确认目录正确。"
fi

mkdir -p "$RESULTS_ROOT"

echo "=================================================="
echo " 分组 FASTA 批量预测"
echo "=================================================="
echo " 分组目录 : $GROUPED_DIR"
echo " 结果目录 : $RESULTS_ROOT"
echo " 项目目录 : $PROJECT_DIR"
echo "=================================================="

count=0
# find 每个 cohort 文件夹下的所有 *.fa
shopt -s nullglob
for dir in "$GROUPED_DIR"/*/; do
    [ -d "$dir" ] || continue
    cohort=$(basename "$dir")
    for fa in "$dir"/*.fa; do
        [ -f "$fa" ] || continue
        base=$(basename "$fa" .fa)
        # 跳过总库
        if [ "$SKIP_TOTAL" = "1" ] && [ "$base" = "sORF_All_Total" ]; then
            echo "  [跳过总库] $fa"
            continue
        fi
        count=$((count+1))
        out="$RESULTS_ROOT/$cohort/$base"
        echo ""
        echo "########## 处理 $fa ##########"
        bash "$SCRIPT_DIR/run_pipeline_one.sh" \
            "$fa" "$out" "$PROJECT_DIR" "$ENV_TF" "$ENV_BERT" || {
            echo "  [警告] 该分组处理失败或为空, 已跳过: $fa (bash 退出码 $?)"
        }
        # 若分组为空, run_pipeline_one.sh 会 exit 0 且不产生最终结果, 该目录会被 aggregator 跳过
    done
done
shopt -u nullglob

echo ""
echo "=================================================="
echo " 批量预测完成! 共处理 $count 个分组文件"
echo " 结果汇总建议运行:"
echo "   python3 amp_pipeline/aggregate_amp_results.py $RESULTS_ROOT"
echo "=================================================="
