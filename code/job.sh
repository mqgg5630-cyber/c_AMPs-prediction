#!/usr/bin/env bash
# job: group-specific AMP analysis v3 (exact-match level, zero mmseqs)
#   A' 跨队列一致性(超几何) B 深度校正下采样 D 长度分层 C k-mer 富集(chi2+BH)
# 复用 v1 已建好的 3500 万行索引 (results/group_specific_family/work)
cd "$(dirname "$0")/.."
RES=/home/w24e/c_AMPs-prediction/amp_results
export SORT_MEM=30% TMPDIR=/home/w24e/0amp/tmp THREADS=6
mkdir -p "$TMPDIR"
echo "== 复用索引: $(ls -la results/group_specific_family/work/all.tsv 2>/dev/null || echo 无)"
set -x
bash amp_pipeline/group_specific_analysis3.sh "$RES" results/group_specific_v3
rc=$?; set +x
[ -s results/group_specific_v3/SUMMARY.md ] || { echo "JOB FAILED: SUMMARY.md missing (rc=$rc)"; exit 1; }
echo "== 结果文件:"; ls results/group_specific_v3
exit $rc
