#!/bin/bash
# ==============================================================================
# run_prediction_slurm.sh —— SLURM 提交脚本: 在 HPC 64/96 核大内存节点上全速跑三模型预测
#
# 优势:
#   * 数据直接读取 HPC 本地 `/mnt/hpc/home/.../comparable_sorf_grouped_catalog` (省去几百 GB 传输)
#   * 500G 内存保证几千万条向量矩阵加载不 OOM
#   * 64~96 CPU 核心通过 OpenMP / MKL / PyTorch 多线程并行加速
#   * BERT_EVAL_BATCH_SIZE=256 大批次向量化推理，吞吐量提升 10 倍以上
#
# 用法:
#   sbatch amp_pipeline/run_prediction_slurm.sh
#
# 查看状态:
#   squeue -u 25wenshaohua
#   tail -f amp_pred_*.out
# ==============================================================================
#SBATCH -J amp_predict
#SBATCH -p fat1
#SBATCH -c 96
#SBATCH --mem=500G
#SBATCH -t 7-00:00:00
#SBATCH -o amp_pred_%j.out
#SBATCH -e amp_pred_%j.err

set -e

# ----- 自动探测路径 -----
CANDIDATE_DIRS=(
    "${SLURM_SUBMIT_DIR:-}"
    "$(pwd)"
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null)"
    "/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/c_AMPs-prediction"
    "/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/c_AMPs-prediction"
    "/mnt/hpc/home/25menglei/25wenshaohua/c_AMPs-prediction"
)

REPO_DIR=""
for d in "${CANDIDATE_DIRS[@]}"; do
    if [ -n "$d" ] && [ -f "$d/amp_pipeline/run_pipeline_all_groups.sh" ]; then
        REPO_DIR="$d"
        break
    fi
done

if [ -z "$REPO_DIR" ]; then
    echo "错误: 找不到项目根目录!"
    exit 1
fi

cd "$REPO_DIR"

# 分组数据目录与结果输出目录
GROUPED_DIR="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/comparable_sorf_grouped_catalog"
RESULTS_ROOT="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/amp_results"

# conda 环境路径 (若环境在不同位置，可在此修改)
ENV_TF="${ENV_TF:-/mnt/hpc/home/25menglei/25wenshaohua/miniconda3/envs/camps-tf114}"
ENV_BERT="${ENV_BERT:-/mnt/hpc/home/25menglei/25wenshaohua/miniconda3/envs/py36}"

# 备选: 若环境在 ~/.conda/envs/ 或其他位置，自动搜寻
if [ ! -d "$ENV_TF" ]; then
    for cand in "$HOME/miniconda3/envs/camps-tf114" "$HOME/.conda/envs/camps-tf114" "/home/25wenshaohua/miniconda3/envs/camps-tf114"; do
        if [ -d "$cand" ]; then ENV_TF="$cand"; break; fi
    done
fi
if [ ! -d "$ENV_BERT" ]; then
    for cand in "$HOME/miniconda3/envs/py36" "$HOME/.conda/envs/py36" "/home/25wenshaohua/miniconda3/envs/py36"; do
        if [ -d "$cand" ]; then ENV_BERT="$cand"; break; fi
    done
fi

# 多核并行与 BERT 加速参数
CPUS="${SLURM_CPUS_PER_TASK:-64}"
export OMP_NUM_THREADS="$CPUS"
export MKL_NUM_THREADS="$CPUS"
export OPENBLAS_NUM_THREADS="$CPUS"
export VECLIB_MAXIMUM_THREADS="$CPUS"
export NUMEXPR_NUM_THREADS="$CPUS"

export BERT_EVAL_BATCH_SIZE=256
export BERT_NUM_WORKERS=0
export BERT_USE_CUDA=0

echo "=================================================="
echo " HPC 三模型批量预测作业 开始 @ $(date '+%F %T')"
echo "=================================================="
echo " 节点     : $(hostname)"
echo " CPU 核数 : $CPUS"
echo " 内存     : ${SLURM_MEM_PER_NODE:-未知}MB"
echo " 项目目录 : $REPO_DIR"
echo " 分组目录 : $GROUPED_DIR"
echo " 结果目录 : $RESULTS_ROOT"
echo " TF 环境  : $ENV_TF"
echo " BERT 环境: $ENV_BERT"
echo "=================================================="

# 1. 执行全部分组预测
bash "$REPO_DIR/amp_pipeline/run_pipeline_all_groups.sh" \
    "$GROUPED_DIR" "$RESULTS_ROOT" "$REPO_DIR" "$ENV_TF" "$ENV_BERT"

# 2. 汇总生成最终统计与大表
echo ""
echo "=================================================="
echo " 汇总全部分组预测结果 ..."
echo "=================================================="
python3 "$REPO_DIR/amp_pipeline/aggregate_amp_results.py" "$RESULTS_ROOT"

echo ""
echo "=================================================="
echo " 全部分组预测与汇总完成 @ $(date '+%F %T')"
echo " 汇总大表位于: $RESULTS_ROOT/amp_all_peptides.tsv"
echo " 阶段统计位于: $RESULTS_ROOT/amp_summary.tsv"
echo "=================================================="
