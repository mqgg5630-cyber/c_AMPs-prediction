# 宏基因组 sORF 抗菌肽 (AMP) 三模型预测 —— 方法与结果

> 数据：4 个队列 / 14 个分组，共 4.31 亿条 sORF 记录，1.60 亿条唯一序列
> 完成日期：2026-09-13

---

## 1. 结果总览

| 队列 | 分组 | 输入 sORF 数 | 两票 (Att & LSTM) | 两票 % | **三票 (Att & LSTM & BERT)** | **三票 %** |
|---|---|---:|---:|---:|---:|---:|
| Cohort1_Matched265_5Stage | Cohort1_AD  | 24,822,428 | 6,433,553 | 25.92 | **2,010,251** | **8.10** |
| Cohort1_Matched265_5Stage | Cohort1_MCI | 18,372,512 | 4,749,949 | 25.85 | **1,483,763** | **8.08** |
| Cohort1_Matched265_5Stage | Cohort1_NC  | 23,356,299 | 6,003,623 | 25.70 | **1,888,741** | **8.09** |
| Cohort1_Matched265_5Stage | Cohort1_SCD | 23,822,480 | 6,124,753 | 25.71 | **1,927,898** | **8.09** |
| Cohort1_Matched265_5Stage | Cohort1_SCS | 22,367,879 | 5,739,579 | 25.66 | **1,798,519** | **8.04** |
| Cohort2_Matched265_NCvsAD | Cohort2_Disease_AD | 24,822,428 | 6,433,553 | 25.92 | **2,010,251** | **8.10** |
| Cohort2_Matched265_NCvsAD | Cohort2_Healthy_NC | 23,356,299 | 6,003,623 | 25.70 | **1,888,741** | **8.09** |
| Cohort3_Full476_5Stage | Cohort3_AD  | 52,971,582 | 13,469,017 | 25.43 | **4,276,575** | **8.07** |
| Cohort3_Full476_5Stage | Cohort3_MCI | 42,524,471 | 10,788,969 | 25.37 | **3,422,342** | **8.05** |
| Cohort3_Full476_5Stage | Cohort3_NC  | 27,378,997 | 6,982,534 | 25.50 | **2,197,149** | **8.02** |
| Cohort3_Full476_5Stage | Cohort3_SCD | 37,345,907 | 9,509,040 | 25.46 | **3,015,354** | **8.07** |
| Cohort3_Full476_5Stage | Cohort3_SCS | 33,124,222 | 8,451,627 | 25.51 | **2,668,215** | **8.06** |
| Cohort4_Full476_NCvsAD | Cohort4_Disease_AD | 52,971,582 | 13,469,017 | 25.43 | **4,276,575** | **8.07** |
| Cohort4_Full476_NCvsAD | Cohort4_Healthy_NC | 27,378,997 | 6,982,534 | 25.50 | **2,197,149** | **8.02** |

全局层面 (唯一序列)：

| 阶段 | 唯一序列数 | 占比 |
|---|---:|---:|
| 去重后的全部 sORF | 160,215,813 | 100% |
| Attention > 0.5 且 LSTM > 0.5 (进入 BERT) | 39,017,936 | 24.4% |
| **三模型均 > 0.5 (最终候选 AMP)** | **12,665,622** | **7.9%** |

- 最终候选 AMP 定义：**Attention、LSTM、BERT 三个模型的概率都 > 0.5**（原文默认判定规则）。
- 各组三票通过率高度一致 (8.02%~8.10%)，组间差异极小；AD vs NC 差异需在**丰度/流行率层面**（而非候选肽比例）进一步分析。
- Cohort2 与 Cohort1 的 AD/NC、Cohort4 与 Cohort3 的 AD/NC 是相同样本子集，数字相同属预期。

### 输出文件

```
amp_results/results/
├── amp_summary.tsv                         # 上表 (14 组汇总)
├── amp_all_peptides.tsv                    # 全部记录: cohort group name seq len att lstm bert n_votes is_AMP2 is_AMP is_AMP_flex
├── README_cascade.txt                      # 级联模式说明
└── <Cohort>/<group>/aggregated_results.tsv # 每组明细, 列: name seq len att_prob lstm_prob bert_prob n_votes is_AMP AMP_pred is_AMP_flex is_AMP2
amp_results/work/
├── unique_seqs.txt      # 1.60 亿唯一序列 (C 序排序)
├── keras_proba.tsv      # 每行 att_prob \t lstm_prob, 与 unique_seqs.txt 逐行对应
├── bert_proba.tsv       # 每行 bert_prob (未进入 BERT 的为 NA), 与 unique_seqs.txt 逐行对应
└── bert_needed.txt / bert_needed_proba.tsv   # 3,902 万两票序列及其 BERT 概率
amp2_fasta_export/<Cohort>/<group>.amp2.fa     # 每组两票候选 FASTA (header = 原 sORF 名)
amp2_fasta_export/unique_amp2.fa               # 跨组去重的两票序列 (BERT 输入)
```

提取最终三票 AMP 的 FASTA (每组)：

```bash
awk -F'\t' 'NR>1 && $8==1 {print ">"$1"\n"$2}' \
    amp_results/results/Cohort2_Matched265_NCvsAD/Cohort2_Disease_AD/aggregated_results.tsv > Cohort2_AD.amp3.fa
```

---

## 2. 方法

### 2.1 预测模型

使用 Ma et al. (2022, *Nature Biotechnology* 40:921–931, "Identification of antimicrobial peptides from the human gut microbiome using deep learning") 公开的三个预训练模型 (GitHub: mayuefine/c_AMPs-prediction)，**未做任何再训练或微调**：

| 模型 | 文件 | 架构 | 输入编码 | 运行框架 |
|---|---|---|---|---|
| Attention | `Models/att.h5` | Embedding + BiLSTM + Attention | 20 种标准氨基酸 → 整数 1–20，左侧补 0 至 300 列 | Keras 2.2.4 / TensorFlow-GPU 1.14 / CUDA 10.0 |
| LSTM | `Models/lstm.h5` | Embedding + LSTM | 同上 | 同上 |
| BERT | `Models/bert.bin` | BERT-base (12 层, 768 维) 微调的序列分类器 (bert-sklearn 封装) | 氨基酸逐字母以空格分隔，作为 WordPiece token；`[CLS] a a … [SEP]`，max_seq_length 52 | PyTorch 1.10 / bert-sklearn 0.2.0 |

每个模型输出该序列为 AMP 的概率。**判定规则与原文一致：三个模型概率均 > 0.5 判为候选 AMP** (`is_AMP = 1`)。同时保留：`is_AMP2` (Attention & LSTM 两票)、`n_votes` (三模型中 >0.5 的个数)。

模型完整性校验：`bert.bin` MD5 = `990d14de053d8080fcca33d712d647b6`。

### 2.2 输入数据

- 来源：非冗余 sORF catalog，按 4 个对照维度切分为 14 个分组 FASTA (`comparable_sorf_grouped_catalog/<Cohort>/<group>.fa`)：
  - Cohort1：年龄/性别匹配 265 例，5 阶段 (NC / SCS / SCD / MCI / AD)
  - Cohort2：同 265 例，NC vs AD
  - Cohort3：全部 476 例，5 阶段
  - Cohort4：全部 476 例，NC vs AD
- 序列长度 ≤ 50 aa (sORF 定义)。含非标准氨基酸字母 (B/J/O/U/X/Z 等) 的序列按原文 `format.pl` 的做法不予预测，概率记 NA (本数据集为 0 条)。

### 2.3 去重一次预测策略

14 组间样本大量重叠 (Cohort2 ⊂ Cohort1、Cohort4 ⊂ Cohort3 等)，直接按组预测会重复计算 4.31 亿条。为保证**相同序列在所有组中获得完全一致的概率**并节省算力，采用「去重—预测—回填」三步：

1. **全局去重**：抽取 14 组全部序列，统一大写，`sort -u` (磁盘归并排序) 得到 160,215,813 条唯一序列。
2. **唯一序列预测** (见 2.4)。
3. **回填**：按序列做 `join`，把三个概率写回每组每条记录，还原原始顺序，生成 `aggregated_results.tsv`；由此统计每组 `n_AMP2 / n_AMP3`。

去重与回填全部使用流式工具 (`sort/join/awk`)，内存占用受 `-S` 参数限制，可在 16 GB 笔记本上完成。

### 2.4 级联预测

BERT 单条推理成本约为 Keras 模型的 30–50 倍。因最终判定要求三模型**同时** >0.5，只对 Attention 与 LSTM 都 >0.5 的序列运行 BERT 即可得到与全量运行**完全相同**的三票结果 (级联 `strict` 模式)：

```
1.60 亿唯一序列 ──Attention + LSTM (全量)──▶ 3,902 万两票序列 ──BERT──▶ 1,267 万三票 AMP
```

未进入 BERT 的序列 `bert_prob` 记 NA，它们的 `is_AMP` 必为 0，不影响结论。

**Keras 步骤 (Attention + LSTM)** — `script/predict_keras_unique.py`

- 在 Python 内直接生成 (N, 300) 整数矩阵，编码规则与原 `format.pl` 逐位一致 (已用原脚本抽样对照，概率相同)，避免生成数百 GB CSV 中间文件。
- 两个模型加载一次，按 50,000 条一块流式预测，`batch_size = 1024`，输出与 `unique_seqs.txt` 逐行对应的 `att_prob \t lstm_prob`。
- 支持断点续跑 (按已写出行数跳过)。

**BERT 步骤** — `script/predict_bert_unique.py`

- 从 `bert.bin` 恢复 bert-sklearn 模型，直接调用其内部 `BertPlusMLP` 网络做推理，跳过 sklearn 逐条 DataLoader 的开销。
- 分词与 bert-sklearn 完全一致 (氨基酸字母均在 bert-base-uncased 词表中为单 token)；已用原 `prediction_bert.py` 对照 5 条已知 AMP/非 AMP (magainin-2、melittin、aurein 1.2、信号肽、RW 重复肽)，两者概率差异 < 0.01。
- 加速手段：FP16 半精度；按序列长度排序后动态 padding (长度分桶，避免统一 pad 到 max_len)；`max_seq_length = 52` (50 aa + [CLS]/[SEP]，零截断)；`batch_size` 1650 上 512、A4000 上 2048。
- 支持断点续跑。

### 2.5 计算环境与耗时

| 步骤 | 硬件 | 软件环境 | 数据量 | 吞吐 | 耗时 |
|---|---|---|---|---|---|
| 去重 | 笔记本 (WSL2, 16 GB) | coreutils sort | 4.31 亿 → 1.60 亿 | — | ~1 h |
| Attention + LSTM | **GTX 1650** (4 GB), WSL2 | conda `camps-tf114`: Python 3.6, TF-GPU 1.14, Keras 2.2.4, CUDA 10.0, cuDNN 7.6, h5py 2.10 | 1.60 亿 | 9,718 条/s | 4.6 h |
| BERT | **RTX A4000** (16 GB), WSL2 | conda `py36`: Python 3.6, PyTorch 1.10 + CUDA 11.1, bert-sklearn 0.2.0, pytorch-pretrained-bert 0.6.1 | 3,902 万 | 3,550 条/s | 3.1 h |
| 回填 + 汇总 | 笔记本 | sort / join / awk | 14 组, 4.31 亿条 | — | 1.6 h |

参考：同样的 BERT 任务在 GTX 1650 上实测 ~100 条/s，需约 4.5 天，故迁移到 A4000。

### 2.6 质量控制

- 每步产物行数与输入严格核对 (`unique_seqs.txt` = `keras_proba.tsv` = `bert_proba.tsv` = 160,215,813 行；各组回填条数 = 输入条数)。
- 跨机器传输的 BERT 输入与主机按同一规则重建的两票集合逐行 `cmp` 一致后才合并。
- BERT 概率分布：min 1.1e-4，P50 0.11，P90 0.97，max 0.9996；32.5% 的两票序列 >0.5，与对照肽打分行为一致。
- 序列长度分布 (两票序列)：中位数 11 aa，P90 27，P99 46，最大 50。

### 2.7 可复现性

全部脚本位于仓库 `amp_pipeline/` 与 `script/`：

| 脚本 | 作用 |
|---|---|
| `setup_envs.sh` | 一键创建 `camps-tf114` 与 `py36` 两个 conda 环境 |
| `test_gpu.sh` / `test_models.sh` | GPU 与三个模型加载自检 |
| `run_unique_pipeline.sh <grouped_dir> <out_dir>` | 去重 → Keras → BERT (级联) → 回填 → 汇总；每步有 `.done` 标记，可中断续跑；`BERT_CASCADE=skip/strict/any/0` 控制级联 |
| `extract_amp2_fasta.sh` | 导出每组两票 FASTA 与跨组去重集 |
| `run_bert_remote.sh` | 在另一台 GPU 机器上单独跑 BERT (含 bench 模式与断点续跑) |
| `import_bert_remote.sh` | 把远端 BERT 结果校验后合并回主流程并重新回填 |
| `stage_local_bert_base.sh` | 将 bert-base-uncased 词表/配置/权重置于本地，加载免联网 |

核心复现命令：

```bash
bash amp_pipeline/setup_envs.sh all
bash amp_pipeline/run_unique_pipeline.sh ~/data/comparable_sorf_grouped_catalog amp_results   # 单机全流程
# 或分机: 主机 BERT_CASCADE=skip 跑 Keras → extract_amp2_fasta.sh → 远端 run_bert_remote.sh → 主机 import_bert_remote.sh
```

---

## 3. 方法部分（论文用，可直接改写）

**Antimicrobial peptide prediction.** Candidate AMPs were predicted from sORF sequences using the three deep-learning classifiers released by Ma et al. (Nat Biotechnol 2022): an attention-based BiLSTM model, an LSTM model, and a fine-tuned BERT model, all used as-is without retraining. sORFs from the 14 comparison groups (four cohorts; 431 million records) were pooled and de-duplicated to 160,215,813 unique sequences so that each sequence was scored exactly once. Sequences were encoded as in the original pipeline (integer-encoded amino acids, left-padded to 300 positions for the Keras models; space-separated residues tokenised with the bert-base-uncased vocabulary for BERT, maximum sequence length 52). The attention and LSTM models were run on all unique sequences (TensorFlow 1.14, GTX 1650); the BERT model was run in FP16 with length-sorted dynamic batching on the 39,017,936 sequences scored > 0.5 by both Keras models (PyTorch 1.10, RTX A4000), which yields results identical to exhaustive scoring under the consensus rule. A sequence was called a candidate AMP when all three models returned a probability > 0.5. Per-sequence probabilities were then mapped back to every record in each group. Equivalence of the accelerated inference code with the original scripts was verified on control peptides (maximum absolute probability difference < 0.01). Overall, 12,665,622 unique sequences (7.9%) were classified as candidate AMPs, corresponding to 8.02–8.10% of sORFs in each group.
