#!/usr/bin/env bash
# job: family-level group-specific AMP analysis; verifies its own outputs
cd "$(dirname "$0")/.."
RES=/home/w24e/c_AMPs-prediction/amp_results
export SORT_MEM=30% TMPDIR=/home/w24e/0amp/tmp THREADS=6; mkdir -p "$TMPDIR"
echo "== sORF name format (first 3 of one group):"; head -4 "$RES/results/Cohort2_Matched265_NCvsAD/Cohort2_Disease_AD/aggregated_results.tsv" | cut -f1
echo "== conda: $(conda info --base 2>/dev/null | grep -m1 '^/')  mmseqs on PATH: $(command -v mmseqs || echo none)"
set -x
bash amp_pipeline/group_specific_family.sh "$RES" results/group_specific_family
rc=$?; set +x
[ -s results/group_specific_family/SUMMARY.md ] || { echo "JOB FAILED: SUMMARY.md missing (rc=$rc)"; exit 1; }
du -sh results/group_specific_family/work 2>/dev/null; exit $rc
