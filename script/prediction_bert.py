# -*- coding: utf-8 -*-
# prediction_bert.py — 用 BERT 模型对 sORF 序列打分 (概率)
# usage: python prediction_bert.py sequences.fa proba.tsv
#   (可选第 3 个参数指定 bert_model 名/路径, 如
#       python prediction_bert.py seq.fa out.tsv 'bert-base-uncased'
#       python prediction_bert.py seq.fa out.tsv /path/to/bert-base-uncased)
#
# 修复说明:
#   * 原版 load_model("../Models/bert.bin") 后 tokenizer 为 None, 因为
#     BertTokenizer.from_pretrained(bert_model) 在本地/离线环境下找不到 vocab.txt, 返回 None,
#     于是 predict_proba 报 "NoneType object has no attribute 'tokenize'"。
#   * 本脚本在加载模型后【主动解析 tokenizer】: 依次尝试
#       (1) 模型参数里记录的 bert_model
#       (2) 显式第 3 个参数
#       (3) 常见本地缓存/目录: Models/bert-base-uncased, Models/bert-base-uncased-vocab.txt,
#           ~/.cache/torch/pretrained_bert/bert-base-uncased-vocab.txt 等
#       若仍失败, 打印清晰的解决指引并退出(而非静默出错)。

from os import environ
from sys import argv
import os, sys, glob

# 可控开关: -1=自动, 否则固定用 CPU/GPU
environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
USE_CUDA = os.environ.get("BERT_USE_CUDA", "0").lower() in ("1", "true", "yes")

# CPU 多核线程数优化 (例如在 HPC 64/96 核上加速)
import torch
omp_threads = os.environ.get("OMP_NUM_THREADS", "")
if omp_threads and omp_threads.isdigit():
    torch.set_num_threads(int(omp_threads))

seq_path = argv[1]
if len(argv) > 3:
    explicit_bert_model = argv[3]
else:
    explicit_bert_model = None

from bert_sklearn import load_model
import numpy as np
import pandas as pd

# ---------- 先读模型(会打印 "Loading model from ../Models/bert.bin...") ----------
model = load_model("../Models/bert.bin")

# ---------- tokenizer 解析 ----------
def resolve_tokenizer(model):
    """尽力让 model.tokenizer 可用; 返回 (tokenizer, 说明)。"""
    # 模型参数里记录的 bert_model
    recorded = getattr(model, "bert_model", None)

    candidates = []
    if explicit_bert_model:
        candidates.append(explicit_bert_model)
    if recorded:
        candidates.append(recorded)
    # 常见本地名字/路径
    cands_more = [
        "bert-base-uncased",
        "bert-base-cased",
        "bert-base-multilingual-uncased",
        os.path.join("..", "Models", "bert-base-uncased"),
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
    sys.stderr.write("  尝试过的候选: " + ", ".join([repr(x) for x in (explicit_bert_model, getattr(model,'bert_model',None))]) + " ...\n")
    sys.stderr.write("  → 请做以下任一操作:\n")
    sys.stderr.write("    1) 用能上网的机器下载 BERT vocab.txt 放到 Models/ 下:\n")
    sys.stderr.write("       https://huggingface.co/bert-base-uncased/resolve/main/vocab.txt\n")
    sys.stderr.write("       然后放到: ../Models/bert-base-uncased/vocab.txt (或 ../Models/bert-base-uncased-vocab.txt)\n")
    sys.stderr.write("    2) 或指定模型名/路径作为第 3 个参数:\n")
    sys.stderr.write("       python prediction_bert.py seq.fa out.tsv '../Models/bert-base-uncased'\n")
    sys.stderr.write("    3) 若你知道训练时用的 bert_model, 把它作为第 3 个参数传入。\n")
    sys.stderr.write("="*78 + "\n")
    sys.exit(2)

model.tokenizer = tok  # 显式挂上, 供 predict_proba 使用
print("[BERT] tokenizer 已就绪, 来源: %s" % how)

# ---------- 读序列并格式化 ----------
tmp = pd.read_csv(seq_path, sep="\t", header=None, names=["seq"], index_col=False).seq.values
seq_array = []
for eachseq in tmp:
    if ">" not in eachseq:
        # 每个氨基酸字符用空格隔开, 作为 BERT 的 token
        seq_array.append(" ".join(list(eachseq)))
seq_array = np.array(seq_array)

print("[BERT] 待预测序列数: %d  use_cuda=%s" % (len(seq_array), USE_CUDA))
y_prob = model.predict_proba(seq_array, use_cuda=USE_CUDA)
y_prob = y_prob[:, 1]
pd.DataFrame(y_prob).to_csv(argv[2], sep="\t", header=False, index=False)
print("[BERT] 完成 -> %s" % argv[2])
