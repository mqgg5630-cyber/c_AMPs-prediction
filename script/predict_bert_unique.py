# -*- coding: utf-8 -*-
"""
predict_bert_unique.py —— BERT 高吞吐流式预测 (GTX 1650 / 4GB 显存适配)

与 prediction_bert.py 的区别:
  * 自己做 tokenize: 序列每个氨基酸字母是一个 token, 直接查 vocab, 绕过 BasicTokenizer/WordPiece 的 Python 循环
    (原实现每条序列都要跑正则+wordpiece, CPU 成为瓶颈, GPU 利用率 < 20%)
  * 按长度排序后分桶 (bucketing): 每个 batch 只 pad 到该 batch 内最长序列, 而不是固定 128/300,
    sORF 平均 30 AA, 计算量减少 3~5 倍
  * 序列长度上限 BERT_MAX_SEQ_LENGTH (默认 66 = 64 AA + [CLS][SEP]); 更长的序列截断 (与原实现一致)
  * 大 batch 一次性拷贝到 GPU; 支持 fp16 (BERT_FP16=1, Turing 有 tensor core, 提速 ~2 倍)
  * 断点续跑: 输出文件已有 k 行则跳过前 k 条

用法:
    python predict_bert_unique.py <seqs.txt|fasta> <out.tsv> [total_seqs]
输出: 每条输入一行 bert_prob
环境变量:
    BERT_EVAL_BATCH_SIZE (默认 256)  BERT_MAX_SEQ_LENGTH (默认 66)  BERT_CHUNK_SIZE (默认 100000)
    BERT_FP16 (默认 1)  BERT_USE_CUDA (auto/1/0)
"""
import os
import sys
import time

import numpy as np
import torch

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

from bert_sklearn import load_model  # noqa: E402
from bert_sklearn.model.pytorch_pretrained.tokenization import BertTokenizer  # noqa: E402

if len(sys.argv) < 3:
    sys.exit("用法: python predict_bert_unique.py <seqs.txt> <out.tsv> [total_seqs]")
in_path, out_path = sys.argv[1], sys.argv[2]
total = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 0

batch_size = int(os.environ.get("BERT_EVAL_BATCH_SIZE", "256"))
max_len = int(os.environ.get("BERT_MAX_SEQ_LENGTH", "66"))
chunk_size = int(os.environ.get("BERT_CHUNK_SIZE", "100000"))
use_fp16 = os.environ.get("BERT_FP16", "1").strip().lower() in ("1", "true", "yes")
raw_cuda = os.environ.get("BERT_USE_CUDA", "auto").strip().lower()
if raw_cuda in ("1", "true", "yes"):
    use_cuda = True
elif raw_cuda in ("0", "false", "no"):
    use_cuda = False
else:
    use_cuda = torch.cuda.is_available()
device = torch.device("cuda" if use_cuda else "cpu")
if not use_cuda:
    use_fp16 = False

# ---------- 模型 ----------
t0 = time.time()
clf = load_model(os.path.join(PROJECT_DIR, "Models", "bert.bin"))
model = clf.model
model.to(device).eval()
if use_fp16:
    model.half()
print("[BERT] 模型加载 %.1fs  device=%s fp16=%s batch=%d max_len=%d" %
      (time.time() - t0, device, use_fp16, batch_size, max_len), flush=True)

# ---------- 词表 (与训练时一致: uncased 词表, 单字母小写) ----------
tok = getattr(clf, "tokenizer", None)
if tok is None:
    for cand in ("bert-base-uncased",
                 os.path.join(PROJECT_DIR, "Models", "bert-base-uncased"),
                 os.path.expanduser("~/.pytorch_pretrained_bert")):
        try:
            tok = BertTokenizer.from_pretrained(cand, do_lower_case=True)
            if tok is not None:
                break
        except Exception:
            continue
if tok is None:
    sys.exit("[BERT] 无法加载 vocab, 请先联网跑一次 prediction_bert.py 或把 vocab.txt 放到 Models/bert-base-uncased/")
vocab = tok.vocab
CLS, SEP, PAD, UNK = vocab["[CLS]"], vocab["[SEP]"], vocab["[PAD]"], vocab["[UNK]"]
# 26 个字母 -> id (原 pipeline: 序列被拆成 "a c d e ..." 再 lower + wordpiece, 单字母都在词表中)
letter_id = np.full(256, UNK, dtype=np.int64)
for c in "abcdefghijklmnopqrstuvwxyz":
    letter_id[ord(c)] = vocab.get(c, UNK)
    letter_id[ord(c.upper())] = vocab.get(c, UNK)

body_max = max_len - 2


def iter_seqs(path):
    with open(path, "r") as f:
        for line in f:
            if not line or line[0] == ">":
                continue
            s = line.strip()
            if s:
                yield s


# ---------- 断点续跑 ----------
done = 0
if os.path.exists(out_path):
    with open(out_path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 22), b""):
            done += blk.count(b"\n")
    if done:
        print("[BERT] 断点续跑: 输出已有 %d 行, 跳过对应输入" % done, flush=True)


@torch.no_grad()
def predict_chunk(seqs):
    """seqs: list[str]; 返回 np.float32 [n] 的 AMP 概率 (按输入顺序)."""
    n = len(seqs)
    ids_list = []
    for s in seqs:
        b = np.frombuffer(s.encode("ascii", "replace"), dtype=np.uint8)[:body_max]
        ids_list.append(letter_id[b])
    lens = np.fromiter((len(x) + 2 for x in ids_list), dtype=np.int64, count=n)
    order = np.argsort(lens, kind="stable")
    probs = np.empty(n, dtype=np.float32)
    for st in range(0, n, batch_size):
        idx = order[st:st + batch_size]
        L = int(lens[idx].max())
        input_ids = np.full((len(idx), L), PAD, dtype=np.int64)
        mask = np.zeros((len(idx), L), dtype=np.int64)
        for r, j in enumerate(idx):
            body = ids_list[j]
            m = len(body) + 2
            input_ids[r, 0] = CLS
            input_ids[r, 1:m - 1] = body
            input_ids[r, m - 1] = SEP
            mask[r, :m] = 1
        input_ids_t = torch.from_numpy(input_ids).to(device, non_blocking=True)
        mask_t = torch.from_numpy(mask).to(device, non_blocking=True)
        seg_t = torch.zeros_like(input_ids_t)
        logits = model(input_ids_t, seg_t, mask_t)
        p = torch.softmax(logits.float(), dim=-1)[:, 1]
        probs[idx] = p.cpu().numpy()
    return probs


processed = done
skipped = 0
chunk = []
t_start = time.time()
last_report = t_start
out = open(out_path, "a")


def flush(chunk):
    p = predict_chunk(chunk)
    out.write("".join("%.8f\n" % v for v in p))
    out.flush()


for s in iter_seqs(in_path):
    if skipped < done:
        skipped += 1
        continue
    chunk.append(s)
    if len(chunk) >= chunk_size:
        flush(chunk)
        processed += len(chunk)
        chunk = []
        now = time.time()
        if now - last_report >= 10:
            rate = (processed - done) / max(1e-6, now - t_start)
            msg = "  [BERT 进度] %d 条  %.0f 条/s" % (processed, rate)
            if total:
                eta = (total - processed) / max(rate, 1e-6)
                msg += "  剩余约 %.1f 小时 (%.1f%%)" % (eta / 3600, 100.0 * processed / total)
            if use_cuda:
                msg += "  显存峰值 %.0f MB" % (torch.cuda.max_memory_allocated() / 1e6)
            print(msg, flush=True)
            last_report = now
if chunk:
    flush(chunk)
    processed += len(chunk)
out.close()
el = time.time() - t_start
print("[BERT] 完成 -> %s  本次 %d 条, 用时 %.1fs (%.0f 条/s)" %
      (out_path, processed - done, el, (processed - done) / max(el, 1e-6)), flush=True)
