# UniDL4BioPep 22 活性预测结果后处理

本目录提供针对 UniDL4BioPep 预测主循环（25 个 batch × Healthy / Periodontitis，22 个模型）的**后处理脚本**，不修改预测内核。

## 脚本

| 文件 | 用途 |
| :--- | :--- |
| `extract_multiact_hits.py` | 提取 **22 种活性概率全部 > 阈值**（默认 0.8）的肽段，输出 FASTA + 数量统计表 |
| `extract_single_activity_hits.py` | 指定数据集后，分别提取每个模型自身 **prob > 阈值** 的肽段，输出 22 个 FASTA + 统计表 |
| `extract_healthy_single_activity_hits.py` | 健康人组快捷入口，默认处理 `Healthy_Specific` 的 22 个模型 |
| `summarize_two_groups.py` | 将健康人组和牙周炎组结果整理成两张带命中率的汇总表 |

## 用法

```bash
python3 extract_multiact_hits.py \
    /home/wsh/UniDL4BioPep-main/Predictions_Results_With_Probability_20260604_204744
```

常用选项：

```bash
# 换阈值
python3 extract_multiact_hits.py <results_dir> --threshold 0.7

# 用 >= 阈值（默认是严格 >）
python3 extract_multiact_hits.py <results_dir> --inclusive

# 只跑某个数据集 / 输出到别处 / 不去重
python3 extract_multiact_hits.py <results_dir> \
    --datasets Healthy_Specific --outdir /path/to/out --no-dedup

# 大 CSV 建议使用分块读取（默认每次 100000 行），内存较小时可调小
python3 extract_multiact_hits.py <results_dir> --chunksize 50000
```

## 牙周炎组 / 健康人组：22 个模型分别提取

下面的脚本不是要求 22 个模型同时超过阈值，而是分别处理每个模型；每个模型生成一个
FASTA 和一个命中明细 CSV。牙周炎组默认是 `Periodontitis_Specific`：

```bash
python3 extract_single_activity_hits.py \
    /home/wsh/UniDL4BioPep-main/Predictions_Results_With_Probability_20260604_204744
```

健康人组使用快捷脚本：

```bash
python3 extract_healthy_single_activity_hits.py \
    /home/wsh/UniDL4BioPep-main/Predictions_Results_With_Probability_20260604_204744
```

也可以使用通用脚本显式指定：

```bash
python3 extract_single_activity_hits.py <results_dir> \
    --dataset Healthy_Specific
```

默认规则是每个模型自己的 `prob > 0.8`。输出目录为：

```text
<results_dir>/<dataset>_SingleActivity_gt0.8/
├── fasta/                       # 22 个模型各一个 FASTA
├── csv/                         # 22 个模型各一个命中明细 CSV
├── single_activity_summary.csv  # 22 个模型总数量
└── per_batch_counts.csv         # 每个 batch、每个模型数量

牙周炎组目录名为 `Periodontitis_Specific_SingleActivity_gt0.8`，健康人组目录名为
`Healthy_Specific_SingleActivity_gt0.8`。
```

默认保留每条满足条件的输入记录；如果希望每个模型按 sequence 去重：

```bash
python3 extract_single_activity_hits.py <results_dir> --dedup
```

内存较小时可调小分块大小：

```bash
python3 extract_single_activity_hits.py <results_dir> --chunksize 50000
```

## 两个组整理成两张汇总表

健康人组和牙周炎组都完成后，运行：

```bash
python3 summarize_two_groups.py \
    /home/wsh/UniDL4BioPep-main/Predictions_Results_With_Probability_20260604_204744
```

会生成：

```text
Healthy_Specific_model_summary_gt0.8.csv
Periodontitis_Specific_model_summary_gt0.8.csv
```

表格中包含每个模型的输入数、`prob > 0.8` 命中数、命中率和 FASTA 数量。

## 输入 / 输出

**输入**：`<results_dir>/Healthy_Specific/*_Predictions.csv` 与 `<results_dir>/Periodontitis_Specific/*_Predictions.csv`
（每个 CSV 需含 `sequence` 列和 22 个 `{活性名}_prob` 列；若某 batch 的模型预测失败导致 prob 列不足 22 个，该 batch 会在统计表里标记 `INCOMPLETE` 并跳过。）

**输出**（默认 `<results_dir>/MultiAct_Extraction_gt0.8/`）：

```
├── <dataset>_gt0.8_multiact.fasta      # 该数据集全量命中 FASTA（默认按序列去重，保留 min_prob 最高者）
├── <dataset>_gt0.8_multiact_hits.csv   # 命中明细：fasta_header / sequence / min_prob / source_batch
├── per_batch/<dataset>/<batch>_gt0.8.fasta
├── summary_count_table.csv             # 数量统计表：每个 (数据集, batch) 一行 + 汇总行
└── per_activity_hits_gt0.8.csv         # 每个活性单独的 prob>阈值 命中数
```

依赖：仅 `pandas`（其余为标准库）。
