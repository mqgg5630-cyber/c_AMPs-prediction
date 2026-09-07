# 本地安装与 GPU 自检 (WSL2 + GTX 1650)

三个模型分两个 conda 环境跑（与官方 requirement.txt 一致）：

| 环境 | 模型 | 关键版本 |
| :-- | :-- | :-- |
| `camps-tf114` | Attention `att.h5`、LSTM `lstm.h5` | Python 3.6, tensorflow-gpu 1.14, cudatoolkit 10.0, cudnn 7.6, Keras 2.2.4, h5py 2.10 |
| `py36` | BERT `bert.bin` | Python 3.6, torch 1.10.1+cu113, pytorch_pretrained_bert 0.6.1, 本仓库 `bert_sklearn` |

GTX 1650 是 Turing (sm_75)：CUDA 10.0 与 cu113 均支持，无需自己编译。
**WSL2 只需在 Windows 装 NVIDIA 驱动（≥470），WSL 内不要装驱动**；conda/pip 会把 CUDA 运行库装进各自环境。

## 一、准备

```bash
# 1) 装 Miniconda (若已有 conda 则跳过)
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p ~/miniconda3
~/miniconda3/bin/conda init bash && exec bash

# 2) 确认驱动已透传进 WSL
nvidia-smi          # 应显示 GeForce GTX 1650, 4096MiB

# 3) 拉代码
git clone <本仓库> c_AMPs-prediction && cd c_AMPs-prediction
```

## 二、一键安装两个环境

```bash
bash amp_pipeline/setup_envs.sh          # 全部
# bash amp_pipeline/setup_envs.sh tf     # 只装 camps-tf114
# bash amp_pipeline/setup_envs.sh bert   # 只装 py36
# FORCE=1 bash amp_pipeline/setup_envs.sh  # 删掉重建
```

脚本会：创建 `camps-tf114`（conda 自动带上 cudatoolkit 10.0 / cudnn 7.6）→ pip 装 Keras 2.2.4 / h5py 2.10 →
创建 `py36` → pip 装 `torch==1.10.1+cu113` → `pip install -e bert_sklearn`。
结尾各打印一次版本核对。

## 三、下载 BERT 模型

`att.h5`、`lstm.h5` 已在 `Models/`。`bert.bin` 需按 `Models/ReadME.txt` 从 Dropbox 下载放到 `Models/bert.bin`，然后：

```bash
md5sum Models/*.h5 Models/bert.bin
# lstm.h5 13a484aeef0eb3de129368d1e939c0b8
# att.h5  af736531da1dcc5b3381a6071f71fb08
# bert.bin 990d14de053d8080fcca33d712d647b6
```

## 四、测 GPU

```bash
bash amp_pipeline/test_gpu.sh
```

依次检查：`nvidia-smi` → TF1.14 是否列出 GPU、GPU 上跑 matmul、加载 `att.h5`/`lstm.h5` 前向 →
torch CUDA 是否可用、`sm_75` 是否在内置架构列表、GPU matmul、加载 `bert.bin`。最后打印 `PASS=n FAIL=m`。

## 五、测三个模型（端到端）

```bash
bash amp_pipeline/test_models.sh        # 用 Data/AMPs.fa 前 20 条
N=100 bash amp_pipeline/test_models.sh  # 前 100 条
```

看到 Attention / LSTM / BERT 三行“完成”且无 Traceback 即可；结果在 `test_run/run_output/`。

## 六、4 GB 显存调参

脚本默认值已按 GTX 1650 设定，可用环境变量覆盖：

| 变量 | 默认 | 说明 |
| :-- | :-- | :-- |
| `TF_PREDICT_BATCH_SIZE` | 1024 | Attention/LSTM 预测 batch |
| `TF_CHUNK_SIZE` | 20000 | Attention/LSTM 每次读入行数 |
| `BERT_EVAL_BATCH_SIZE` | 64 | BERT batch，OOM 时降到 32/16 |
| `BERT_MAX_SEQ_LENGTH` | 模型内置 | 序列都 <50AA 时设 64 可显著提速 |
| `BERT_USE_CUDA` | auto | `0` 强制 CPU |

例：`BERT_EVAL_BATCH_SIZE=32 BERT_MAX_SEQ_LENGTH=64 bash amp_pipeline/test_models.sh`

## 七、常见问题

| 现象 | 处理 |
| :-- | :-- |
| `nvidia-smi: command not found` | Windows 侧装 NVIDIA 驱动，`wsl --shutdown` 后重开 |
| TF 报 `libcudart.so.10.0 not found` | `conda install -n camps-tf114 cudatoolkit=10.0 cudnn=7.6 -c defaults` |
| TF 报 `Could not create cudnn handle` / OOM | 已开 `allow_growth`；再降 `TF_PREDICT_BATCH_SIZE=256` |
| `load_model` 报 `'str' object has no attribute 'decode'` | h5py 版本过高：`pip install h5py==2.10.0` |
| torch 安装报 `HASHES DO NOT MATCH` / `BadZipFile` | 1.8GB wheel 下载被掐断。脚本已改为 `wget -c` 续传到 `~/.cache/torch_wheels/`，**重跑 `setup_envs.sh bert` 即可续传** |
| `torch.cuda.is_available()` 为 False | 装成了 CPU 版，重跑 `setup_envs.sh bert` 或 `pip install torch==1.10.1+cu113 --extra-index-url https://download.pytorch.org/whl/cu113` |
| BERT 报 tokenizer 无法解析 | 首次需联网下载 `bert-base-uncased` vocab；离线时把 `vocab.txt` 放到 `Models/bert-base-uncased/` |
| mamba 下载 cudatoolkit/cudnn 报 `Download error (56)` / `unexpected eof` | 镜像对大包断线。脚本已改为 `wget -c` 断点续传预下载，**直接重跑 `setup_envs.sh tf` 即可续传** |
| conda 解析 tf-gpu 1.14 很慢 | `conda install -n base mamba -c conda-forge`，脚本会自动改用 mamba |
