#!/usr/bin/env bash
# local_check.sh (template) - what watch.sh runs on a Linux machine when the agent requests a check.
# Exit 0 = passed. Output goes to results/status/check_rN_<stamp>.txt and is pushed back.
# Edit freely: this file belongs to the repo; the installer only creates it when missing.
set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$PATH:/usr/lib/wsl/lib:/usr/local/cuda/bin:$HOME/miniconda3/bin:$HOME/miniconda3/condabin"   # cron PATH is minimal
fail=0
echo "== host: $(hostname)  $(date '+%F %T')  repo: $PWD"
echo "== 1. gate"; bash code/check_all.sh && echo "OK: gate" || { echo "FAIL: gate"; fail=1; }
echo "== 2. GPU"; command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || echo "WARN: no nvidia-smi"
# ---- job hook: the agent drops a command into code/job.sh; it runs HERE (real machine) and the
#      log is pushed back in results/jobs/. Non-zero exit fails the round. Remove the file to disable.
if [ -f code/job.sh ]; then
  echo "== 3. job: code/job.sh"; mkdir -p results/jobs; log="results/jobs/job_$(date '+%Y%m%d-%H%M%S').log"
  if timeout 6h bash code/job.sh > "$log" 2>&1; then echo "OK: job"; else echo "FAIL: job"; fail=1; fi; tail -30 "$log"
fi
echo "== result: $([ $fail = 0 ] && echo PASSED || echo FAILED)"; exit $fail
