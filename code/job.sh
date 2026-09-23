#!/usr/bin/env bash
# job: family-level group-specific AMP analysis (mmseqs clustering + MAG-prevalence Fisher tests)
cd "$(dirname "$0")/.."
RES=/home/w24e/c_AMPs-prediction/amp_results
export SORT_MEM=30% TMPDIR=/home/w24e/0amp/tmp THREADS=6; mkdir -p "$TMPDIR"
echo "== sORF name format check (first 3 names of one group):"
head -4 "$RES/results/Cohort2_Matched265_NCvsAD/Cohort2_Disease_AD/aggregated_results.tsv" | cut -f1
bash amp_pipeline/group_specific_family.sh "$RES" results/group_specific_family
du -sh results/group_specific_family/work 2>/dev/null
