# -*- coding: utf-8 -*-
# prediction_bert.py — 用 BERT 模型对 sORF 序列打分 (概率)
# usage: python prediction_bert.py sequences.fa proba.tsv
#   (可选第 3 个参数指定 bert_model 名/路径, 如
#       python prediction_bert.py seq.fa out.tsv 'bert-base-uncased'
#       python prediction_bert.py seq.fa out.tsv /path/to/bert-base-uncased)

from os import environ
from sys import argv
import os, sys, glob

# CPU 多核线程数优化 (例如在 HPC 64/96 核上加速)
import torch
omp_threads = os.environ.get("OMP_NUM_THREADS", "")
if omp_threads and omp_threads.isdigit():
    torch.set_num_threads(int(omp_threads))

# 可控开关: auto=自动检测 GPU, 1/true=强制 GPU, 0/false=强制 CPU
raw_cuda = os.environ.get("BERT_USE_CUDA", "auto").strip().lower()
if raw_cuda in ("1", "true", "yes"):
    USE_CUDA = True
elif raw_cuda in ("0", "false", "no"):
    USE_CUDA = False
else:
    USE_CUDA = torch.cuda.is_available()

seq_path = argv[1]
if len(argv) > 3:
    explicit_bert_model = argv[3]
else:
    explicit_bert_model = None

from bert_sklearn import load_model
import numpy as np

# ---------- 先读模型 ----------
model = load_model("../Models/bert.bin")

# ---------- tokenizer 解析 ----------
def resolve_tokenizer(model):
    """尽力让 model.tokenizer 可用; 返回 (tokenizer, 说明)。"""
    recorded = getattr(model, "bert_model", None)

    candidates = []
    if explicit_bert_model:
        candidates.append(explicit_bert_model)
    if recorded:
        candidates.append(recorded)
    cands_more = [
        "bert-base-uncased",
        "bert-base-cased",
        "bert-base-multilingual-uncased",
        os.path.join("..", "Models", "bert-base-uncased"),
        os.path.join("Models", "bert-base-uncased"),
        os.path.join("..", "Models", "bert-base-uncased-vocab.txt"),
        os.path.expanduser("~/.cache/torch/pretrained_bert/bert-base-uncased-vocab.txt"),
        os.path.expanduser("~/.cache/torch/pretrained_bert/bert-base-cased-vocab.txt"),
    ]
    for p in cands_more:
        for g in glob.glob(p) + glob.glob(os.path.join(p, "vocab.txt")):
            if g not in candidates:
                candidates.append(g)

    tokenizer = None
    last_err = None
    for cand in candidates:
        if not cand:
            continue
        try:
            from bert_sklearn.model.pytorch_pretrained.tokenization import BertTokenizer
            do_lower = ("cased" not in cand)
            tokenizer = BertTokenizer.from_pretrained(cand, do_lower_case=do_lower)
            if tokenizer is not None:
                return tokenizer, cand
        except Exception as e:  # noqa
            last_err = e
            continue
    return None, (last_err if last_err else "未知原因")


tok, how = resolve_tokenizer(model)
if tok is None:
    sys.stderr.write("\n" + "="*78 + "\n")
    sys.stderr.write("[BERT tokenizer 无法解析] 无法加载 BERT 的 vocab.txt, 因此无法打分。\n")
    sys.stderr.write("="*78 + "\n")
    sys.exit(2)

model.tokenizer = tok
print("[BERT] tokenizer 已就绪, 来源: %s" % how)

# ---------- 流式读取 FASTA 并分块预测 (低内存占用, 防止 OOM 崩溃) ----------
chunk_size = int(os.environ.get("BERT_CHUNK_SIZE", "50000"))
print("[BERT] 开始流式预测 (use_cuda=%s, 分块大小: %d)..." % (USE_CUDA, chunk_size))

def stream_fasta_tokens(filepath, chunk_size=50000):
    seq_chunk = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('>'):
                continue
            seq_chunk.append(" ".join(list(line)))
            if len(seq_chunk) >= chunk_size:
                yield np.array(seq_chunk)
                seq_chunk = []
        if seq_chunk:
            yield np.array(seq_chunk)

total = 0
with open(argv[2], 'w') as out_f:
    for idx, chunk_data in enumerate(stream_fasta_tokens(seq_path, chunk_size)):
        y_prob = model.predict_proba(chunk_data, use_cuda=USE_CUDA)
        y_prob = y_prob[:, 1]
        for p in y_prob:
            out_f.write("%.8f\n" % p)
        total += len(y_prob)
        print("  [BERT 进度] 已预测 %d 条序列" % total, flush=True)

print("[BERT] 完成 -> %s (共 %d 条)" % (argv[2], total))
