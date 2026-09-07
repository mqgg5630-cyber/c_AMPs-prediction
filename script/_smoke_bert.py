#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
_smoke_bert.py —— BERT 模型 (Models/bert.bin) 的独立自检 (camps-bert 环境里跑)

用法:
    python _smoke_bert.py [n_seq]

必须 **cd 到 script/ 目录** 再跑, 因为 prediction_bert.py 里写的是相对路径
'../Models/bert.bin' / '../Models/bert-base-uncased'。

退出码: 0 = 通过, 1 = 失败, 2 = 跳过 (bert.bin 或 vocab.txt 缺失)
"""
from __future__ import print_function

import glob
import os
import sys
import time
import traceback

N = int(sys.argv[1]) if len(sys.argv) > 1 else 4

HERE = os.path.dirname(os.path.abspath(__file__))      # .../script
PROJECT = os.path.dirname(HERE)                        # .../c_AMPs-prediction
MODELS = os.path.join(PROJECT, "Models")
sys.path.insert(0, HERE)
os.chdir(HERE)

# 与 prediction_bert.py 完全一致的设备策略
raw_cuda = os.environ.get("BERT_USE_CUDA", "auto").strip().lower()
if raw_cuda in ("1", "true", "yes"):
    USE_CUDA = True
elif raw_cuda in ("0", "false", "no"):
    USE_CUDA = False
else:
    USE_CUDA = None          # 等到 import torch 之后再探测


def banner(t):
    print("\n" + "-" * 66)
    print(" " + t)
    print("-" * 66)
    sys.stdout.flush()


def env_report():
    import numpy as np
    import sklearn
    import torch
    print("[env] python     %s" % sys.version.split()[0])
    print("[env] torch      %s (built with cuda %s)" % (torch.__version__, torch.version.cuda))
    print("[env] numpy      %s" % np.__version__)
    print("[env] sklearn    %s" % sklearn.__version__)
    try:
        import bert_sklearn
        print("[env] bert_sklearn %s @ %s" % (bert_sklearn.__version__,
                                              os.path.dirname(bert_sklearn.__file__)))
    except Exception as e:
        print("[env] bert_sklearn 导入失败: %r" % (e,))
        raise
    print("[env] torch.cuda.is_available() = %s" % torch.cuda.is_available())
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            cap = torch.cuda.get_device_capability(i)
            print("[env]   GPU%d = %s (sm_%d%d, %.1f GB)" % (
                i, torch.cuda.get_device_name(i), cap[0], cap[1],
                torch.cuda.get_device_properties(i).total_memory / 1024 ** 3))
    print("[env] CUDA_VISIBLE_DEVICES = %r" % os.environ.get("CUDA_VISIBLE_DEVICES", "<unset>"))
    print("[env] BERT_MAX_SEQ_LENGTH  = %r" % os.environ.get("BERT_MAX_SEQ_LENGTH", "<unset>"))
    print("[env] BERT_EVAL_BATCH_SIZE = %r" % os.environ.get("BERT_EVAL_BATCH_SIZE", "<unset>"))
    sys.stdout.flush()
    return torch


def find_vocab():
    """返回 (vocab 路径或 None, 说明)。候选顺序与 prediction_bert.py 保持一致。"""
    cands = [
        os.path.join(MODELS, "bert-base-uncased", "vocab.txt"),
        os.path.join(MODELS, "bert-base-uncased-vocab.txt"),
        os.path.expanduser("~/.cache/torch/pretrained_bert/bert-base-uncased-vocab.txt"),
        os.path.join(MODELS, "bert-base-uncased"),
        "bert-base-uncased",
    ]
    for g in glob.glob(os.path.join(PROJECT, "Models", "*vocab*.txt")):
        if g not in cands:
            cands.append(g)
    for c in cands:
        if os.path.isfile(c) and c.endswith(".txt"):
            return c, c
        if os.path.isdir(c) and os.path.isfile(os.path.join(c, "vocab.txt")):
            return c, os.path.join(c, "vocab.txt")
    return None, "已尝试: " + ", ".join(cands)


def main():
    banner("BERT 环境自检")
    import torch
    env_report()

    global USE_CUDA
    if USE_CUDA is None:
        USE_CUDA = torch.cuda.is_available()
    print("\n[env] 本次自检 use_cuda = %s (BERT_USE_CUDA=%r)" % (USE_CUDA, raw_cuda))

    bert_bin = os.path.join(MODELS, "bert.bin")
    if not os.path.isfile(bert_bin):
        banner("结果: SKIP")
        print(" 找不到 %s" % bert_bin)
        print(" 官方只给了 Dropbox 链接 (见 Models/ReadME.txt):")
        print("   https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0")
        print("   md5 = 990d14de053d8080fcca33d712d647b6")
        print(" 放好后重跑: bash amp_pipeline/smoke_test_3models.sh")
        sys.exit(2)

    vocab, how = find_vocab()
    if vocab is None:
        banner("结果: FAIL")
        print(" bert.bin 在, 但找不到 bert-base-uncased 的 vocab.txt, tokenizer 无法构建。")
        print(" " + how)
        print(" 解决: bash amp_pipeline/install_envs.sh --only bert   (会自动下 vocab.txt)")
        sys.exit(1)
    print("\n[vocab] tokenizer 词表: %s (%d 行)" % (how, sum(1 for _ in open(how, errors="ignore"))))

    try:
        banner("加载 bert.bin")
        t0 = time.time()
        from bert_sklearn import load_model
        model = load_model(bert_bin)
        print("[1/4] load_model OK (%.1fs)" % (time.time() - t0))
        print("      class        = %s" % type(model).__name__)
        print("      bert_model   = %r" % getattr(model, "bert_model", None))
        print("      label2id     = %r" % getattr(model, "label2id", None))
        print("      max_seq_len  = %r" % getattr(model, "max_seq_length", None))

        banner("绑定 tokenizer")
        from bert_sklearn.model.pytorch_pretrained.tokenization import BertTokenizer
        do_lower = "cased" not in str(vocab)
        tok = BertTokenizer.from_pretrained(vocab, do_lower_case=do_lower)
        model.tokenizer = tok
        print("[2/4] tokenizer OK  vocab_size=%d  do_lower_case=%s" % (tok.vocab_size, do_lower))

        banner("真跑一次 predict_proba (n=%d)" % N)
        import numpy as np
        seqs = ["M K T A Y I A K Q R",          # 典型 AMP 样序列
                "G L F G L L G K L L K",
                "R C L C G R G I C",
                "A A A A A A A A A A A A"]
        seqs = [" ".join(list(s.replace(" ", ""))) for s in seqs]
        seqs = np.array((seqs * N)[:N])
        t1 = time.time()
        prob = model.predict_proba(seqs, use_cuda=USE_CUDA)
        dt = time.time() - t1
        p1 = np.asarray(prob)[:, 1]
        print("[3/4] predict_proba OK  用时 %.2fs → %.1f 条/秒" % (dt, N / dt if dt > 0 else float("inf")))
        print("      proba shape = %s" % (np.asarray(prob).shape,))
        print("      P(AMP)      = %s" % [round(float(v), 6) for v in p1])
        if not np.all(np.isfinite(p1)):
            print("[FAIL] 概率里出现 NaN/Inf")
            sys.exit(1)

        banner("GPU/CPU 实测 (确认设备真的被用上)")
        if USE_CUDA and torch.cuda.is_available():
            before = torch.cuda.memory_allocated() / 1024 ** 2
            model.predict_proba(seqs, use_cuda=True)
            after = torch.cuda.max_memory_allocated() / 1024 ** 2
            print("[4/4] CUDA 显存: 当前 %.1f MB / 峰值 %.1f MB → GPU 确实在算" % (before, after))
            if after <= 0.01:
                print("      (警告: 峰值显存几乎为 0, 可能实际落回了 CPU)")
        else:
            print("[4/4] 本次走 CPU (use_cuda=%s)" % USE_CUDA)

        banner("结果: PASS")
        print(" BERT 模型可加载 / 可 tokenize / 可出概率")
        sys.exit(0)

    except Exception:
        banner("结果: FAIL")
        traceback.print_exc()
        msg = str(sys.exc_info()[1])
        if "weights_only" in msg:
            print("\n>>> 诊断: torch>=2.6 的 torch.load 默认 weights_only=True。")
            print(">>> 解决: 已在 bert_sklearn/utils.py 加了 torch_load_compat(); 若你用的是外部")
            print(">>>       安装的 bert_sklearn, 请重装仓库自带的: ")
            print(">>>       $ENV_BERT/bin/pip install --no-deps --force-reinstall <repo>/bert_sklearn")
        elif "CUDA" in msg or "cuda" in msg:
            print("\n>>> 诊断: 像是 CUDA 相关问题。先 export BERT_USE_CUDA=0 用 CPU 验证模型本身没坏。")
        elif "vocab" in msg.lower():
            print("\n>>> 诊断: vocab.txt 有问题。重跑 install_envs.sh --only bert 重新下载。")
        sys.exit(1)


if __name__ == "__main__":
    main()
