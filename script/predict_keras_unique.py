# -*- coding: utf-8 -*-
"""
predict_keras_unique.py —— Attention + LSTM 两个 Keras 模型一次性流式预测 (高吞吐版)

与 prediction_attention.py / prediction_lstm.py 的区别:
  * 直接在 Python 内把氨基酸编码成 (N, 300) 矩阵, 不再经过 format.pl 生成几百 GB 的 CSV 中间文件
  * 两个模型共用同一份编码, 只读一遍输入
  * 支持断点续跑: 输出文件已有 k 行, 则自动跳过前 k 条输入
  * 编码规则与 format.pl 完全一致: 大写; 20 种标准氨基酸 -> 1..20; 左侧补 0 至 300 列;
    含非标准字母 (B/J/O/U/X/Z 或其它) 的序列 format.pl 会直接丢弃, 这里输出 NA\tNA 占位

用法:
    python predict_keras_unique.py <seqs.txt|fasta> <out.tsv> [total_seqs]
输入:  每行一条序列 (或 FASTA, '>' 行会被忽略)
输出:  每条输入一行  "att_prob\tlstm_prob"  (非标准序列为 "NA\tNA")
环境变量:
    TF_PREDICT_BATCH_SIZE  (默认 1024)   TF_CHUNK_SIZE (默认 50000)
"""
import os
import sys
import time

import numpy as np

# 防止 LC_ALL=C 等环境下 stdout 为 ASCII 导致中文打印崩溃
for _st in (sys.stdout, sys.stderr):
    try:
        _st.reconfigure(encoding="utf-8")   # py3.7+
    except AttributeError:
        import io
        if getattr(_st, "encoding", "").lower() not in ("utf-8", "utf8"):
            if _st is sys.stdout:
                sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)
            else:
                sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", line_buffering=True)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)

if len(sys.argv) < 3:
    sys.exit("用法: python predict_keras_unique.py <seqs.txt> <out.tsv> [total_seqs]")
in_path, out_path = sys.argv[1], sys.argv[2]
total = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 0

batch_size = int(os.environ.get("TF_PREDICT_BATCH_SIZE", "1024"))
chunk_size = int(os.environ.get("TF_CHUNK_SIZE", "50000"))
MAXLEN = 300
AA = "ACDEFGHIKLMNPQRSTVWY"

# ---------- 编码表 ----------
_code = np.zeros(256, dtype=np.float32)
_valid = np.zeros(256, dtype=bool)
for i, c in enumerate(AA):
    _code[ord(c)] = i + 1
    _valid[ord(c)] = True

n_trunc = 0


def encode(seqs):
    """seqs: list[str] (已大写). 返回 (X float32 [n,300], ok bool[n])."""
    global n_trunc
    X = np.zeros((len(seqs), MAXLEN), dtype=np.float32)
    ok = np.ones(len(seqs), dtype=bool)
    for i, s in enumerate(seqs):
        b = np.frombuffer(s.encode("ascii", "replace"), dtype=np.uint8)
        if b.size == 0 or not _valid[b].all():
            ok[i] = False
            continue
        if b.size > MAXLEN:
            b = b[:MAXLEN]
            n_trunc += 1
        X[i, MAXLEN - b.size:] = _code[b]
    return X, ok


def iter_seqs(path):
    with open(path, "r") as f:
        for line in f:
            if not line or line[0] == ">":
                continue
            s = line.strip().upper()
            if s:
                yield s


# ---------- 断点续跑 ----------
done = 0
if os.path.exists(out_path):
    with open(out_path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 22), b""):
            done += blk.count(b"\n")
    if done:
        print("[Keras] 断点续跑: 输出已有 %d 行, 跳过对应输入" % done, flush=True)

# ---------- 加载模型 (放在后面, 让参数错误尽早暴露) ----------
import tensorflow as tf  # noqa: E402
from keras.backend.tensorflow_backend import set_session  # noqa: E402
from keras.models import load_model  # noqa: E402
from Attention import Attention_layer  # noqa: E402

config = tf.ConfigProto()
config.gpu_options.allow_growth = True
set_session(tf.Session(config=config))

t0 = time.time()
att = load_model(os.path.join(PROJECT_DIR, "Models", "att.h5"),
                 custom_objects={"Attention_layer": Attention_layer})
lstm = load_model(os.path.join(PROJECT_DIR, "Models", "lstm.h5"))
print("[Keras] 模型加载完成 (%.1fs)  batch=%d chunk=%d" % (time.time() - t0, batch_size, chunk_size), flush=True)

# ---------- 主循环 ----------
processed = done
t_start = time.time()
n_bad = 0
chunk = []
out = open(out_path, "a")


def flush_chunk(chunk):
    global n_bad
    X, ok = encode(chunk)
    n = len(chunk)
    pa = np.full(n, np.nan, dtype=np.float32)
    pl = np.full(n, np.nan, dtype=np.float32)
    if ok.any():
        Xo = X[ok]
        pa[ok] = att.predict(Xo, batch_size=batch_size).reshape(-1)
        pl[ok] = lstm.predict(Xo, batch_size=batch_size).reshape(-1)
    n_bad += int((~ok).sum())
    lines = []
    for i in range(n):
        if ok[i]:
            lines.append("%.8f\t%.8f\n" % (pa[i], pl[i]))
        else:
            lines.append("NA\tNA\n")
    out.write("".join(lines))
    out.flush()


skipped = 0
last_report = time.time()
for s in iter_seqs(in_path):
    if skipped < done:
        skipped += 1
        continue
    chunk.append(s)
    if len(chunk) >= chunk_size:
        flush_chunk(chunk)
        processed += len(chunk)
        chunk = []
        now = time.time()
        if now - last_report >= 10:
            rate = (processed - done) / max(1e-6, now - t_start)
            msg = "  [Keras 进度] %d 条  %.0f 条/s" % (processed, rate)
            if total:
                eta = (total - processed) / max(rate, 1e-6)
                msg += "  剩余约 %.1f 小时 (%.1f%%)" % (eta / 3600, 100.0 * processed / total)
            print(msg, flush=True)
            last_report = now
if chunk:
    flush_chunk(chunk)
    processed += len(chunk)
out.close()

el = time.time() - t_start
print("[Keras] 完成 -> %s  本次 %d 条, 用时 %.1fs (%.0f 条/s), 非标准氨基酸序列 %d 条, 截断(>300) %d 条"
      % (out_path, processed - done, el, (processed - done) / max(el, 1e-6), n_bad, n_trunc), flush=True)
