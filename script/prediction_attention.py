# -*- coding:utf-8 -*-

## usage python prediction_attention.py bact.txt att_bact.txt
import os
import csv
import sys
import numpy as np
import tensorflow as tf
from keras.backend.tensorflow_backend import set_session
from keras.models import load_model
from Attention import Attention_layer

# 动态申请 GPU 显存, 防止占满显存
config = tf.ConfigProto()
config.gpu_options.allow_growth = True
set_session(tf.Session(config=config))

model = load_model('../Models/att.h5', custom_objects={'Attention_layer': Attention_layer})

input_file = sys.argv[1]
output_file = sys.argv[2]
batch_size = int(os.environ.get("TF_PREDICT_BATCH_SIZE", "4096"))
chunksize = int(os.environ.get("TF_CHUNK_SIZE", "100000"))

print("[Attention] 正在流式预测 (分块大小: %d, Batch: %d)..." % (chunksize, batch_size))

def stream_matrix(filepath, chunk_size=100000):
    chunk = []
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            chunk.append([float(x) for x in row])
            if len(chunk) >= chunk_size:
                yield np.array(chunk, dtype=np.float32)
                chunk = []
        if chunk:
            yield np.array(chunk, dtype=np.float32)

total = 0
with open(output_file, 'w') as out_f:
    for idx, chunk_data in enumerate(stream_matrix(input_file, chunksize)):
        preds = model.predict(chunk_data, batch_size=batch_size)
        for p in preds:
            out_f.write("%.8f\n" % p)
        total += len(preds)
        if (idx + 1) % 10 == 0 or len(preds) < chunksize:
            print("  [Attention 进度] 已预测 %d 条序列" % total, flush=True)

print("[Attention] 完成 -> %s (共 %d 条)" % (output_file, total))
