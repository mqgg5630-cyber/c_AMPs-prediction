# -*- coding:utf-8 -*-

## usage python prediction_lstm.py sequence_after_format.txt lstm_bact.txt
import os
import tensorflow as tf
from keras.backend.tensorflow_backend import set_session
from keras.models import load_model
from numpy import loadtxt, savetxt
from sys import argv

# 动态申请 GPU 显存, 防止占满显存
config = tf.ConfigProto()
config.gpu_options.allow_growth = True
set_session(tf.Session(config=config))

model = load_model('../Models/lstm.h5')
x = loadtxt(argv[1], delimiter=",")

batch_size = int(os.environ.get("TF_PREDICT_BATCH_SIZE", "2048"))
preds = model.predict(x, batch_size=batch_size)
savetxt(argv[2], preds, fmt="%.8f", delimiter=",")
