#!/bin/bash
# ==============================================================================
# verify_unique_vs_original.sh —— 校验「快速路径」与「原始脚本」输出一致
#   原始: format.pl -> prediction_attention.py / prediction_lstm.py ; prediction_bert.py
#   快速: predict_keras_unique.py ; predict_bert_unique.py
# 用法: bash amp_pipeline/verify_unique_vs_original.sh [N=200]
# ==============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
N="${1:-200}"
CONDA_BASE="$(conda info --base 2>/dev/null | grep -m1 "^/" || true)"; [ -d "$CONDA_BASE" ] || CONDA_BASE="$HOME/miniconda3"
PY_TF="${ENV_TF:-$CONDA_BASE/envs/camps-tf114}/bin/python"
PY_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}/bin/python"
W="$PROJECT_DIR/test_run/verify"; mkdir -p "$W"
export TF_CPP_MIN_LOG_LEVEL=2

python3 "$SCRIPT_DIR/subset_fasta.py" "$PROJECT_DIR/Data/AMPs.fa" "$N" > "$W/in.fa"
grep -v '^>' "$W/in.fa" > "$W/in.txt"
echo "序列数: $(wc -l < "$W/in.txt")"

cd "$PROJECT_DIR/script"
echo "--- 原始 Attention/LSTM ---"
perl format.pl "$W/in.fa" none > "$W/in_300.txt"
"$PY_TF" prediction_attention.py "$W/in_300.txt" "$W/att_orig.tsv" 2>/dev/null | tail -1
"$PY_TF" prediction_lstm.py "$W/in_300.txt" "$W/lstm_orig.tsv" 2>/dev/null | tail -1
echo "--- 快速 Attention+LSTM ---"
rm -f "$W/keras_fast.tsv"; "$PY_TF" predict_keras_unique.py "$W/in.txt" "$W/keras_fast.tsv" 2>/dev/null | tail -1
echo "--- 原始 BERT (max_len=模型默认) ---"
"$PY_BERT" prediction_bert.py "$W/in.fa" "$W/bert_orig.tsv" 2>/dev/null | tail -1
echo "--- 快速 BERT (fp16, 分桶) ---"
rm -f "$W/bert_fast.tsv"; "$PY_BERT" predict_bert_unique.py "$W/in.txt" "$W/bert_fast.tsv" 2>/dev/null | tail -1
echo "--- 快速 BERT (fp32) ---"
rm -f "$W/bert_fast32.tsv"; BERT_FP16=0 "$PY_BERT" predict_bert_unique.py "$W/in.txt" "$W/bert_fast32.tsv" 2>/dev/null | tail -1

python3 - "$W" <<'PY'
import sys, os, numpy as np
w = sys.argv[1]
def col(p, c=0):
    out=[]
    for l in open(p):
        t=l.split()
        if not t: continue
        out.append(float('nan') if t[c]=="NA" else float(t[c]))
    return np.array(out)
ao, lo, bo = col(f"{w}/att_orig.tsv"), col(f"{w}/lstm_orig.tsv"), col(f"{w}/bert_orig.tsv")
af, lf = col(f"{w}/keras_fast.tsv",0), col(f"{w}/keras_fast.tsv",1)
bf, bf32 = col(f"{w}/bert_fast.tsv"), col(f"{w}/bert_fast32.tsv")
def rep(name, a, b):
    n=min(len(a),len(b)); a,b=a[:n],b[:n]
    d=np.abs(a-b); agree=np.mean((a>0.5)==(b>0.5))
    print(f"{name:22s} n={n:4d}  max|Δ|={np.nanmax(d):.6f}  mean|Δ|={np.nanmean(d):.6f}  阈值0.5判定一致率={agree*100:.2f}%")
rep("Attention 原始 vs 快", ao, af)
rep("LSTM      原始 vs 快", lo, lf)
rep("BERT 原始 vs 快(fp32)", bo, bf32)
rep("BERT 原始 vs 快(fp16)", bo, bf)
print("说明: Attention/LSTM 应完全一致 (Δ≈1e-7 级); BERT fp32 应一致 (Δ<1e-4), fp16 有 ~1e-3 级误差属正常。")
PY
