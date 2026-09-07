#!/bin/bash
# ==============================================================================
# test_gpu.sh —— 检查 GTX 1650 在两个环境里是否都能被用上
#   1) 驱动层     : nvidia-smi
#   2) camps-tf114: TF1.14 能否看到 GPU, 并在 GPU 上跑一次矩阵乘 + 加载 att.h5/lstm.h5
#   3) py36       : torch.cuda 是否可用, sm_75 是否在支持列表, GPU 上跑一次矩阵乘
#
# 用法: bash amp_pipeline/test_gpu.sh
#       ENV_TF=/path/to/env ENV_BERT=/path/to/env bash amp_pipeline/test_gpu.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 自动定位 conda base
CONDA_BASE="$(conda info --base 2>/dev/null || true)"
if [ -z "$CONDA_BASE" ]; then
    for c in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/mambaforge" "$HOME/miniforge3" /opt/conda; do
        [ -d "$c/envs" ] && CONDA_BASE="$c" && break
    done
fi
ENV_TF="${ENV_TF:-$CONDA_BASE/envs/camps-tf114}"
ENV_BERT="${ENV_BERT:-$CONDA_BASE/envs/py36}"

PASS=0; FAIL=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

echo "=================================================="
echo " [1/3] 驱动层: nvidia-smi"
echo "=================================================="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used --format=csv
    if nvidia-smi -L | grep -qi "1650"; then ok "检测到 GTX 1650"; else ok "检测到 GPU (非 1650, 仍继续)"; fi
else
    bad "nvidia-smi 不存在。WSL2 用户: 请在 Windows 安装 NVIDIA 驱动 (>=470) 后重启 WSL (wsl --shutdown)"
fi

echo ""
echo "=================================================="
echo " [2/3] camps-tf114: TensorFlow 1.14 GPU"
echo "=================================================="
if [ ! -x "$ENV_TF/bin/python" ]; then
    bad "找不到 $ENV_TF/bin/python, 请先运行 setup_envs.sh tf"
else
    # WSL 内核无 NUMA, TF 会刷 "could not open file to read NUMA node" (无害), 这里过滤掉
    "$ENV_TF/bin/python" - "$PROJECT_DIR" 2> >(grep -v -i "numa" >&2) <<'PY'
import os, sys, time
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "1")
project = sys.argv[1]
import tensorflow as tf
print("  tensorflow", tf.__version__, "| built_with_cuda:", tf.test.is_built_with_cuda())
from tensorflow.python.client import device_lib
gpus = [d for d in device_lib.list_local_devices() if d.device_type == "GPU"]
if not gpus:
    print("  [FAIL] TF 看不到 GPU。常见原因: cudatoolkit 10.0 / cudnn 7.6 未随环境安装, 或驱动过旧")
    sys.exit(1)
for g in gpus:
    print("  [PASS] TF GPU:", g.physical_device_desc, "| 可用显存 %.0f MB" % (g.memory_limit / 1e6))

config = tf.ConfigProto(); config.gpu_options.allow_growth = True
with tf.Session(config=config) as sess:
    with tf.device("/gpu:0"):
        a = tf.random_normal([2048, 2048]); b = tf.random_normal([2048, 2048])
        c = tf.matmul(a, b)
    sess.run(c)  # warm-up
    t = time.time(); sess.run(c); dt = time.time() - t
    print("  [PASS] GPU 上 2048x2048 matmul 耗时 %.1f ms" % (dt * 1000))

# 加载两个 keras 模型, 确认 h5py / keras 版本兼容
from keras.backend.tensorflow_backend import set_session
set_session(tf.Session(config=config))
sys.path.insert(0, os.path.join(project, "script"))
from keras.models import load_model
from Attention import Attention_layer
import numpy as np
for name, kw in (("att.h5", {"custom_objects": {"Attention_layer": Attention_layer}}), ("lstm.h5", {})):
    p = os.path.join(project, "Models", name)
    if not os.path.exists(p):
        print("  [WARN] 缺 Models/%s, 跳过加载测试" % name); continue
    m = load_model(p, **kw)
    x = np.random.randint(1, 21, size=(8,) + tuple(m.input_shape[1:])).astype(np.float32)
    y = m.predict(x, batch_size=8)
    print("  [PASS] %s 加载并前向成功, 输入 %s -> 输出 %s" % (name, m.input_shape, y.shape))
PY
    if [ ${PIPESTATUS[0]} -eq 0 ]; then ok "camps-tf114 GPU 测试通过"; else bad "camps-tf114 GPU 测试失败"; fi
fi

echo ""
echo "=================================================="
echo " [3/3] py36: PyTorch CUDA (BERT)"
echo "=================================================="
if [ ! -x "$ENV_BERT/bin/python" ]; then
    bad "找不到 $ENV_BERT/bin/python, 请先运行 setup_envs.sh bert"
else
    "$ENV_BERT/bin/python" - "$PROJECT_DIR" <<'PY'
import sys, time, os
project = sys.argv[1]
import torch
print("  torch", torch.__version__, "| cuda build:", torch.version.cuda, "| cudnn:", torch.backends.cudnn.version())
if not torch.cuda.is_available():
    print("  [FAIL] torch.cuda.is_available() == False (是否装成了 CPU 版? 应为 1.10.1+cu113)")
    sys.exit(1)
name = torch.cuda.get_device_name(0)
cap = torch.cuda.get_device_capability(0)
archs = torch.cuda.get_arch_list()
print("  [PASS] GPU:", name, "| compute capability sm_%d%d" % cap, "| 显存 %.0f MB" % (torch.cuda.get_device_properties(0).total_memory / 1e6))
print("  torch 内置架构:", archs)
if "sm_%d%d" % cap not in archs:
    print("  [FAIL] 该 torch 未包含 sm_%d%d 内核" % cap); sys.exit(1)
a = torch.randn(2048, 2048, device="cuda"); b = torch.randn(2048, 2048, device="cuda")
torch.matmul(a, b); torch.cuda.synchronize()
t = time.time(); torch.matmul(a, b); torch.cuda.synchronize()
print("  [PASS] GPU 上 2048x2048 matmul 耗时 %.1f ms" % ((time.time() - t) * 1000))

import bert_sklearn
print("  [PASS] bert_sklearn", bert_sklearn.__version__, "已可导入")
p = os.path.join(project, "Models", "bert.bin")
if os.path.exists(p):
    m = bert_sklearn.load_model(p)
    print("  [PASS] bert.bin 加载成功 (bert_model=%s, max_seq_length=%s)" % (getattr(m, "bert_model", "?"), getattr(m, "max_seq_length", "?")))
else:
    print("  [WARN] 缺 Models/bert.bin (需按 Models/ReadME.txt 下载), 跳过加载测试")
print("  峰值显存占用 %.0f MB" % (torch.cuda.max_memory_allocated() / 1e6))
PY
    if [ $? -eq 0 ]; then ok "py36 CUDA 测试通过"; else bad "py36 CUDA 测试失败"; fi
fi

echo ""
echo "=================================================="
echo " 结果: PASS=$PASS  FAIL=$FAIL"
echo "=================================================="
[ "$FAIL" -eq 0 ]
