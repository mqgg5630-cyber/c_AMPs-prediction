# 失败记录（只记教训，不记流水）

## round 8（2026-09-23）：v1 家族分析跑偏，手动叫停

**任务**：`amp_pipeline/group_specific_family.sh` —— mmseqs 90% 聚 1266 万三票 AMP → 家族层面 AD/NC 流行率 Fisher 检验。

**现象**（本机 `job_*.log`，16:15 起）：
- 解析 35,061,523 条三票记录，去重后 12,665,622 条唯一序列；
- `--min-seq-id 0.9` 聚出 **12,215,326 个家族，压缩比 1.0x** —— 等于没聚类；
- 所谓“MAG 计数”：Cohort1_AD 71,722 … Cohort4_Disease_AD 134,176。

**根因 1（分析设计错）：90% 同一性对短肽没有区分力。**
三票 AMP 中位长度 11 aa：1 个错配即 91%，2 个即 82% 被拆成两个家族。
短肽 + 高阈值 + 默认灵敏度 ⇒ 几乎每条序列自成一家，家族层面分析退化成精确序列层面，
v1 的“家族”结论全部无效。教训：**短肽聚类前必须先跑压缩比曲线标定阈值**（已纳入 v2-A）。

**根因 2（数据理解错）：sORF 名里没有 MAG/样本信息，流行率检验的列联表是错的。**
sORF 名形如 `k141_32419_170`（contig+ORF 编号），v1 正则切出来的所谓“MAG id”实际是
contig id。所谓“某家族在 N 个 MAG 中出现”实际是“在 N 条 contig 中出现”，
Fisher 检验的行（多少个独立生物学单位携带该家族）从定义上就是错的，p 值无意义。
教训：**做流行率/富集检验前，先确认 ID 的命名空间到底是什么**；样本级检验必须等服务器
导出 `sorf2mag.tsv`（清单见 v2-E `NEXT_STEPS_SERVER_FILES.md`）。

**根因 3（过程缺失）：Arena 侧无法远程叫停跑偏的任务，只能喊用户手动 kill。**
已修复（三层，见 `skills/git-sync/SKILL.md §13`）：
`code/job_watch.py` 看门狗（卡死/超时自动杀）+ `watch.sh remote_cancel_check`
（每 tick 即使 lock 被占也检查 `cancel_request.txt`，≤2 min 就地停任务）+ `watch.sh --kill` 本地急停。

**纠正**：round 9（v2）`amp_pipeline/group_specific_analysis2.sh` —— A 压缩比曲线标定阈值；
B 最近邻同一性（判断“特异”是否只是菌株变异）；C 家族层面重叠 + core14；
D 家族层面特征对比；E 服务器文件清单。不再做无 MAG 信息的 Fisher 检验。

## round 6（2026-09-23）：job  exit 0 但无产物

job 日志只落在本机、没推回仓库，Arena 侧无法判断。已修复：每轮清空旧 `job_*.log`、
`local_check.sh` 打印日志尾、job_watch 每 15 min 回传进度 + 日志。
