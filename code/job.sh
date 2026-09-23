#!/usr/bin/env bash
# job: group-specific AMP analysis v2
#   A 压缩比曲线(标定短肽聚类阈值) B 最近邻同一性(判断“特异”是否只是菌株变异) C 家族层面重叠/核心家族 D 特征对比
# 复用 v1 已建好的 3500 万行索引 (results/group_specific_family/work) 以省时间
cd "$(dirname "$0")/.."
RES=/home/w24e/c_AMPs-prediction/amp_results
export SORT_MEM=30% TMPDIR=/home/w24e/0amp/tmp THREADS=6 SAMPLE=200000 FULL_ID=0.7
mkdir -p "$TMPDIR"
echo "== mmseqs: $(command -v mmseqs || echo "$PWD/tools/mmseqs/bin/mmseqs")"
echo "== 复用索引: $(ls -la results/group_specific_family/work/all.tsv 2>/dev/null || echo 无)"
# round 9 的 A(采样切碎 FASTA)/B(max-seqs 截断)产物无效, round 10 重跑 A/B; work/ 索引保留复用
rm -f results/group_specific_family2/compression_curve.tsv results/group_specific_family2/nn_identity_dist.tsv results/group_specific_family2/nn_identity_summary.tsv
set -x
bash amp_pipeline/group_specific_analysis2.sh "$RES" results/group_specific_family2
rc=$?; set +x
[ -s results/group_specific_family2/SUMMARY.md ] || { echo "JOB FAILED: SUMMARY.md missing (rc=$rc)"; exit 1; }
echo "== 结果文件:"; ls results/group_specific_family2
exit $rc
