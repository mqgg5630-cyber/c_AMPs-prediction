# 差异化分析方案（v2 之后，约束：只有 14 组层面 presence，无样本级数据）

背景：v1（精确序列）显示 AD vs NC 共享仅 ~10%（Jaccard ~0.05），但极可能是组装/菌株噪音；
v1 家族版因阈值与 MAG 问题作废（见 `results/status/failure_log.md`）；v2（round 9 在跑）
回答“特异是真信号还是菌株变异”。下面是 v2 之后值得做的差异化分析，按价值排序，
**全部可在本机做，不需要服务器**。是否开 v3、开哪些，待 round 9 结果按文末决策点定，
不要抢跑打断 round 9。

## A. 跨队列一致性检验（最强证据，不需新数据）⭐

原理：如果 AD 特异 AMP 是真生物学信号，两个独立队列（Cohort1 matched-265 与
Cohort3 full-476）的 AD 特异集合应在家族层面**显著重叠**；若只是噪音，重叠 ≈ 随机期望。
这是没有样本级数据时最有说服力的“差异化”检验。

方法（v2 的 `fam_group.tsv` + 家族划分直接可算，不用重聚类）：
- 取 Cohort1 的 AD-only 家族集合 X（相对 Cohort1_NC 定义），Cohort3 的 AD-only 家族集合 Y
  （相对 Cohort3_NC 定义），算 |X∩Y| vs 超几何期望，fold enrichment + p 值；
- NC-only 同样做一遍；再交叉看 AD-only(X) vs NC-only(Y) 是否互斥（应不富集）；
- 在几个 FULL_ID 阈值下重复，看结论是否稳健。

判定：AD-only 跨队列显著富集（fold ≫ 1，p 极小）⇒ 存在可重复的 AD 相关 AMP 家族，
导出交集 FASTA 即候选清单；不富集 ⇒ “特异”基本是队列特异性噪音，结论转向“组间无实质差异”。

## B. 测序深度校正（必需的对照）

问题：各组 sORF 总量不同（如 AD 2482 万 vs NC 2335 万记录），“AD 特有序列更多”
可能只是采样更深。用 `shuf` 下采样到相同记录数（或 rarefy 到相同唯一序列数）后重算
特有/共享比例 + rarefaction 曲线，看结论是否翻转。3500 万行规模本机可行。

## C. k-mer / motif 层面差异（对短肽最友好的差异化）

不要求整条序列相同：统计 5-mer/6-mer 在 AD vs NC 全部三票 AMP 中的频率，
chi2/Fisher + BH，top 富集 k-mer 回标到序列，看是否落在核心家族/AD-only 家族。
优点：不依赖聚类阈值，对 11 aa 短肽敏感；缺点：解释时要回落到序列/家族。

## D. 长度分层（短肽 vs 长肽分开看）

原理：≤12 aa 的 exact-match“特异”基本不可信（随机碰撞 + 单点变异噪音），
≥20 aa 的可信得多。按长度 bin（≤10 / 11–15 / 16–25 / ≥26）分别算 AD/NC 共享率与 Jaccard：
若“特异性”随长度增加收敛到稳定值 ⇒ 长肽子集的结论可用；若各 bin 都一样低 ⇒ 全是噪音。

## E. 已知 AMP 数据库比对（外部验证）

核心家族 + AD-only/NC-only 家族代表序列 vs APD / DRAMP / CAMP
（`mmseqs easy-search` 短肽模式或 blastp-short），比较 AD-only vs NC-only 的已知 AMP 命中率。
数据库几十 MB，本机可下载。无论 v2 结论如何都值得做一次。

## F. 理化性质分布检验（v2-D 的加强版）

序列层面 AD vs NC：净电荷/疏水性/长度分布的 KS 检验 + Cliff's delta；
家族层面 v2-D 已有描述统计，补检验即可。预期差异小（v1 精确序列层面 δ<0.02），
主要起“排除混杂”（如 AD 特异只是更短/更带电）的作用。

## G. 服务器文件到位后的严格检验（不在本机做）

`sorf2mag.tsv` 到手 → 样本级 presence 矩阵 → 每家族 Fisher+BH、五阶段
Cochran–Armitage 趋势检验、logistic（校正队列 + 测序深度）。清单见 v2-E。

## 决策点（round 9 结果出来后）

- 若压缩比曲线在 id=0.6–0.7 有合理压缩（2–5x）⇒ 家族层面可用 ⇒ v3 做 **A + B**。
- 若 NN 同一性显示 onlyAD vs onlyNC 中位 >0.9 ⇒ “特异”≈菌株变异 ⇒
  结论转向“组间无实质差异”，v3 只做 **B + D** 作支撑，不再挖特异清单。
- **E** 无论如何做一次；**C** 视 A 的结果（若 A 不富集，C 是最后的灵敏度尝试）；**F** 顺手做。
- v3 脚本复用 v2 的 `work/`（all.tsv / uniq.fa / seq2fam），不动 round 9 产物。
