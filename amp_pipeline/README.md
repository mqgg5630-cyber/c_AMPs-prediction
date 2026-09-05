# 宏基因组 sORF 四队列分组建库 + 本地三模型 AMP 预测 + 汇总

本目录补充了你在 `c_AMPs-prediction` 主线流程之外的完整闭环：

1. **服务器端** (SLURM / /mnt/hpc)：把「非冗余 sORF Catalog」按四维度队列切分成**分组总 FASTA 文件夹**，方便整目录打包下载。
2. **本地端** (WSL / 你自己的机器)：对每个分组 FASTA 跑 Attention / LSTM / BERT 三个模型，并**汇总三模型投票**输出每个分组的 AMP 结果。

> 这套脚本只是**生成分组 FASTA** 与 **汇总预测**，不修改 `c_AMPs-prediction` 的预测内核；只修复了内核里一个会导致 LSTM 预测失败的路径拼写错误（`../Moldes/lstm.h5` → `../Models/lstm.h5`，见文末）。

---

## 0. 目录结构 / 产物一览

```
amp_pipeline/
├── build_grouped_sorf_fasta.py      # 【服务器端】四队列分组总 FASTA 生成
├── run_pipeline_one.sh              # 【本地】单个分组 FASTA 跑三模型并生成最终结论
├── run_pipeline_all_groups.sh       # 【本地】遍历所有分组 FASTA 跑三模型
└── aggregate_amp_results.py         # 【本地】汇总三模型概率 + 投票, 输出分组/全量/汇总表
```

---

## 1. 服务器端：生成「分组 + 不分组」总 FASTA

### 1.1 输入文件（都在 `sorf_pipeline` 目录下）

| 输入 | 来源 | 说明 |
| :--- | :--- | :--- |
| `sorf_output/final_sORF_Catalog.unique.fa` | 步骤一 去重后的非冗余 sORF 目录 | **不分组总库**。每条 Header 形如 `>sORF_MAGID_序号 [MAG=MAGID]` |
| `MAG_Sample_Mapping.tsv` | `build_mag_sample_mapping.py` | 长格式：`MAG` → `Sample` |
| `Sample_Group_Mapping.tsv` | `build_mapping.py` | 每样本的 `Stage` / `Sex` / `Age` / `Is_Matched_265` |

> 你已经在服务器上跑完了 `build_mapping.py` 和 `build_mag_sample_mapping.py`，所以后两个文件都在 `sorf_pipeline/` 下。

### 1.2 运行

```bash
cd /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline

python3 /path/to/amp_pipeline/build_grouped_sorf_fasta.py \
    --catalog  sorf_output/final_sORF_Catalog.unique.fa \
    --mag-sample MAG_Sample_Mapping.tsv \
    --meta      Sample_Group_Mapping.tsv \
    --outdir    sorf_grouped_catalog \
    --copy-total
```

- `--outdir sorf_grouped_catalog`：分组 FASTA 全部放在这一个文件夹里，**整目录打包下载**（见第 2 节）即可。
- `--copy-total`：把总库做成真实拷贝（而非硬链接）。

> **关于 MAG id 匹配（重要）**：脚本会自动把 Catalog header 的 `[MAG=...]` 与 `MAG_Sample_Mapping.tsv` 的 `MAG_File` 两端都做归一化（去路径 / 去 `.fa` 扩展名 / 去 `MAG_` 前缀 / 忽略大小写）再比对，因此诸如 `A602__bin.10.fa` vs `[MAG=A602__bin.10]`、`MAG_d777__bin.9.fa` vs `[MAG=d777__bin.9]` 都能配对。**若跑出来某组计数为 0**（说明匹配率极低），先用诊断模式看样例、确认 header 与映射表的写法差异，再对症处理：
> ```bash
> # 诊断: 只打印样例 Header / 映射 MAG / 抽样匹配率, 不写任何文件
> python3 /path/to/amp_pipeline/build_grouped_sorf_fasta.py \
>     --catalog ... --mag-sample ... --meta ... \
>     --dry-run --sample-n 8
> ```

> **⚠️ 如果你跑出来分组全是 0，且诊断显示 Catalog header 无 `[MAG=...]`（形如 `>k141_30435_10665_[60054_-_60197]_`）**：
> 说明去重后的 `final_sORF_Catalog.unique.fa` 丢失了每条肽段的 MAG 来源，**无法**用上面的脚本按队列分组。
> 改用 **v2 脚本** `build_grouped_sorf_from_magfiles.py`，它直接读每个 per-MAG ORF 文件（`sorf_output/*__bin.*.fa.orf.fa`），从**文件名**恢复 MAG 来源再做四队列分组。
> ```bash
> python3 amp_pipeline/build_grouped_sorf_from_magfiles.py \
>     --sorf-dir   /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/sorf_output \
>     --mag-sample /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/MAG_Sample_Mapping.tsv \
>     --meta       /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/Sample_Group_Mapping.tsv \
>     --catalog    /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/sorf_output/final_sORF_Catalog.unique.fa \
>     --outdir     /mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/comparable_sorf_grouped_catalog \
>     --copy-total
> ```
> 先去掉 `--catalog/--outdir/--copy-total`、加 `--dry-run` 试跑一次，确认 per-MAG 文件都能匹配到映射表后再正式跑。

### 1.3 输出结构（就在 `sorf_grouped_catalog/` 里）

```
sorf_grouped_catalog/
├── sORF_All_Total.fa                        ← 不分组总库 (等价于 final_sORF_Catalog.unique.fa)
├── group_manifest.tsv                        ← 每个分组文件的肽段/MAG/样本数汇总
├── Cohort1_Matched265_5Stage/
│   ├── Cohort1_NC.fa   ├── Cohort1_SCS.fa
│   ├── Cohort1_SCD.fa  ├── Cohort1_MCI.fa   └── Cohort1_AD.fa
├── Cohort2_Matched265_NCvsAD/
│   ├── Cohort2_Healthy_NC.fa  └── Cohort2_Disease_AD.fa
├── Cohort3_Full476_5Stage/
│   ├── Cohort3_NC.fa   ├── Cohort3_SCS.fa
│   ├── Cohort3_SCD.fa  ├── Cohort3_MCI.fa   └── Cohort3_AD.fa
└── Cohort4_Full476_NCvsAD/
    ├── Cohort4_Healthy_NC.fa  └── Cohort4_Disease_AD.fa
```

**匹配说明：**

| Cohort | 样本切片 | 分组 | 说明 |
| :--- | :--- | :--- | :--- |
| Cohort1 | `Is_Matched_265 == Yes` | 5 阶段 (NC/SCS/SCD/MCI/AD) | 每组 53 人，年龄性别匹配 |
| Cohort2 | 同上 | 严格 NC vs AD | 只写 Healthy_NC 与 Disease_AD，SCS/SCD/MCI 在本队列被排除 |
| Cohort3 | 全 476 | 5 阶段 | 全队列大样本 |
| Cohort4 | 全 476 | 严格 NC vs AD | 同上 |

---

## 2. 从服务器传到本地（rsync vs 直接下载）

两个文件都 6+ GB 级别（`sorf_output` 里 catalog + unique 共约 19.6 GB；分组目录 `sorf_grouped_catalog` 里每个分组 = 该组命中 MAG 的肽段子集，通常几百 MB）。**推荐 rsync**，它支持断点续传、增量比对，比网页逐文件下载稳。

### 方式 A：rsync（推荐，WSL 里执行）

把服务器的分组目录整目录拖到本地 `~/c_AMPs-prediction-master` 下：

```bash
rsync -avhP \
  25wenshaohua@mu01:/mnt/hpc/home/25menglei/25wenshaohua/wsh/ad/codenew/sorf_pipeline/sorf_grouped_catalog/ \
  /home/w26/c_AMPs-prediction-master/c_AMPs-prediction-master/sorf_grouped_catalog/
```

- `-a` 归档（保留结构/权限），`-v` 显示，`-h` 人类可读大小，`-P` = 进度 + 断点续传。
- 若你的服务器也开了 SSH 代理（你在 WSL 上配了 `172.30.192.1:4067` 转发），把主机名 `mu01` 换成实际的跳板/代理写法，或先 `ssh mu01` 测试连通。
- 只想要总库：单独 rsync `sORF_All_Total.fa` 即可。

### 方式 B：直接下载

```bash
scp -r 25wenshaohua@mu01:/mnt/hpc/.../sorf_pipeline/sorf_grouped_catalog /home/w26/...
```

或先 `tar` 成一个包再下：
```bash
tar -czf sorf_grouped_catalog.tar.gz -C /mnt/hpc/.../sorf_pipeline sorf_grouped_catalog
# 下载后 tar -xzf
```

> 注意 `sORF_All_Total.fa` 可能是指向 `final_sORF_Catalog.unique.fa` 的符号链接/硬链接。rsync 加 `-L` 会解引用。若你想让总库在本地是**独立实体**，生成时加 `--copy-total`（会真正拷贝一份）。否则下载到本地后，直接确认 `sorf_output/final_sORF_Catalog.unique.fa` 也在就行——**它与 `sORF_All_Total.fa` 内容一致**。

---

## 3. 本地：三模型 AMP 预测

你本地的 Python 环境是官方要求的三个环境：
- `camps-tf114`：Attention (`att.h5`) 与 LSTM (`lstm.h5`) —— TensorFlow 1.14 / Keras 2.2.4
- `py36`：BERT (`bert.bin`) —— PyTorch / bert-sklearn 0.2.0

> 你刚激活的 `megahit` 不是预测用的环境，三模型分别要用上面两个环境。请确认 `Models/` 下有 `att.h5`、`lstm.h5`、`bert.bin`。若缺 `bert.bin`，按 `Models/ReadME.txt` 从 dropbox 下载并 `md5sum` 校验（`990d14de053d8080fcca33d712d647b6`）。

### 3.1 单个分组跑（先试一个）

```bash
cd ~/c_AMPs-prediction-master/c_AMPs-prediction-master

bash amp_pipeline/run_pipeline_one.sh \
    sorf_grouped_catalog/Cohort1_Matched265_5Stage/Cohort1_NC.fa \
    amp_results/Cohort1_Matched265_5Stage/Cohort1_NC
```

### 3.2 全部组批量跑

```bash
bash amp_pipeline/run_pipeline_all_groups.sh sorf_grouped_catalog amp_results
```

- 会自动遍历 `sorf_grouped_catalog` 下所有子文件夹里的 `*.fa`，逐个跑 `run_pipeline_one.sh`。
- **自动定位分组目录**：脚本会依次探测「当前目录 / 仓库内 / 仓库上一级 / 仓库上两级」的 `sorf_grouped_catalog`，所以即便你把目录放在了 `~/c_AMPs-prediction-master/sorf_grouped_catalog`（仓库的上一级，即你现在的情况），不传路径也能自动找到；找不到时再显式传绝对路径。
- **预检 fail-fast**：批量脚本会对每个分组先跑 `run_pipeline_one.sh` 的前置检查——`Models/{att.h5,lstm.h5,bert.bin}` 是否存在、两个 conda 环境是否有 python、`script/format.pl`/`result.pl` 是否在位。缺任何一样立刻给出清晰报错，**不会等你跑到一半才失败**。
- 默认跳过 `sORF_All_Total.fa`（总库，且在顶层不参与 iterate），想跑就 `SKIP_TOTAL=0 bash ...`。
- 每个分组的结果写到 `amp_results/<Cohort文件夹>/<分组名>/`，包含 `final_prediction.txt`、三个单模型概率 TSV 与 `input.fa`。

### 3.3 汇总三模型（你要的“汇总三个模型的结果”）

```bash
python3 amp_pipeline/aggregate_amp_results.py amp_results
```

输出三个文件：

1. `amp_results/<分组名>/aggregated_results.tsv` —— **每肽段明细**：
   `name / seq / len / att_prob / lstm_prob / bert_prob / n_votes / is_AMP / is_AMP_flex`
2. `amp_results/amp_summary.tsv` —— **分组层面摘要**：每组 `n_seq`、三票一致 AMP 数及占比、宽松(≥2票) AMP 数及占比。
3. `amp_results/amp_all_peptides.tsv` —— **全部分组的肽段合表**（带 `group` 列），方便直接丢进 R/Excel 做后续统计。

> 投票规则与官方 `result.pl` 完全一致：三个模型 >0.5 记一票，`n_votes==3` 才判为 `is_AMP=1`。另额外给 `is_AMP_flex`（≥2 票宽松口径）供你选择筛多肽。

---

## 4. 怎么 git 同步我给你的代码

你现在这台机器克隆的目录 **不是 git 仓库**（`git status` 报 `fatal: not a git repository`），因为 `c_AMPs-prediction-master/c_AMPs-prediction-master` 是套娃的两层同名目录，而 `.git` 只存在于你**另外那台 Arena 沙箱的 `/home/user/c_AMPs-prediction`** 里。

我这边（Arena 沙箱分支 `arena/01a06f35-c-amps-prediction`）已经把新增的 `amp_pipeline/`（4 个脚本）和 `script/prediction_lstm.py` 的一处修复都放好了。你只需要在**能访问那个** GitHub 仓库的地方 `git pull`（或看下面两种方式）。

### 方式 A（推荐）：直接在原仓库 `git pull`

我的改动会提交并推送到远程分支 `arena/01a06f35-c-amps-prediction`（以及可选的 PR 到 `master`）。你只要：

```bash
cd 你的仓库目录
git fetch origin
git checkout arena/01a06f35-c-amps-prediction   # 或合并到你的本地分支
git pull origin arena/01a06f35-c-amps-prediction
```

### 方式 B：把本地这两个文件/目录手动拷过去

你现在这台 WSL 上既然已经跑通了下载目录，也可以直接手动把 `amp_pipeline/` 整个文件夹复制进你的 `c_AMPs-prediction-master/c_AMPs-prediction-master/` 下：

```bash
# 在下载/解压出的 amp_pipeline 目录所在处执行
cp -r amp_pipeline ~/c_AMPs-prediction-master/c_AMPs-prediction-master/
```

再把修正后的 `script/prediction_lstm.py` 覆盖过去（把 `../Moldes/lstm.h5` 改回 `../Models/lstm.h5`）。

### 方式 C：用 git 把改动拉回本地（如果你想自己合并）

```bash
cd ~/c_AMPs-prediction-master/c_AMPs-prediction-master
git clone   # 若还没有 remote, 用 git remote add origin <你的仓库URL>
git fetch origin
git checkout -b arena/01a06f35-c-amps-prediction origin/arena/01a06f35-c-amps-prediction
```

---

## 5. 一次跑完的推荐顺序（复制粘贴）

```bash
# ---- 服务器端 ----
python3 amp_pipeline/build_grouped_sorf_fasta.py \
  --catalog sorf_output/final_sORF_Catalog.unique.fa \
  --mag-sample MAG_Sample_Mapping.tsv \
  --meta Sample_Group_Mapping.tsv \
  --outdir sorf_grouped_catalog --copy-total

# ---- 传回本地 (WSL, 在仓库根目录) ----
rsync -avhP 25wenshaohua@mu01:/mnt/.../sorf_grouped_catalog/ ./sorf_grouped_catalog/

# ---- 本地预测 + 汇总 ----
bash amp_pipeline/run_pipeline_all_groups.sh sorf_grouped_catalog amp_results   # 自动探测目录
python3 amp_pipeline/aggregate_amp_results.py amp_results
```

---

## 6. 关于总 sORF 的 FASTA 在哪里

| 你问的 | 对应文件 |
| :--- | :--- |
| 「分组 + 不分组总的」 | `sorf_grouped_catalog/sORF_All_Total.fa`（内容 == `sorf_output/final_sORF_Catalog.unique.fa`，即步骤一去重后的全库） |
| 分组总 | `sorf_grouped_catalog/Cohort*_*/*.fa` |
| 分组的头部信息 | `sorf_grouped_catalog/group_manifest.tsv` |

> 如果你只要"总的"那一个，最省事的是直接拿服务器上已有的 `sorf_output/final_sORF_Catalog.unique.fa`（约 9.8 GB），不必重新拷贝一份。

---

## 7. 修复说明

`script/prediction_lstm.py` 里模型路径原本写成了 `../Moldes/lstm.h5`（拼写错误，目录不叫 `Moldes`），会导致 LSTM 加载模型直接失败。已改为 `../Models/lstm.h5`，与 `att.h5`、`bert.bin` 所在目录一致。
