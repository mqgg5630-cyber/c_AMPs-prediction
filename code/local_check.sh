#!/usr/bin/env bash
# local_check.sh - what watch.sh runs on THIS Linux machine when the agent requests a check.
# Exit 0 = passed. Output is captured to results/status/check_rN_<stamp>.txt and pushed back.
# Repo-specific checks for c_AMPs-prediction: gate + GPU + the three AMP models.
set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$PATH:/usr/lib/wsl/lib:/usr/local/cuda/bin:$HOME/miniconda3/bin:$HOME/miniconda3/condabin"   # cron has a minimal PATH
fail=0
echo "== host: $(hostname)  $(date '+%F %T')  repo: $PWD"
echo "== 1. gate"
if bash code/check_all.sh; then echo "OK: gate"; else echo "FAIL: gate"; fail=1; fi

echo "== 2. GPU"
if command -v nvidia-smi >/dev/null; then nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader; else echo "WARN: nvidia-smi not found"; fi

CONDA_BASE="$(conda info --base 2>/dev/null | grep -m1 '^/' || true)"; [ -d "$CONDA_BASE" ] || CONDA_BASE="$HOME/miniconda3"
ENV_TF="${ENV_TF:-$CONDA_BASE/envs/camps-tf114}"; ENV_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}"
echo "== 3. environments"
[ -x "$ENV_TF/bin/python" ]   && echo "OK: $ENV_TF"   || { echo "MISSING: $ENV_TF   (bash amp_pipeline/setup_envs.sh tf)";   fail=1; }
[ -x "$ENV_BERT/bin/python" ] && echo "OK: $ENV_BERT" || { echo "MISSING: $ENV_BERT (bash amp_pipeline/setup_envs.sh bert)"; fail=1; }

echo "== 4. models"
for m in Models/att.h5 Models/lstm.h5 Models/bert.bin; do [ -s "$m" ] && echo "OK: $m ($(du -h "$m" | cut -f1))" || { echo "MISSING: $m"; fail=1; }; done

echo "== 5. GPU + model smoke test (test_gpu.sh)"
if [ -f amp_pipeline/test_gpu.sh ] && [ -x "$ENV_TF/bin/python" ] && [ -x "$ENV_BERT/bin/python" ]; then
  if ENV_TF="$ENV_TF" ENV_BERT="$ENV_BERT" timeout 900 bash amp_pipeline/test_gpu.sh; then echo "OK: test_gpu.sh"; else echo "FAIL: test_gpu.sh"; fail=1; fi
else echo "SKIP: test_gpu.sh (envs missing)"; fi

# ---- optional job hook: agent can drop a command into code/job.sh; it runs here and its
#      output goes to results/jobs/. Non-zero exit fails the round. Delete the file to disable.
if [ -f code/job.sh ]; then
  echo "== 6. job: code/job.sh"; mkdir -p results/jobs
  if timeout 6h bash code/job.sh > "results/jobs/job_$(date '+%Y%m%d-%H%M%S').log" 2>&1; then echo "OK: job"; tail -20 results/jobs/job_*.log | tail -20; else echo "FAIL: job (see results/jobs/)"; tail -20 results/jobs/*.log | tail -20; fail=1; fi
fi
echo "== result: $([ $fail = 0 ] && echo PASSED || echo FAILED)"
exit $fail
