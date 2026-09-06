# UniDL4BioPep 22 活性预测结果后处理

本目录提供针对 UniDL4BioPep 预测主循环（25 个 batch × Healthy / Periodontitis，22 个模型）的**后处理脚本**，不修改预测内核。

## 脚本

| 文件 | 用途 |
| :--- | :--- |
| `extract_multiact_hits.py` | 提取 **22 种活性概率全部 > 阈值**（默认 0.8）的肽段，输出 FASTA + 数量统计表 |

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
