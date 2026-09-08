# 全局去重 + strict 三票级联预测

`run_unique_cascade_pipeline.sh` 面向四个分组目录，避免每组重复计算同一条 sORF：

1. 用 `sORF_All_Total.fa` 作为全局唯一 catalog（没有该文件时从分组 FASTA 建立唯一索引）；
2. Attention 和 LSTM 对全局唯一序列各运行一次；
3. 默认 `strict` 只将 `att > 0.5 且 lstm > 0.5` 的序列交给 BERT；
4. BERT 结果按原始 FASTA header 回填到每个分组；
5. 用仓库原有 `result.pl` 生成三票 `final_prediction.txt`。

`strict` 对“三个模型均 > 0.5”的结果是精确的，因为不满足前两个条件的序列不可能成为三票。它不提供未送入 BERT 序列的准确两票统计。

## 先做本机测速/ETA

```bash
MAX_UNIQUE=10000 bash amp_pipeline/run_unique_cascade_pipeline.sh \
  ~/data/comparable_sorf_grouped_catalog amp_results_bench bench
```

bench 会真正加载模型并运行 10,000 条（可改 `MAX_UNIQUE`），打印当前机器实测速率、strict 候选数量和候选比例。它只用于估算，不生成正式回填结果。

## 正式运行

```bash
nohup bash amp_pipeline/run_unique_cascade_pipeline.sh \
  ~/data/comparable_sorf_grouped_catalog amp_results strict \
  > run_unique.log 2>&1 &

tail -f run_unique.log
```

日志会打印：唯一序列数、Attention/LSTM 阶段估算小时数、strict 候选数和比例、BERT 阶段估算小时数以及最终总耗时。输出位于 `amp_results/cascade_results/`，中间文件位于 `amp_results/.unique_cascade_work/`，可用于中断后续跑。

模式：

- `strict`（默认）：BERT 只跑 `att > 0.5 且 lstm > 0.5`，适合只要三票；
- `any`：BERT 跑 `att > 0.5 或 lstm > 0.5`，可准确统计至少两票；
- `all`：BERT 跑全部唯一序列。

脚本会从 `ENV_TF`、`ENV_BERT` 环境变量读取环境路径，也会自动查找 `camps-tf114` 和 `py36`。BERT 是否用 CUDA 由 `BERT_USE_CUDA=auto` 自动检测；必须安装 CUDA 版 PyTorch 才会真正使用显卡。
