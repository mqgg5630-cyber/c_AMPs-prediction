#!/bin/bash
# ==============================================================================
# run_grouping_slurm.sh —— SLURM 提交脚本: 在 fat 大内存节点上跑 v2 分组
#
# 背景: 之前直接在登录节点跑被 OOM Killed, 因为脚本对所有 cohort 的"去重 seen 集合"
#       同时驻留内存 (可达几十 GB)。现在的 v2 脚本改为"逐 cohort 处理", 峰值内存大幅下降;
#       再配合本脚本的 fat 节点 500G 内存, 双保险。
#
# 用法:
#   sbatch run_grouping_slurm.sh
# 或用 bash 直接前台跑:  bash run_grouping_slurm.sh  (会忽略 #SBATCH, 在本机跑)
#
# 提交后:
#    看日志:   cat sorf_grouping_%j.out / sorf_grouping_%j.err
#    查状态:   squeue -u <你的用户名>
# ==============================================================================
#SBATCH -J sorf_grouping
#SBATCH -p fat1
#SBATCH -c 48
#SBATCH --mem=500G
#SBATCH -t 7-00:00:00
#SBATCH -o sorf_grouping_%j.out
#SBATCH -e sorf_grouping_%j.err

set -e

# ----- 按你的实际路径修改这几个变量 -----
SORF_DIR="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/sorf_output"
MAG_SAMPLE="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/MAG_Sample_Mapping.tsv"
META="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/Sample_Group_Mapping.tsv"
CATALOG="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/sorf_output/final_sORF_Catalog.unique.fa"
OUTDIR="/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/comparable_sorf_grouped_catalog"
# 自动定位 build_grouped_sorf_from_magfiles.py 路径 (兼容 sbatch 的 spool 临时目录与常规 bash 运行)
SCRIPT_NAME="build_grouped_sorf_from_magfiles.py"
PY_SCRIPT=""

# 依次检查可能的目录
CANDIDATE_DIRS=(
    "${SLURM_SUBMIT_DIR:-}"
    "${SLURM_SUBMIT_DIR:-}/amp_pipeline"
    "$(pwd)"
    "$(pwd)/amp_pipeline"
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null)/amp_pipeline"
    "/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/c_AMPs-prediction/amp_pipeline"
    "/mnt/hpc/home/25menglei/25wenshaohua/c_AMPs-prediction/amp_pipeline"
    "/mnt/hpc/home/25menglei/25wenshaohua/c_AMPs-prediction"
)

for dir in "${CANDIDATE_DIRS[@]}"; do
    if [ -n "$dir" ] && [ -f "$dir/$SCRIPT_NAME" ]; then
        PY_SCRIPT="$dir/$SCRIPT_NAME"
        break
    fi
done

if [ -z "$PY_SCRIPT" ] || [ ! -f "$PY_SCRIPT" ]; then
    echo "错误: 找不到 $SCRIPT_NAME !"
    echo "当前目录: $(pwd)"
    echo "SLURM_SUBMIT_DIR: ${SLURM_SUBMIT_DIR:-未设置}"
    exit 1
fi

# GPU 不需要, 但保留探测避免 CUDA 相关提示
export CUDA_VISIBLE_DEVICES=""

echo "=================================================="
echo " sorf 四队列分组 (SLURM) 开始 @ $(date '+%F %T')"
echo "=================================================="
echo " 节点     : $(hostname)"
echo " CPU 数   : ${SLURM_CPUS_PER_TASK:-1} / ${SLURM_CPUS_ON_NODE:-1}"
echo " 内存     : ${SLURM_MEM_PER_NODE:-未知}MB"
echo " 脚本路径 : $PY_SCRIPT"
echo " sorf-dir : $SORF_DIR"
echo " 输出     : $OUTDIR"
echo "=================================================="

# 正式跑
python3 "$PY_SCRIPT" \
    --sorf-dir    "$SORF_DIR" \
    --mag-sample  "$MAG_SAMPLE" \
    --meta        "$META" \
    --catalog     "$CATALOG" \
    --outdir      "$OUTDIR" \
    --copy-total

echo ""
echo "=================================================="
echo " 分组完成 @ $(date '+%F %T')"
echo " 结果目录: $OUTDIR"
echo " 清单    : $OUTDIR/group_manifest.tsv"
echo " 请用 rsync 把 $OUTDIR 整目录传回本地。"
echo "=================================================="
