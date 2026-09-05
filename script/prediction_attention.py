# -*- coding:utf-8 -*-

## usage python prediction_attention.py bact.txt att_bact.txt
import os
import tensorflow as tf
from keras.backend.tensorflow_backend import set_session
from keras.models import load_model
from numpy import loadtxt, savetxt
from Attention import Attention_layer
from sys import argv

# 动态申请 GPU 显存, 防止占满显存
config = tf.ConfigProto()
config.gpu_options.allow_growth = True
set_session(tf.Session(config=config))

model = load_model('../Models/att.h5', custom_objects={'Attention_layer': Attention_layer})
x = loadtxt(argv[1], delimiter=",")

batch_size = int(os.environ.get("TF_PREDICT_BATCH_SIZE", "2048"))
preds = model.predict(x, batch_size=batch_size)
savetxt(argv[2], preds, fmt="%.8f", delimiter=",")
