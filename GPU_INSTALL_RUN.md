# c_AMPs-prediction —— 在本机 (GPU / WSL) 安装与三模型冒烟测试

本文件给出在**你自己的电脑**(nvidia-smi 可见 RTX A4000, WSL/Ubuntu)上用 `mamba`
创建环境、安装依赖、下载模型、并验证 **Attention / LSTM / BERT** 三个模型跑通的完整步骤。

> 环境说明: 本仓库为不同模型保留了不同深堆, 必须分开装:
> - **`camps-tf114`**: 跑 `Attention`(`att.h5`) 和 `LSTM`(`lstm.h5`) —— TensorFlow 1.14 + Keras 2.2.4
> - **`py36`**: 跑 `BERT`(`bert.bin`) —— PyTorch + 仓库自带 `bert_sklearn` 0.2.0
>
> 所有路径、脚本都支持用环境变量覆盖, 见各脚本头部注释。

---

## 0. 需要的仓库文件

克隆本仓库并 `cd` 进去(`bert_sklearn` 用的是仓库内自带那份, 无需单独 git clone 其它文件):

```bash
git clone git@github.com:USER/c_AMPs-prediction.git
cd c_AMPs-prediction
```

`Models/` 下当前只有 `att.h5` 和 `lstm.h5`(已入库)。
**`Models/bert.bin` 体积大、不入库**, 需按 Models/ReadME.txt 单独下载(见第 4 节)。

---

## 1. 确认 mamba / conda

仓库自带一键脚本, 会自动探测 `mamba`/`conda` 与常见安装路径。

```bash
bash amp_pipeline/setup_envs_mamba.sh all
```

如果上面找不到你的 mamba(例如装在非默认路径), 可以先手动确认:

```bash
which mamba conda          # 应能看到路径
mamba --version
```

没有 mamba 就装一个(WSL/Linux, 选 Miniforge 自带 mamba, 比 conda 默认求解快很多):

```bash
wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
bash Miniforge3-Linux-x86_64.sh -b
source ~/miniforge3/etc/profile.d/conda.sh
conda activate
mamba --version
```

---

## 2. 单独创建两个环境(等效于上面 `all`, 也可分步)

### 2.1 环境 `camps-tf114`(Attention + LSTM)

```bash
mamba create -y -n camps-tf114 python=3.7 pip
conda activate camps-tf114
pip install numpy==1.16.2 h5py==2.9.0 Keras==2.2.4 pillow
# GPU 版优先; 若你的新驱动(如 595.x)装不上老 CUDA 运行库会自动回退 CPU:
pip install tensorflow-gpu==1.14.0 2>/dev/null || pip install tensorflow==1.14.0
python -c "import tensorflow as tf, keras; print(tf.__version__, keras.__version__)"
```

或一步: `bash amp_pipeline/setup_envs_mamba.sh tf`

> **关于 TF1.14 的 GPU**: 这是 2019 年的版本, GPU 版绑定老 CUDA10/cuDNN7 运行库。
> 在 RTX A4000 / 595.x 驱动 / 新 WSL2 下**几乎必然只能跑 CPU**——这不影响预测正确性,
> 只是稍慢。真正用 GPU 跑的是第 2.2 节的 BERT(PyTorch)。

### 2.2 环境 `py36`(BERT)

```bash
mamba create -y -n py36 python=3.7 pip
conda activate py36
# BERT 用 PyTorch。要在本机 GPU 上推理, 装与你 CUDA 版本匹配的 cu wheel; 装不上就用 CPU 版(仅慢):
pip install torch==1.10.0 --index-url https://download.pytorch.org/whl/cu113   # 或去掉 --index-url 装 CPU 版
pip install numpy pandas scikit-learn regex tqdm boto3 requests
cd bert_sklearn && pip install .   # 安装仓库自带 bert_sklearn 0.2.0
python -c "import torch; from bert_sklearn import BertClassifier; print(torch.__version__)"
```

或一步: `bash amp_pipeline/setup_envs_mamba.sh bert`

> 手动装时请让 `py36` 的 python 在能 `import bert_sklearn` 的位置运行预测脚本(已在仓库根 `script/` 下)。

---

## 3. 确认 GPU 可见

```bash
nvidia-smi            # 应列出你的卡, 如 RTX A4000
python -c "import torch; print('torch cuda:', torch.cuda.is_available())"   # 在 py36 环境内
```

如果第 2 节的 torch 是 CUDA 版且驱动正常, 这里应打印 `torch cuda: True` —— BERT 就会走 GPU。

---

## 4. 下载 BERT 模型 `bert.bin`

```bash
# 从 Models/ReadME.txt 给出的地址下载
#   https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0
mv 下载到的文件 Models/bert.bin
md5sum Models/bert.bin    # 期望 990d14de053d8080fcca33d712d647b6
```

---

## 5. 一键冒烟测试: 验证三模型都跑通

脚本会自动探测两个环境、打印每步用的 GPU/CPU 后端、逐模型出概率文件:

```bash
bash amp_pipeline/test_models_gpu.sh            # Data/AMPs.fa 前 20 条
N=50 bash amp_pipeline/test_models_gpu.sh       # 前 50 条
```

如果环境在非标准路径, 直接传绝对路径:

```bash
ENV_TF=/home/you/miniconda3/envs/camps-tf114 \
ENV_BERT=/home/you/miniconda3/envs/py36 \
bash amp_pipeline/test_models_gpu.sh
```

预期输出: `test_run/` 下生成
`attention_proba.tsv`、`lstm_proba.tsv`、`bert_proba.tsv`,每行一个 0~1 概率,行数=测试序列数;
结尾打印 `三模型全部跑通 ✓`(若还没下 `bert.bin`,则提示只跑通 Attention+LSTM,退出码 2)。

---

## 6. 在完整分组数据上跑正式流程

单组(sORF 分组 FASTA → 三模型投票 → 最终预测):

```bash
bash amp_pipeline/run_pipeline_one.sh <group.fa> <out_dir>
```

该脚本会做三模型预测并用 `result.pl` 投票生成 `final_prediction.txt`。
需保证 `Models/att.h5 lstm.h5 bert.bin` 齐全、两个环境存在(环境路径可在标准位置自动找到, 或用第 4/5 参数指定)。

---

## 7. 常见问题

| 现象 | 处理 |
| --- | --- |
| `run_pipeline_one.sh` 预检报缺 `bert.bin` | 按第 4 节下载并放 `Models/`, 校验 md5 |
| TF 打印 `未检测到可用 GPU` | 正常, TF1.14 GPU 需老 CUDA; 用 CPU 跑结果一致 |
| `py36` 里 `bert_sklearn` 导入失败 | 确认在 `bert_sklearn/` 内执行了 `pip install .` |
| 想用三块真实 GPU 并行 | 仓库跑的是"三个模型",非三卡并行; 如需多卡请把 `test_models_gpu.sh`/预测脚本按 GPU id 拆成三份再分别 `CUDA_VISIBLE_DEVICES=0/1/2` 运行 |
| 无网/内网机 | 把两个 env 的 conda-pack 打包装到目标机即可复用 |

> 注: 本文件与 `setup_envs_mamba.sh`、`test_models_gpu.sh` 由本项目维护,
> 请在本机实际执行后再根据自身环境微调。
