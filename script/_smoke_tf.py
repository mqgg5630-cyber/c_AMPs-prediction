#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
_smoke_tf.py —— Attention / LSTM 两个 TF1.14 模型的独立自检 (camps-tf114 环境里跑)

用法:
    python _smoke_tf.py <att|lstm|both> [n_seq]

必须 **cd 到 script/ 目录** 再跑, 因为:
  * prediction_*.py 里模型路径是相对写法 '../Models/xxx.h5'
  * prediction_attention.py 里 `from Attention import Attention_layer` 依赖 cwd
退出码: 0 = 通过, 1 = 失败, 2 = 跳过 (模型文件缺失)
"""
from __future__ import print_function

import os
import sys
import time
import traceback

MODE = sys.argv[1] if len(sys.argv) > 1 else "both"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 8

HERE = os.path.dirname(os.path.abspath(__file__))          # .../script
PROJECT = os.path.dirname(HERE)                            # .../c_AMPs-prediction
sys.path.insert(0, HERE)

# 相对路径 '../Models/...' 是相对 cwd 的, 这里强制 cd 到 script/
os.chdir(HERE)


def banner(t):
    print("\n" + "-" * 66)
    print(" " + t)
    print("-" * 66)
    sys.stdout.flush()


def report_devices():
    import tensorflow as tf
    print("[env] tensorflow %s" % tf.__version__)
    try:
        import keras
        print("[env] keras      %s (backend=%s)" % (keras.__version__, keras.backend.backend()))
    except Exception as e:
        print("[env] keras 导入失败: %r" % (e,))
    import numpy as np
    print("[env] numpy      %s" % np.__version__)
    print("[env] CUDA_VISIBLE_DEVICES = %r" % os.environ.get("CUDA_VISIBLE_DEVICES", "<unset>"))
    print("[env] TF_FORCE_GPU_ALLOW_GROWTH = %r" % os.environ.get("TF_FORCE_GPU_ALLOW_GROWTH", "<unset>"))
    try:
        from tensorflow.python.client import device_lib
        devs = [d.name for d in device_lib.list_local_devices()]
        print("[env] TF 可见设备: %s" % devs)
        gpu_ok = any("/GPU" in d for d in devs)
        print("[env] GPU 是否被 TF 识别: %s" % ("是" if gpu_ok else "否 (将走 CPU)"))
    except Exception as e:
        print("[env] 列设备失败 (不影响 CPU 推理): %r" % (e,))
    sys.stdout.flush()


def make_batch(n, dim=300):
    """构造一个和 format.pl 输出同形状的矩阵: n 行 x 300 列, 取值 {0..20}。"""
    import numpy as np
    rng = np.random.RandomState(42)
    x = rng.randint(0, 21, size=(n, dim)).astype("float32")
    # 模拟真实数据: 前面一大段是 0 (padding), 后面才是氨基酸编码
    x[:, :dim // 2] = 0
    return x


def check_model(name, weight_file, need_custom=False):
    banner("模型 %s  (%s)" % (name, weight_file))
    if not os.path.isfile(weight_file):
        print("[SKIP] 找不到模型文件: %s" % weight_file)
        return 2

    t0 = time.time()
    try:
        import numpy as np
        import tensorflow as tf
        from keras.models import load_model
        from keras.backend.tensorflow_backend import set_session

        # 显存按需增长, 别一上来就吃满 (和 prediction_*.py 行为一致)
        cfg = tf.ConfigProto()
        cfg.gpu_options.allow_growth = True
        set_session(tf.Session(config=cfg))

        custom = {}
        if need_custom:
            from Attention import Attention_layer          # noqa: 依赖 cwd=script/
            custom = {"Attention_layer": Attention_layer}

        print("[1/4] load_model ...")
        model = load_model(weight_file, custom_objects=custom or None)
        print("      OK  (%.1fs)" % (time.time() - t0))

        print("[2/4] 模型结构概要")
        try:
            print("      input_shape  = %s" % (model.input_shape,))
            print("      output_shape = %s" % (model.output_shape,))
            print("      layers       = %d, params = %s" %
                  (len(model.layers), "{:,}".format(int(model.count_params()))))
        except Exception as e:
            print("      (概要打印失败, 不影响推理: %r)" % (e,))

        print("[3/4] 真跑一次 predict (n=%d, dim=300) ..." % N)
        t1 = time.time()
        xb = make_batch(N)
        p = model.predict(xb, batch_size=N)
        p = np.asarray(p).reshape(-1)
        dt = time.time() - t1
        print("      OK  用时 %.2fs  →  %.1f 条/秒" % (dt, N / dt if dt > 0 else float("inf")))

        print("[4/4] 输出概率合理性")
        print("      shape=%s  min=%.6f  max=%.6f  mean=%.6f" %
              (p.shape, float(np.min(p)), float(np.max(p)), float(np.mean(p))))
        if not np.all(np.isfinite(p)):
            print("[FAIL] 概率里出现 NaN/Inf")
            return 1
        if float(np.min(p)) < -1e-6 or float(np.max(p)) > 1.0 + 1e-6:
            print("[FAIL] 概率超出 [0,1] —— 模型或输入形状不对")
            return 1
        print("      前 5 条概率: %s" % [round(float(v), 6) for v in p[:5]])
        print("[PASS] %s 模型可正常加载并出概率" % name)
        return 0
    except Exception:
        print("[FAIL] %s 模型异常:" % name)
        traceback.print_exc()
        hint = str(sys.exc_info()[1])
        if "no kernel image is available" in hint:
            print("\n>>> 诊断: 这是 CUDA 10.0 的 kernel 没有为你的显卡架构 (Ampere/sm_86) 编译。")
            print(">>> 解决: export TF_USE_GPU=0 (走 CPU) —— Attention/LSTM 是小模型, CPU 完全够快。")
        elif "Cannot assign a device" in hint or "no device" in hint.lower():
            print("\n>>> 诊断: 指定的 GPU 设备不可用。export TF_USE_GPU=0 走 CPU。")
        return 1


def main():
    report_devices()
    rc = []
    if MODE in ("att", "attention", "both"):
        rc.append(check_model("Attention", os.path.join(PROJECT, "Models", "att.h5"),
                              need_custom=True))
    if MODE in ("lstm", "both"):
        rc.append(check_model("LSTM", os.path.join(PROJECT, "Models", "lstm.h5")))

    banner("TF 侧自检结论")
    if any(r == 1 for r in rc):
        print(" 结果: FAIL")
        sys.exit(1)
    if all(r == 2 for r in rc):
        print(" 结果: SKIP (模型文件都不在)")
        sys.exit(2)
    print(" 结果: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
