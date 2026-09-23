#!/usr/bin/env bash
# job: group-specific AMP set analysis on the real results (CPU only, ~1-2 h on the laptop)
cd "$(dirname "$0")/.."
RES=/home/w24e/c_AMPs-prediction/amp_results
[ -d "$RES/results" ] || { echo "MISSING $RES/results"; exit 1; }
export SORT_MEM=30% TMPDIR=/home/w24e/0amp/tmp; mkdir -p "$TMPDIR"
bash amp_pipeline/group_specific_amps.sh "$RES" results/group_specific
echo; echo "== sizes"; du -sh results/group_specific/fasta 2>/dev/null; ls results/group_specific/*/ | head -60
