# 最近一轮同步回执（agent -> 分支）

- 时间：2026-09-23 06:45 UTC
- 分支：`arena/01a07992-c-amps-prediction`
- 本轮纳入的**本机侧**提交（本机 -> 助手 ✅）：
  - 5348378 local: auto LAPTOP-R77M5D6M 2026-09-23 11:42:05
  - 11c639d check: accepted - local checks passed, loop closed
  - 3ce6873 check: round 3 passed
  - 774ac07 check: request round 3 (awaiting local check)
  - caeb12a check: round 2 passed
  - 896b8d9 local: auto LAPTOP-R77M5D6M 2026-09-23 11:34:06
  - 101a193 check: round 2 passed
  - 54cde5d check: request round 2 (awaiting local check)
  - 8d4c65e check: round 1 failed
  - 96b52fb check: round 1 failed
  - 15c5e7b check: round 1 failed
  - ab77758 check: round 1 failed
  - c67a1c1 check: round 1 failed
  - 4fd3af7 check: round 1 failed
  - e479dc9 check: round 1 failed
  - 603fac5 check: round 1 failed
  - 035214f hardware: report from LAPTOP-R77M5D6M (20260923-110227)
  - 2d6fc31 check: round 1 failed
  - 31e69bc check: round 1 failed
  - 866c0ac auth.sh: use git's proxy for API calls, accept pasted credential URL, clearer errors
  - d3ac06c Linux git-sync: proxy.sh (WSL host-IP auto proxy, --install patches .bashrc) + auth.sh multi-account (--add/--accounts/--account/--unpin, per-clone pin like auth.ps1)
  - 8fabe52 check: request round 1 (awaiting local check)
  - ec800d6 Install git-sync skill v2.9.2 + Linux user-side twins (sync/push/auth/watch/doctor/hardware/bootstrap .sh, cron watcher, code/local_check.sh with GPU+3-model smoke test)
  - 96e373d Add METHODS_AMP_prediction.md: full results table and methods write-up for three-model AMP prediction
  - 97b6bca Fix: apply merged-table invalidation to import_bert_remote.sh itself (remove stray ibr.sh)
  - 3ede55e import_bert_remote: invalidate correct merged table (unique_with_proba.tsv) so BERT probs are actually re-merged
  - 2e9b10d Robust conda base detection (ignore conda plugin error lines on stdout)
  - 3632124 Add run_bert_remote.sh (standalone resumable BERT on another GPU box) and import_bert_remote.sh (merge remote BERT back into pipeline)
  - 2415ecd stage_local_bert_base.sh: assemble local bert-base-uncased (vocab/config/weights) from cache; bench uses it
  - a50926b bench_bert_amp2: absolute paths, find unique set in amp2_fasta_export, stage local vocab to avoid s3 timeout; extract defaults to sibling amp2_fasta_export
  - e5c3b67 Add extract_amp2_fasta.sh (per-group two-vote FASTA + global unique set) and bench_bert_amp2.sh (BERT timing on two-vote set)
  - f8f19ba BERT_CASCADE=skip: Keras-only mode (is_AMP2 = att&lstm both >0.5) for all cohorts; add is_AMP2/n_AMP2 columns; BERT rerun invalidates join
  - 61c482a cascade mode switch invalidates previous BERT output
  - 6ebd649 BERT_CASCADE=strict (default): BERT only where att&lstm both >0.5 for 3-vote-only use; bench reports both ratios
  - 9ae8147 BERT cascade: only run BERT where att/lstm has >=1 vote (identical final labels); GPU util sampling; bench reports cascade ratio + length distribution; fix NA vote bug; batch 512
  - d7bebd1 predict_bert_unique: per-batch progress every 10s, smaller default chunk
  - 2f19360 Fix UnicodeEncodeError under LC_ALL=C: force UTF-8 stdout for python predictors
  - cb8a712 Add high-throughput dedup pipeline for 33GB grouped catalog: run_unique_pipeline.sh (bench/full/resume), fast Keras+BERT predictors, verify script, docs
  - 1aee0ba Fix BERT: restore_finetuned_model compat with sklearn>=0.24; make bert_sklearn importable from any cwd via .pth + sys.path fallback
  - af9ac79 setup_envs.sh: install BERT python deps one by one with retries
  - 1e6e9ca setup_envs.sh: background torch download with live progress and stall detection
  - ac2d625 setup_envs.sh: loop torch wheel resume across mirrors until sha256 verifies
  - 6ad4051 setup_envs.sh: download torch wheel with resumable wget from CN mirrors, verify sha256, install locally
  - 777d9fe setup_envs.sh: install keras via conda with pip fallback, multi-index pip fallback; test_gpu.sh: filter NUMA noise
  - 7b723a0 setup_envs.sh: detect/cleanup broken env dirs, use absolute env python for pip
  - 36406e0 setup_envs.sh: prefetch large CUDA packages with resumable wget and retry conda/pip installs (mirror disconnects)
  - 6f9a79a Add conda env setup script, GPU self-test (GTX 1650) and install guide; auto-detect conda base in pipeline scripts
- 本轮助手提交：deliverable: 中文结果与方法文档 (md+docx) + md2docx.py; job.sh verifies files on the local machine
- 本轮改动文件：
   M bert_sklearn/data/__pycache__/__init__.cpython-36.pyc
   M bert_sklearn/data/__pycache__/data.cpython-36.pyc
   M bert_sklearn/data/__pycache__/utils.cpython-36.pyc
   M results/status/success_criteria.json
  ?? amp_pipeline/md2docx.py
  ?? code/job.sh
  ?? deliverable/

> 完整历史：`git log --oneline -10`；本机 `.\sync.ps1` 之后即可看到本文件。
