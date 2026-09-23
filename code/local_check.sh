#!/usr/bin/env bash
# local_check.sh - what watch.sh runs on THIS Linux machine when the agent requests a check.
# Exit 0 = passed. Output is captured to results/status/check_rN_<stamp>.txt and pushed back.
# Repo-specific checks for c_AMPs-prediction: gate + GPU + the three AMP models.
set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PY="$(command -v python3 || command -v python)"
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
if [ -f results/status/cancel_request.txt ]; then
  echo "== 6. job: CANCELLED (results/status/cancel_request.txt present) - skipping code/job.sh"
  echo "--- cancel reason ---"; head -5 results/status/cancel_request.txt; fail=1
elif [ -f code/job.sh ]; then
  echo "== 6. job: code/job.sh  (watchdog: stall>${JOB_STALL_MIN:-25}min, max ${JOB_MAX_HOURS:-6}h, progress pushed every ${JOB_PUSH_MIN:-15}min)"
  mkdir -p results/jobs; rm -f results/jobs/job_*.log
  JL="results/jobs/job_$(date '+%Y%m%d-%H%M%S').log"
  if [ -f code/job_watch.py ]; then
    JOB_STALL_MIN=${JOB_STALL_MIN:-25} JOB_MAX_HOURS=${JOB_MAX_HOURS:-6} JOB_PUSH_MIN=${JOB_PUSH_MIN:-15} \
      "$PY" code/job_watch.py --cmd "bash code/job.sh" --log "$JL" \
        --stall-min "${JOB_STALL_MIN:-25}" --max-hours "${JOB_MAX_HOURS:-6}" --push-every-min "${JOB_PUSH_MIN:-15}" 2>&1 | tail -n 200
    rc=${PIPESTATUS[0]}
  else
    timeout "${JOB_MAX_HOURS:-6}h" bash code/job.sh > "$JL" 2>&1; rc=$?
  fi
  if [ "$rc" = 0 ]; then echo "OK: job (exit 0)"; else echo "FAIL: job (exit $rc${rc:+ }$([ "$rc" = 90 ] && echo '=stalled, killed by watchdog')$([ "$rc" = 91 ] && echo '=timeout, killed by watchdog'))"; fail=1; fi
  echo "--- job log tail (full log pushed back: $JL) ---"; tail -n 60 "$JL" 2>/dev/null
fi
echo "== result: $([ $fail = 0 ] && echo PASSED || echo FAILED)"
exit $fail
