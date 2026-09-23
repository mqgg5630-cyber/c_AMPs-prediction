# 阿尔茨海默病肠道宏基因组 sORF 抗菌肽（AMP）三模型预测：完整结果与方法

- 项目：AD 队列肠道 MAG 来源 sORF 的候选 AMP 挖掘
- 计算完成：2026-09-13；文档生成：2026-09-23
- 代码与产物：`mqgg5630-cyber/c_AMPs-prediction` 分支 `arena/01a07992-c-amps-prediction`
- 本机路径：`/home/w24e/0amp/att-lstm-bert/deliverable/`（本文件），原始结果 `/home/w24e/c_AMPs-prediction/amp_results/`

---

## 一、结果总览

### 1.1 全局漏斗（唯一序列层面）

| 阶段 | 唯一序列数 | 占上一级 | 占全部 |
|---|---:|---:|---:|
| 14 组 sORF 记录合计（含跨组重复） | 431,608,983 条记录 | — | — |
| 全局去重后的唯一 sORF | 160,215,813 | — | 100% |
| Attention > 0.5 | 约 6,600 万（估） | — | — |
| LSTM > 0.5 | 约 6,800 万（估） | — | — |
| **Attention 且 LSTM > 0.5（两票）** | **39,017,936** | — | **24.35%** |
| **两票中 BERT > 0.5（三票 = 最终候选 AMP）** | **12,665,622** | 32.46% | **7.91%** |

- 序列长度（sORF 定义 ≤ 50 aa）：两票序列中位数 11 aa，P90 27 aa，P99 46 aa，最大 50 aa。
- 非标准氨基酸序列：0 条；被截断（>300 位）序列：0 条。
- BERT 概率分布（两票序列）：最小 1.1×10⁻⁴，P10 0.0018，P50 0.110，P90 0.973，最大 0.9996——呈明显双峰，说明 BERT 对两票序列有实质区分力，而非"随机再筛"。

### 1.2 14 个分组的完整结果

| 队列 | 分组 | 样本切片 | 输入 sORF 数 | 两票 n | 两票 % | **三票 n** | **三票 %** |
|---|---|---|---:|---:|---:|---:|---:|
| Cohort1_Matched265_5Stage | Cohort1_NC  | 匹配 265 例 | 23,356,299 | 6,003,623 | 25.70 | **1,888,741** | **8.09** |
| Cohort1_Matched265_5Stage | Cohort1_SCS | 匹配 265 例 | 22,367,879 | 5,739,579 | 25.66 | **1,798,519** | **8.04** |
| Cohort1_Matched265_5Stage | Cohort1_SCD | 匹配 265 例 | 23,822,480 | 6,124,753 | 25.71 | **1,927,898** | **8.09** |
| Cohort1_Matched265_5Stage | Cohort1_MCI | 匹配 265 例 | 18,372,512 | 4,749,949 | 25.85 | **1,483,763** | **8.08** |
| Cohort1_Matched265_5Stage | Cohort1_AD  | 匹配 265 例 | 24,822,428 | 6,433,553 | 25.92 | **2,010,251** | **8.10** |
| Cohort2_Matched265_NCvsAD | Cohort2_Healthy_NC | 匹配 265 例 | 23,356,299 | 6,003,623 | 25.70 | **1,888,741** | **8.09** |
| Cohort2_Matched265_NCvsAD | Cohort2_Disease_AD | 匹配 265 例 | 24,822,428 | 6,433,553 | 25.92 | **2,010,251** | **8.10** |
| Cohort3_Full476_5Stage | Cohort3_NC  | 全部 476 例 | 27,378,997 | 6,982,534 | 25.50 | **2,197,149** | **8.02** |
| Cohort3_Full476_5Stage | Cohort3_SCS | 全部 476 例 | 33,124,222 | 8,451,627 | 25.51 | **2,668,215** | **8.06** |
| Cohort3_Full476_5Stage | Cohort3_SCD | 全部 476 例 | 37,345,907 | 9,509,040 | 25.46 | **3,015,354** | **8.07** |
| Cohort3_Full476_5Stage | Cohort3_MCI | 全部 476 例 | 42,524,471 | 10,788,969 | 25.37 | **3,422,342** | **8.05** |
| Cohort3_Full476_5Stage | Cohort3_AD  | 全部 476 例 | 52,971,582 | 13,469,017 | 25.43 | **4,276,575** | **8.07** |
| Cohort4_Full476_NCvsAD | Cohort4_Healthy_NC | 全部 476 例 | 27,378,997 | 6,982,534 | 25.50 | **2,197,149** | **8.02** |
| Cohort4_Full476_NCvsAD | Cohort4_Disease_AD | 全部 476 例 | 52,971,582 | 13,469,017 | 25.43 | **4,276,575** | **8.07** |

说明：
- Cohort2 的两组与 Cohort1 的 NC/AD 是同一批样本，Cohort4 与 Cohort3 的 NC/AD 同理，数字相同属预期。
- 两票 % 范围 25.37–25.92，三票 % 范围 **8.02–8.10**；五阶段按 NC→SCS→SCD→MCI→AD 排列，三票 % 在 Cohort1 为 8.09 / 8.04 / 8.09 / 8.08 / 8.10，在 Cohort3 为 8.02 / 8.06 / 8.07 / 8.05 / 8.07，**无单调趋势，组间差异 < 0.1 个百分点**。
- 各组"三票 / 两票"比值均在 31.3%–31.7%，与全局 32.46% 一致，说明 BERT 的再筛在各组间是同质的。

### 1.3 输出文件清单

```
/home/w24e/c_AMPs-prediction/
├── amp_results/results/
│   ├── amp_summary.tsv                          # 上表（机器可读）
│   ├── amp_all_peptides.tsv                     # 全部 4.3 亿条记录：cohort group name seq len att lstm bert n_votes is_AMP2 is_AMP is_AMP_flex
│   └── <Cohort>/<group>/aggregated_results.tsv  # 每组明细（列见下）
├── amp_results/work/
│   ├── unique_seqs.txt                          # 1.60 亿唯一序列（C 序排序）——全部计算的“主键”
│   ├── keras_proba.tsv                          # att_prob \t lstm_prob，与 unique_seqs.txt 逐行对应
│   ├── bert_proba.tsv                           # bert_prob（未进 BERT 的为 NA），逐行对应
│   └── bert_needed.txt / bert_needed_proba.tsv  # 3,902 万两票序列及其 BERT 概率
└── amp2_fasta_export/
    ├── <Cohort>/<group>.amp2.fa                 # 每组两票候选 FASTA（header = 原 sORF 名）
    └── unique_amp2.fa                           # 跨组去重两票序列（即 BERT 输入）
```

`aggregated_results.tsv` 列定义：`name, seq, len, att_prob, lstm_prob, bert_prob, n_votes(0–3), is_AMP(三票), AMP_pred(=is_AMP), is_AMP_flex(≥2 票，级联下为下界), is_AMP2(Attention & LSTM 两票)`。

提取某组最终三票 AMP 的 FASTA：

```bash
awk -F'\t' 'NR>1 && $8==1 {print ">"$1"\n"$2}' \
  amp_results/results/Cohort4_Full476_NCvsAD/Cohort4_Disease_AD/aggregated_results.tsv > Cohort4_AD.amp3.fa
```

---

## 二、方法（详细）

### 2.1 数据来源与分组

1. **原始数据**：476 例受试者粪便宏基因组，组装并分箱得到 MAG；对 MAG 预测 sORF（≤ 50 aa 的小开放阅读框），跨样本去重得到非冗余 sORF 目录 `final_sORF_Catalog.unique.fa`（约 33 GB）。
2. **样本分层**：临床分期五阶段 NC（认知正常）、SCS（主观认知下降前期/subjective cognitive symptoms）、SCD（主观认知下降）、MCI（轻度认知障碍）、AD；另按年龄/性别匹配挑出 265 例作为匹配子集。
3. **四个比较维度、14 个分组**（`amp_pipeline/build_grouped_sorf_fasta.py`）：通过 `MAG → Sample` 与 `Sample → Stage/Is_Matched_265` 两张映射表，把每条 sORF 按其来源 MAG 所属样本归入分组；一条 sORF 若出现在多个样本的 MAG 中，会同时进入多个组（因此 14 组记录总数 4.31 亿 > 唯一序列 1.60 亿）。
   - Cohort1：匹配 265 例 × 五阶段；Cohort2：匹配 265 例 × NC vs AD
   - Cohort3：全部 476 例 × 五阶段；Cohort4：全部 476 例 × NC vs AD

### 2.2 预测模型

采用 Ma Y. et al. *Identification of antimicrobial peptides from the human gut microbiome using deep learning*, **Nature Biotechnology** 2022, 40: 921–931 公开发布的三个预训练分类器（GitHub `mayuefine/c_AMPs-prediction`），**原样使用，不做再训练/微调**。

| 模型 | 文件 | 架构 | 输入编码 | 运行框架 |
|---|---|---|---|---|
| Attention | `Models/att.h5` | Embedding → BiLSTM → Attention → Dense(sigmoid) | 20 种标准氨基酸编码为整数 1–20，左侧补 0 至 300 位 | Keras 2.2.4 / TensorFlow-GPU 1.14 / CUDA 10.0 / cuDNN 7.6 |
| LSTM | `Models/lstm.h5` | Embedding → LSTM → Dense(sigmoid) | 同上 | 同上 |
| BERT | `Models/bert.bin`（MD5 `990d14de053d8080fcca33d712d647b6`） | BERT-base（12 层、768 维、12 头）+ 线性分类头，bert-sklearn 封装微调 | 氨基酸逐字母以空格分隔作为 token（均在 bert-base-uncased 词表内），`[CLS] … [SEP]`，max_seq_length 52 | PyTorch 1.10 / bert-sklearn 0.2.0 / pytorch-pretrained-bert 0.6.1 |

三个模型各输出"该序列为 AMP"的概率。**判定规则与原文一致：三个模型概率均 > 0.5 判为候选 AMP**（`is_AMP=1`）。同时记录 `is_AMP2`（Attention 与 LSTM 两票）与 `n_votes`（三模型中 > 0.5 的个数）供敏感性分析。

### 2.3 "去重—预测—回填"策略

14 组之间样本高度重叠（Cohort2 ⊂ Cohort1，Cohort4 ⊂ Cohort3，且同一 sORF 出现在多个样本），若逐组预测需重复计算 4.31 亿条。为保证**相同序列在所有组中概率完全一致**并节省 63% 算力，采用三步法（`amp_pipeline/run_unique_pipeline.sh`）：

1. **全局去重**：抽取 14 组全部序列，统一大写，`sort -u`（磁盘归并排序，`-S 40%` 限内存）→ 160,215,813 条唯一序列 `unique_seqs.txt`。
2. **唯一序列预测**（2.4 节）。
3. **回填**：每组 FASTA 按序列 `join` 到概率表，恢复原始顺序，生成 `aggregated_results.tsv`；由此统计每组 `n_AMP2 / n_AMP3` 及占比。回填条数与输入条数逐组核对相等。

### 2.4 级联预测与加速实现

**级联（strict 模式）**：BERT 单条推理成本约为 Keras 模型的 30–50 倍。由于最终判定要求三模型**同时** > 0.5，只对 Attention 与 LSTM 都 > 0.5 的序列运行 BERT，得到的三票结果与全量运行 BERT **数学上完全相同**；未进入 BERT 的序列 `bert_prob` 记 NA，其 `is_AMP` 必为 0。

```
1.60 亿唯一序列 ─Attention+LSTM(全量)→ 3,902 万两票序列 ─BERT→ 1,267 万三票 AMP
```

**Keras 步骤**（`script/predict_keras_unique.py`）：
- 在 Python 内直接把序列编码为 (N, 300) 整数矩阵，编码规则与原 `format.pl` 逐位一致（抽样比对概率相同），避免原流程生成数百 GB CSV 中间文件。
- 两模型加载一次，50,000 条/块流式预测，`batch_size=1024`，输出与 `unique_seqs.txt` 逐行对应的 `att_prob\tlstm_prob`；支持断点续跑。

**BERT 步骤**（`script/predict_bert_unique.py`）：
- 从 `bert.bin` 恢复 bert-sklearn 模型后直接调用其内部网络推理，绕过 sklearn 逐条 DataLoader 开销。
- 分词与原版一致；用原 `prediction_bert.py` 对 5 条对照肽（magainin-2、melittin、aurein 1.2 为阳性；一段信号肽为阴性；RW 重复肽）比对，概率差异 < 0.01（如 magainin-2：0.9966 vs 0.9964；信号肽：0.00012 vs 0.00013）。
- 加速：FP16 半精度；按长度排序后动态 padding（长度分桶）；`max_seq_length=52`（50 aa + CLS/SEP，零截断）；GTX 1650 上 batch 512，RTX A4000 上 batch 2048；支持断点续跑。

### 2.5 计算环境与耗时

| 步骤 | 硬件 | 软件环境 | 数据量 | 吞吐 | 耗时 |
|---|---|---|---|---:|---:|
| 分组建库 | HPC（SLURM） | Python 3 | 33 GB 目录 → 14 组 | — | ~2 h |
| 全局去重 | 笔记本 WSL2（i5-10200H, 16 GB） | coreutils sort | 4.31 亿 → 1.60 亿 | — | ~1 h |
| Attention + LSTM | **GTX 1650 (4 GB)**，WSL2 | conda `camps-tf114`：Py 3.6, TF-GPU 1.14, Keras 2.2.4, CUDA 10.0, h5py 2.10 | 1.60 亿 | 9,718 条/s | 4.6 h |
| BERT | **RTX A4000 (16 GB)**，WSL2 | conda `py36`：Py 3.6, PyTorch 1.10+cu111, bert-sklearn 0.2.0 | 3,902 万 | 3,550 条/s | 3.1 h |
| 回填 + 汇总 | 笔记本 WSL2 | sort / join / awk | 14 组 4.31 亿条 | — | 1.6 h |

对照：同一 BERT 任务在 GTX 1650 上实测约 100 条/s（需 4.5 天），故迁移至 A4000（提速 35 倍）。

### 2.6 质量控制

- 行数守恒：`unique_seqs.txt` = `keras_proba.tsv` = `bert_proba.tsv` = 160,215,813 行；各组回填条数 = 输入条数（14/14 通过）。
- 跨机器一致性：A4000 上的 BERT 输入与主机按同一规则重建的两票集合逐行 `cmp` 一致后才合并。
- 模型完整性：`bert.bin` MD5 校验通过；`att.h5/lstm.h5` 加载并前向成功；GPU 自检 3/3 通过。
- 编码等价性：快速编码/分词均与原作者脚本抽样比对一致。

### 2.7 可复现脚本

| 脚本 | 作用 |
|---|---|
| `amp_pipeline/setup_envs.sh` | 一键创建 `camps-tf114` 与 `py36` 环境 |
| `amp_pipeline/test_gpu.sh` / `test_models.sh` | GPU 与三模型自检 |
| `amp_pipeline/build_grouped_sorf_fasta.py` | 服务器端按四维度分组建库 |
| `amp_pipeline/run_unique_pipeline.sh <grouped_dir> <out_dir>` | 去重 → Keras → BERT（级联）→ 回填 → 汇总；每步 `.done` 可续跑 |
| `amp_pipeline/extract_amp2_fasta.sh` | 导出每组两票 FASTA + 跨组去重集 |
| `amp_pipeline/run_bert_remote.sh` / `import_bert_remote.sh` | 在另一台 GPU 机器跑 BERT 并合并回主流程 |
| `amp_pipeline/METHODS_AMP_prediction.md` | 英文方法段落（论文用） |

---

## 三、论文方法段落（中文，可直接改写）

**抗菌肽预测。** 采用 Ma 等（Nat Biotechnol 2022）公开的三个深度学习分类器——基于注意力机制的双向 LSTM 模型、LSTM 模型和微调的 BERT 模型——对 sORF 进行候选抗菌肽（AMP）预测，模型均原样使用、未做再训练。将四个队列共 14 个比较组的 sORF（4.31 亿条记录）合并并全局去重，得到 160,215,813 条唯一序列，保证每条序列只被打分一次且在各组间概率一致。序列编码与原流程一致：Keras 模型采用氨基酸整数编码并左补零至 300 位；BERT 模型以空格分隔的单个氨基酸为 token，使用 bert-base-uncased 词表，最大序列长度 52。Attention 与 LSTM 模型在全部唯一序列上运行（TensorFlow 1.14，GTX 1650）；BERT 模型以 FP16 精度和按长度排序的动态批处理，在两个 Keras 模型概率均 > 0.5 的 39,017,936 条序列上运行（PyTorch 1.10，RTX A4000）——在"三模型共识"判定规则下，该级联策略与全量运行 BERT 的结果完全等价。三个模型概率均 > 0.5 的序列判定为候选 AMP，随后将每条唯一序列的概率回填至各组的全部记录。加速后的推理代码与原作者脚本在对照肽上的概率差异 < 0.01。最终 12,665,622 条唯一序列（7.9%）被判定为候选 AMP，各组候选 AMP 占该组 sORF 的 8.02%–8.10%。

---

## 四、为什么各组几乎没有差异？该怎么办？

### 4.1 这不是模型出错，而是这个指标本身"看不见"疾病信号

"候选 AMP 占该组 sORF 的比例"衡量的是**序列空间的组成**，而非**生物学状态**。它几乎必然组间一致，原因有三：

1. **各组序列高度重叠。** 同一条 sORF 只要出现在任一 AD 样本和任一 NC 样本的 MAG 中，就同时进入 AD 组和 NC 组。人群核心菌群共享，导致各组 sORF 集合的交集极大——1.60 亿唯一序列对应 4.31 亿条记录，平均每条序列出现在 2.7 个组中。集合几乎相同，比例自然相同。
2. **分类器判定的是"序列像不像 AMP"，与来源无关。** 这是序列内在属性；只要 sORF 的整体组成（长度分布、氨基酸频率、来源菌门）在各组间相似，AMP 样序列的比例就相似。模型是对每条序列独立打分的，组间一致恰恰说明它**稳定、没有批次效应**。
3. **样本量放大器效应。** 每组 2,000–5,000 万条序列，任何微小的系统性差异都会被平均掉；三票 % 的组间波动 < 0.1 个百分点，属于抽样噪声量级。

类比：比较 AD 与 NC 患者的**基因组**中"编码蛋白的基因比例"——两者都是约 1.5%，但这不说明 AD 与基因无关；差异在于**哪些基因表达、表达多少**。

### 4.2 差异应该在"哪些 AMP、多少量、多少人"上找

现在手里已经有完整的候选 AMP 名单（1,267 万条唯一序列）和每条序列出现在哪些组的记录，接下来做**肽段级/家族级的差异分析**，而不是组级比例：

**（a）存在/缺失（prevalence）分析——最直接、不需要新数据**
- 把 `MAG_Sample_Mapping` 追溯回来，得到每条候选 AMP 在**每个样本**中是否存在的 0/1 矩阵（476 样本 × N 个 AMP）。
- 每个 AMP 做 AD vs NC 的 Fisher 精确检验（或按年龄/性别校正的 logistic 回归），BH 校正，找出**AD 特有 / AD 缺失**的 AMP；五阶段用 Cochran–Armitage 趋势检验。
- 先把 1,267 万条按 ≥ 90% 相似度聚类（`mmseqs easy-cluster` 或 CD-HIT），聚成"AMP 家族"，把 N 从千万级降到几十万，统计功效和可解释性都大幅提高。

**（b）丰度分析——最有说服力**
- 目前只知道"某 AMP 的编码 sORF 在某样本的 MAG 里"，不知道**丰度**。把每个样本的宏基因组 reads 回帖到候选 AMP 编码序列（或它们所在的 contig），得到 RPKM/TPM 丰度矩阵，再用 MaAsLin2 / ANCOM-BC / LinDA 做差异丰度分析。
- 也可以用 CoverM（你机器上有 `coverm` 环境）对 MAG 定量，把 AMP 的丰度用其宿主 MAG 的丰度代理。

**（c）宿主/来源分析**
- 差异 AMP 的宿主 MAG 属于哪些菌（GTDB-Tk 注释已有环境 `gtdbtk`）；AD 组是否丢失了某些产 AMP 的共生菌（如 *Faecalibacterium*、*Roseburia*），或富集了某些携带特定 AMP 的菌。这条线与已发表的 AD 菌群失调证据能直接对接。

**（d）功能/理化特征分析**
- 对差异 AMP 计算电荷、疏水性、两亲性等，比较 AD 富集与 NC 富集 AMP 的特征分布；预测靶标（革兰阳性/阴性、抗真菌）与可能的宿主效应。

### 4.3 关于"宏蛋白组处理后再比较"

宏蛋白组（metaproteomics）能回答"**这些 AMP 到底有没有被翻译出来**"，是从预测走向证据的关键一步，非常值得做，但它是**验证层**，不是缩小候选的第一步：

- **可行性**：以 1,267 万条候选 AMP 序列构建自定义数据库，用 MaxQuant / FragPipe / DIA-NN 搜库。sORF 编码的小肽在质谱中检出率本来就低（分子量小、胰酶位点少、丰度低），而且数据库越大 FDR 控制越难。因此**必须先用 (a)(b) 把候选缩到几百到几千条差异 AMP**，再构建小数据库去搜宏蛋白组，检出概率才有意义。
- **样本**：需要同一批粪便样本的蛋白组数据；若没有，可以挑差异最显著的 AD/NC 各 10–20 例补做。
- **另一条验证线**：宏转录组（有 RNA-seq 就能做，灵敏度远高于蛋白组），可以证明 sORF 被转录；再往下就是合成 top 差异 AMP 做体外抑菌实验。

### 4.4 建议的下一步顺序

1. **AMP 聚类**（1 天）：`mmseqs easy-cluster unique_amp3.fa --min-seq-id 0.9 -c 0.8` → 家族代表序列。
2. **样本级存在/缺失矩阵 + 差异检验**（2–3 天）：直接用现有 `MAG_Sample_Mapping.tsv` 和 `aggregated_results.tsv`，不需要 GPU，我可以把脚本写好通过 `code/job.sh` 在你机器上跑。
3. **reads 回帖定量 + 差异丰度**（1–2 周，需原始 fastq，在 HPC 上跑）。
4. **差异 AMP 的宿主注释与功能特征**（几天）。
5. **宏转录组/宏蛋白组验证 + 合成验证**（后续）。

第 1–2 步做完就能回答"AD 患者肠道是否缺失/富集特定 AMP"，这才是论文的核心图。
