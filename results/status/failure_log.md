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

## round 9（2026-09-23）：v2 的 A/B 与 watchdog 有 bug，远程叫停后重开

**发现方式**：watchdog 第一次进度回传（15 min）即暴露问题 —— 进度回传机制本身立功。

**bug 1（A 采样切碎 FASTA）**：`awk 'NR%k==1' uniq.fa` 按**行**采样，把双行 FASTA
切成 header/序列错位的碎片。证据：子样本 197900“序列”聚出 395801 个家族
（家族数 = 行数 ≈ 序列数 2 倍）。修：按记录采样 `/^>/{n++} n%k==1`，序列数用 `grep -c '^>'`。

**bug 2（B max-seqs 截断 self-hit）**：`--max-seqs 1` 在 prefilter 阶段就截断，
低复杂度短肽的海量 k-mer 命中把 self 淹没。证据：self 搜索 onlyAD→onlyAD 仅 67% 命中、
both→both 仅 40%（越短/越 R-rich 的集合漏检越多）。修：`--max-seqs 300` + 每 query 取第一行（best）。

**bug 3（watchdog CPU 负值 + 单次误杀）**：树总 CPU 时间在子进程退出时会下降，
`dcpu` 变负（回传里 -803%、-1661%）；stall 条件“单次 cpu<5%”遇上 C 聚类全程无日志
（mmseqs 输出被 `>/dev/null` 丢掉），17:35 后随时可能误杀。修：`dcpu=max(0,…)` +
连续 3 次 idle 才杀 + C 的 mmseqs `-v 1` 进度进日志（长步骤必须有心跳）+ 聚类前清 tmpdir。

**决策**：不停等误杀，主动远程叫停（`cancel_request.txt`，验证 remote_cancel_check 实战），
修完重开 round 10（C 只损失十几分钟；job.sh 开头删 round 9 的错误 A/B 产物，work/ 索引保留）。
