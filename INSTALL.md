# 在 WSL + RTX A4000 上安装并跑通三个模型（mamba 加速版）

> 面向机器：`wsh@DESKTOP-IEUDGS5` (WSL2) · NVIDIA RTX A4000 16GB · 驱动 595.95 / CUDA 13.2 · miniconda 在 `/home/wsh/miniconda3`
>
> **先说清楚一件事**：你这台机器 `nvidia-smi` 只有 **1 张卡**（GPU 0 = RTX A4000）。
> 你说的“三个 GPU 跑通”，按仓库上下文理解就是 **三个模型跑通**：
> `Attention(att.h5)` / `LSTM(lstm.h5)` / `BERT(bert.bin)`。
> 自检脚本 `amp_pipeline/smoke_test_3models.sh` 就是逐个模型给 PASS/FAIL，最后再跑一遍端到端小样本。
> （如果你以后真有 3 张卡，见文末「多卡机器」。）

---

## 0. 为什么需要两个 conda 环境

官方 `requirement.txt` 自己就要求两套互不兼容的依赖，没法合成一个环境：

| 环境 | python | 关键包 | 负责的模型 |
| :--- | :--- | :--- | :--- |
| `camps-tf114` | **3.6** | tensorflow **1.14** + Keras **2.2.4** | Attention `att.h5`、LSTM `lstm.h5` |
| `camps-bert`  | 3.9 | torch **2.4.1** + 仓库自带 `bert_sklearn` 0.2.0 | BERT `bert.bin` |

tensorflow 1.14 在 PyPI 上**只有 cp36 / cp37 的 wheel**，所以第一个环境必须是 python 3.6（或 3.7），这也是它不能和 BERT 合并的根本原因。

> ⚠️ 你现在的 `bio_pep` 环境是 UniDL4BioPep 的，**别往里装东西**，两个项目会互相踩依赖。

### GPU 到底谁在用（重要，省你几小时排查）

| 模型 | 框架 | 你的 A4000 (Ampere, sm_86) 能用 GPU 吗 |
| :--- | :--- | :--- |
| Attention / LSTM | TF 1.14 = CUDA 10.0 | **基本不能**。CUDA 10.0 编译的 cubin 只到 sm_75，在 sm_86 上典型报错 `no kernel image is available for execution on the device`。 |
| BERT | torch 2.4.1 (cu12.1) | **能**，而且这是三个模型里最慢、最值得上 GPU 的一个。 |

所以脚本的默认策略就是 **TF 走 CPU，BERT 走 GPU**：
`TF_USE_GPU=auto` 会真的跑一个 kernel 探测，探测不过自动落 CPU；`BERT_USE_CUDA=auto` 检测到 CUDA 就开。
Attention/LSTM 都是 ≤50 AA 的小模型，CPU 上跑百万级肽段也完全够快，不用纠结。

---

## 1. 拿代码

```bash
cd ~
git clone -b arena/01a07ad2-c-amps-prediction \
    https://github.com/mqgg5630-cyber/c_AMPs-prediction.git
cd c_AMPs-prediction
```

已经有克隆的话，只要把分支切过来：

```bash
cd ~/c_AMPs-prediction
git fetch origin
git checkout arena/01a07ad2-c-amps-prediction
git pull origin arena/01a07ad2-c-amps-prediction
```

---

## 2. 一键装环境（mamba）

```bash
cd ~/c_AMPs-prediction
bash amp_pipeline/install_envs.sh 2>&1 | tee install.log
```

就这一条。它会：

1. **找/装 mamba**：`mamba` → `micromamba`（没有就自动下载 ~8MB 单文件）→ `conda --solver=libmamba` → conda classic，逐级回退。你 base 里已经有 conda，最省事的是先手动补一个 mamba：
   ```bash
   conda install -n base -c conda-forge mamba -y      # 可选，装了会更快
   ```
2. 建 `camps-tf114`（python 3.6），按 `conda-forge → anaconda/pkgs/free → python3.7` 三级回退，因为 conda-forge 当前 repodata 里可能已经查不到 3.6 了。
3. **两段式 bootstrap pip**（py3.6 自带的 pip 9.0.3 太老，装现代包会报 `manylinux2014` / metadata 不兼容）：`pip 9 → 20.3.4 → 21.3.1 + setuptools 59.6.0 + wheel 0.37.1`。
4. `pip install -r amp_pipeline/requirements_tf114.txt`。里面**每个版本号都确认过 PyPI 上有 linux cp36 wheel**，所以整条安装**不需要 gcc、不编译 C 扩展**。
5. 建 `camps-bert`（python 3.9）+ `torch==2.4.1`（PyPI 默认 wheel 就是 cu12.1，sm_86 可用）。
6. `pip install --no-deps ./bert_sklearn` —— 装**仓库自带**的 0.2.0。
   > 注意：README 里写的 `cd bert-sklearn && pip install .` 是**错的**。`setup.py` 在 `bert_sklearn/` 目录**里面**，那样 `find_packages()` 找不到顶层包。必须在仓库根目录执行 `pip install ./bert_sklearn`，脚本已经帮你处理了。
7. 下载 `bert-base-uncased` 的 `vocab.txt`（231KB / 30522 行）到 `Models/bert-base-uncased/vocab.txt` 和 `~/.cache/torch/pretrained_bert/`，**tokenizer 必需**，缺了 BERT 会以 exit 2 退出。
8. 写出 `amp_pipeline/env.sh`，把探测到的环境路径固化下来。

常用变体：

```bash
bash amp_pipeline/install_envs.sh --bert-cpu     # BERT 也不要 GPU，少下 ~5GB
bash amp_pipeline/install_envs.sh --tf-gpu       # 想赌一把 TF1.14 上 GPU
bash amp_pipeline/install_envs.sh --only tf      # 只装 Attention/LSTM 那套
bash amp_pipeline/install_envs.sh --only bert    # 只装 BERT 那套
FORCE=1 bash amp_pipeline/install_envs.sh        # 推倒重建
PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple bash amp_pipeline/install_envs.sh   # pip 换源
```

装完确认一下：

```bash
source amp_pipeline/env.sh --print
```

---

## 3. bert.bin（唯一需要你手动搞的东西）

`Models/att.h5`、`Models/lstm.h5` 已经在仓库里。**`bert.bin` 官方只给了 Dropbox 链接，且需要签 MTA**，脚本没法自动下：

```
https://www.dropbox.com/sh/o58xdznyi6ulyc6/AABLckEnxP54j2X7BrGybhyea?dl=0
md5 = 990d14de053d8080fcca33d712d647b6
```

WSL 里下载 Dropbox 很别扭，推荐**在 Windows 浏览器里下**，然后从 `/mnt/c` 拷进来：

```bash
bash amp_pipeline/install_envs.sh --bert-bin "/mnt/c/Users/<你的用户名>/Downloads/bert.bin"
# 它会拷到 Models/bert.bin 并自动校验 md5
```

**还没有 bert.bin？** 不影响先把另外两个模型跑通：

```bash
bash amp_pipeline/smoke_test_3models.sh --only tf          # 只测 Attention + LSTM
SMOKE_SKIP_BERT=1 bash amp_pipeline/smoke_test_3models.sh  # 全测，BERT 段显示 SKIP
```
端到端那一段会自动写**占位 BERT 概率**（全 0），把 `format.pl → 两个 TF 模型 → result.pl → 汇总` 整条链路验通；此时 `is_AMP` 必然全是 0，属正常（三票凑不齐）。

---

## 4. 跑通测试

### 4.1 逐模型自检（你要的“三个跑通”）

```bash
cd ~/c_AMPs-prediction
bash amp_pipeline/smoke_test_3models.sh 2>&1 | tee smoke.log
```

输出长这样，每项独立 PASS/FAIL/SKIP + 耗时 + 日志路径：

```
==> [1a] Attention (att.h5)
    | [env] tensorflow 1.14.0
    | [env] TF 可见设备: ['/device:CPU:0']
    | [1/4] load_model ...  OK  (2.1s)
    | [3/4] 真跑一次 predict (n=20, dim=300) ...  OK  用时 0.31s → 64.5 条/秒
    | [4/4] 输出概率合理性  min=0.000012 max=0.998734
    | [PASS] Attention 模型可正常加载并出概率
...
==============================================================
 自检结论
==============================================================
  项目                            结果   耗时     备注
  [0] 环境预检                    PASS   0s
  [1a] Attention (att.h5)         PASS   6s
  [1b] LSTM (lstm.h5)             PASS   4s
  [2] BERT (bert.bin)             PASS   25s
  [3] 端到端小样本                PASS   31s
  [3b] 三模型汇总 aggregate       PASS   -
==============================================================
 PASS 6 / SKIP 0 / FAIL 0
```

它做的事：

| 段 | 内容 |
| :--- | :--- |
| `[0]` | 机器/GPU/磁盘信息、两个 conda 环境、三个模型文件、`perl`、6 个脚本是否齐全 —— **fail-fast** |
| `[1a/1b]` | 在 `camps-tf114` 里真 `load_model(att.h5 / lstm.h5)`，打印结构概要，喂一个 `20×300` 的矩阵真跑 `predict`，检查概率在 `[0,1]` 且无 NaN |
| `[2]` | 在 `camps-bert` 里真 `load_model(bert.bin)`，绑定 tokenizer，跑 `predict_proba`，并读 `torch.cuda.max_memory_allocated()` 证明 GPU 真的在算 |
| `[3]` | `Data/AMPs.fa` 前 N 条 → `format.pl` → 三模型 → `result.pl` → `final_prediction.txt` |
| `[3b]` | `aggregate_amp_results.py` 出 `aggregated_results.tsv` / `amp_summary.tsv` / `amp_all_peptides.tsv` |

常用变体：

```bash
N=200 bash amp_pipeline/smoke_test_3models.sh              # 200 条，顺便看吞吐
bash amp_pipeline/smoke_test_3models.sh --no-e2e           # 只做模型级自检，快
bash amp_pipeline/smoke_test_3models.sh --only bert        # 只测 BERT
TF_USE_GPU=1 bash amp_pipeline/smoke_test_3models.sh --only tf   # 强行让 TF 上 GPU（大概率 FAIL，用于确认诊断信息）
BERT_USE_CUDA=0 bash amp_pipeline/smoke_test_3models.sh --only bert  # 强行让 BERT 走 CPU
bash amp_pipeline/smoke_test_3models.sh /path/to/your.fa   # 换自己的输入
```

### 4.2 想亲手确认 GPU 有没有被 BERT 吃到

```bash
source amp_pipeline/env.sh
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv -l 1 &   # 另开一个终端更好
N=2000 bash amp_pipeline/smoke_test_3models.sh --only bert
```
`[2]` 段日志里那行 `CUDA 显存: 当前 xxx MB / 峰值 xxx MB → GPU 确实在算` 就是判据；峰值 >100MB 说明真在 GPU 上。

### 4.3 端到端（老入口，等价于 [3]+[3b]）

```bash
N=50 bash amp_pipeline/test_models.sh
```

---

## 5. 跑真实数据

```bash
source amp_pipeline/env.sh

# 单个分组
bash amp_pipeline/run_pipeline_one.sh \
    sorf_grouped_catalog/Cohort1_Matched265_5Stage/Cohort1_NC.fa \
    amp_results/Cohort1_Matched265_5Stage/Cohort1_NC

# 全部分组（自带断点续跑：已完成的组自动跳过）
bash amp_pipeline/run_pipeline_all_groups.sh sorf_grouped_catalog amp_results

# 三模型投票汇总
python3 amp_pipeline/aggregate_amp_results.py amp_results
```

16GB 显存可以把批量开大，BERT 会明显提速：

```bash
export BERT_EVAL_BATCH_SIZE=256     # 默认 64
export BERT_MAX_SEQ_LENGTH=64       # 肽段 ≤50AA，裁掉无效 PAD，提速 2~4 倍
export BERT_CHUNK_SIZE=50000        # 流式分块，控内存
```

显存/内存吃紧就往小调（`BERT_EVAL_BATCH_SIZE=32`、`TF_CHUNK_SIZE=5000`、`TF_PREDICT_BATCH_SIZE=256`）。

---

## 6. 踩坑速查

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| `no kernel image is available for execution on the device` | TF1.14 的 CUDA10 kernel 没有 sm_86 | `export TF_USE_GPU=0`（默认 auto 已经会自动落 CPU） |
| `PackagesNotFoundError: python=3.6` | conda-forge 当前 repodata 太老查不到 | 脚本自动回退到 `pkgs/free`、再回退到 python 3.7；也可手动 `TF_PY=3.7 bash amp_pipeline/install_envs.sh --only tf` |
| pip 报 `manylinux2014_x86_64 is not a supported wheel` | py3.6 自带 pip 9.0.3 太老 | 脚本已两段式升到 21.3.1；手动修：`$ENV_TF/bin/pip install pip==20.3.4 && $ENV_TF/bin/pip install pip==21.3.1` |
| `UnpicklingError ... weights_only=True` | torch ≥ 2.6 改了 `torch.load` 默认值 | 仓库里 `bert_sklearn/utils.py` 已加 `torch_load_compat()`；若你用的是外部装的 bert_sklearn，重装仓库自带版：`$ENV_BERT/bin/pip install --no-deps --force-reinstall ./bert_sklearn` |
| `[BERT tokenizer 无法解析]` exit 2 | 缺 `vocab.txt` | `bash amp_pipeline/install_envs.sh --only bert` 会自动下；离线就手动放 `Models/bert-base-uncased/vocab.txt` |
| `ImportError: No module named 'Attention'` | 没在 `script/` 目录下跑，或 `PYTHONPATH` 丢了 | 用 `run_pipeline_one.sh`（已自动 `cd script/` + 注入 `PYTHONPATH`）；手动跑就要 `cd script && python prediction_attention.py ...` |
| `找不到 TF 环境 python: /home/w26/miniconda3/...` | 老脚本硬编码了别人的家目录 | 已修：现在自动探测 `CONDA_ROOT`。也可显式 `ENV_TF=... ENV_BERT=... bash ...` 或 `source amp_pipeline/env.sh` |
| WSL 里 `torch.cuda.is_available()` 是 False | Windows 侧 NVIDIA 驱动问题（WSL 不要装 Linux 驱动） | Windows 上更新 GeForce 驱动 → `wsl --shutdown` → 重开；`nvidia-smi` 在 WSL 里能出卡就说明通了 |
| 下载慢 / 超时 | 网络 | `PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple`；vocab 走 `HF_VOCAB_URL=https://hf-mirror.com/...`；torch 改用 `--bert-cpu` |
| 磁盘不够 | torch cu121 + nvidia 运行库约 6GB，两个环境合计 12~15GB | `df -h ~`；或 `bash amp_pipeline/install_envs.sh --bert-cpu` |

日志位置：`test_run/smoke/logs/{attention,lstm,bert,e2e,aggregate}.log`。

---

## 7. 多卡机器（万一以后有 3 张卡）

框架层面**只有 BERT 能吃 GPU**，所以多卡的正确用法是「按卡分数据并行」，不是让一个模型跨卡：

```bash
BERT_GPU=0 bash amp_pipeline/run_pipeline_one.sh  A.fa out_A &
BERT_GPU=1 bash amp_pipeline/run_pipeline_one.sh  B.fa out_B &
BERT_GPU=2 bash amp_pipeline/run_pipeline_one.sh  C.fa out_C &
wait
```

`BERT_GPU=n` 会被 `amp_pipeline/env.sh` 映射成 `CUDA_VISIBLE_DEVICES=n`（并已设 `CUDA_DEVICE_ORDER=PCI_BUS_ID`，保证编号和 `nvidia-smi` 一致）。

Attention/LSTM 是 CPU 跑的，多开几个进程即可，注意别把内存打满：

```bash
for f in sorf_grouped_catalog/*/*.fa; do
    echo "$f"
done | xargs -P 4 -I{} bash amp_pipeline/run_pipeline_one.sh {} amp_results/$(basename {})
```

---

## 8. 新增/改动的文件一览

```
INSTALL.md                      ← 本文件 (仓库根目录)

amp_pipeline/
├── lib.sh                      (新) 公共函数: conda root/mamba 探测、环境自动解析、设备策略
├── env.sh                      (新) source 它就拿到 ENV_TF/ENV_BERT + 运行期默认参数
├── install_envs.sh             (新) 一键建两个环境 (mamba 加速, 幂等, 多级回退)
├── smoke_test_3models.sh       (新) 三模型逐个 PASS/FAIL + 端到端小样本
├── requirements_tf114.txt      (新) TF1.14/Keras2.2.4 全钉死 (全部有 cp36 manylinux wheel)
├── requirements_bert.txt       (新) torch 侧依赖全钉死
├── test_models.sh              (改) 去掉硬编码 /home/w26, 改为自动探测
├── run_pipeline_one.sh         (改) 自动探测环境 + TF 设备策略 + 新增 skip-bert
└── run_pipeline_all_groups.sh  (改) 自动探测环境 + 开跑前统一预检

script/
├── _smoke_tf.py                (新) Attention/LSTM 独立自检 (cwd 自动切到 script/)
└── _smoke_bert.py              (新) BERT 独立自检 (含 GPU 显存实测)

bert_sklearn/
├── utils.py                    (改) 新增 torch_load_compat(), 兼容 torch>=2.6
├── sklearn.py                  (改) 两处 torch.load → torch_load_compat
└── model/pytorch_pretrained/modeling.py (改) 预训练权重一律先加载到 CPU + 兼容 torch>=2.6
```
