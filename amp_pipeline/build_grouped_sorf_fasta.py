#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=================================================================================
 步骤一(服务器端): 按四维度队列把「非冗余 sORF Catalog」切分成「分组总 FASTA」
=================================================================================

用途
----
读入 :
    * 非冗余 sORF 目录  : sorf_output/final_sORF_Catalog.unique.fa
                          (每条 Header 形如: >sORF_MAGID_序列序号 [MAG=MAGID])
    * MAG->样本 映射    : MAG_Sample_Mapping.tsv      (来自 build_mag_sample_mapping.py)
    * 样本->分组 映射  : Sample_Group_Mapping.tsv     (来自 build_mapping.py)
输出 (写入 --outdir) :
    sORF_All_Total.fa                                  <- 不分组总库(指向原 catalog)
    Cohort1_Matched265_5Stage/Cohort1_{NC,SCS,SCD,MCI,AD}.fa
    Cohort2_Matched265_NCvsAD/Cohort2_{Healthy_NC,Disease_AD}.fa
    Cohort3_Full476_5Stage/   Cohort3_{NC,SCS,SCD,MCI,AD}.fa
    Cohort4_Full476_NCvsAD/   Cohort4_{Healthy_NC,Disease_AD}.fa
    group_manifest.tsv                                 <- 每个分组文件的肽段/MAG/样本数汇总

关键: MAG id 匹配
------------------
Catalog 每条 Header 中标明其来源 MAG (MAG Provenance), 而 MAG_Sample_Mapping 用 MAG_File
列标识 MAG。两者 id 的写法可能不完全一致 (例如带/不带 .fa 后缀、路径、大小写、MAG_ 前缀)。
本脚本对【两端】的 MAG id 做统一的 normalize (去路径/去扩展名/去常见前缀/转小写) 后再比对,
以稳健匹配。若仍匹配不上, 用 --dry-run 可打印样例 Header 与映射表 MAG 值, 便于诊断。

示例
----
    python3 build_grouped_sorf_fasta.py \
        --catalog sorf_output/final_sORF_Catalog.unique.fa \
        --mag-sample MAG_Sample_Mapping.tsv \
        --meta Sample_Group_Mapping.tsv \
        --outdir sorf_grouped_catalog

诊断 (不写任何文件, 只看匹配情况):
    python3 build_grouped_sorf_fasta.py \
        --catalog ... --mag-sample ... --meta ... \
        --dry-run --sample-n 10

若列名无法自动识别 (见下方"自动识别列名")，请显式指定:
    --mag-col    MAG   --sample-col Sample \
    --stage-col  Stage --matched-col Is_Matched_265
依赖: 仅标准库 (argparse/csv/re/os/sys/shutil)。
=================================================================================
"""

import argparse
import csv
import os
import re
import sys
import shutil

# ---------------------------------------------------------------------------------
# 四维度队列定义 (可通过下方常量自行调整)
# ---------------------------------------------------------------------------------
COHORTS = [
    {"id": "Cohort1", "folder": "Cohort1_Matched265_5Stage", "slice": "matched", "mode": "stage"},
    {"id": "Cohort2", "folder": "Cohort2_Matched265_NCvsAD", "slice": "matched", "mode": "binary"},
    {"id": "Cohort3", "folder": "Cohort3_Full476_5Stage",    "slice": "all",     "mode": "stage"},
    {"id": "Cohort4", "folder": "Cohort4_Full476_NCvsAD",    "slice": "all",     "mode": "binary"},
]

NC_STAGE = "NC"
AD_STAGE = "AD"
HEALTHY_LABEL = "Healthy_NC"
DISEASE_LABEL = "Disease_AD"
STAGE_ORDER = ["NC", "SCS", "SCD", "MCI", "AD"]

TRUTHY = {"yes", "y", "true", "1", "matched", "matched_265", "是", "匹配"}

HEADER_MAG_RE = re.compile(r"\[MAG=([^\]]+)\]", re.IGNORECASE)
# 常见基因组扩展名
EXT_RE = re.compile(r"\.(fa|fna|fasta|ffn|faa|fas|orf\.fa(\.gz)?|gz)$", re.IGNORECASE)
# 常见 MAG 前缀 (如 MAG_A602__bin.10 -> A602__bin.10)
PREFIX_RE = re.compile(r"^(mag|drep|representative|rep|bin|genome|scaffold|contig)[_\-\.]", re.IGNORECASE)


# ---------------------------------------------------------------------------------
# MAG id 归一化 (稳健匹配的关键)
# ---------------------------------------------------------------------------------
def normalize_mag(x):
    """统一两端 MAG id: 去路径 -> 去扩展名 -> 去常见前缀 -> 去下划线边界 -> 转小写。"""
    if x is None:
        return None
    x = x.strip()
    if not x:
        return None
    x = os.path.basename(x)          # /path/to/A602__bin.10.fa -> A602__bin.10.fa
    x = EXT_RE.sub("", x)            # A602__bin.10.fa -> A602__bin.10
    x = PREFIX_RE.sub("", x)         # MAG_A602__bin.10 -> A602__bin.10
    x = x.strip("_.-")               # 去首尾分隔符
    return x.lower()


def extract_mag_candidates(header):
    """从 Header 行提取候选 MAG 序列 (按优先级)。"""
    cands = []
    m = HEADER_MAG_RE.search(header)
    if m:
        cands.append(m.group(1).strip())
    # 候选2: 去掉 > 后、遇到空白/ '[' 之前的完整 token
    token = header.lstrip(">").split("[")[0].strip()
    if token:
        cands.append(token)
    # 候选3: 紧跟在 sORF_ 之后、到下一个 '_' 之前 (当 MAG 不含下划线时有用)
    m2 = re.match(r">\s*sORF_([^_\s]+)", header)
    if m2:
        cands.append(m2.group(1).strip())
    # 去重保序
    seen, out = set(), []
    for c in cands:
        c = c.strip()
        if c and c not in seen:
            seen.add(c)
            out.append(c)
    return out


# ---------------------------------------------------------------------------------
# 列名自动识别
# ---------------------------------------------------------------------------------
def detect_col(header, candidates, default=None):
    if not header:
        return default
    low = [h.lower().strip() for h in header]
    for cand in candidates:
        cand = cand.lower().strip()
        for i, h in enumerate(low):
            if h == cand:
                return i
        for i, h in enumerate(low):
            if cand in h or h in cand:
                return i
    return default


def read_mag_sample(path, mag_col=None, sample_col=None, sample_sep=None):
    """
    读 MAG->样本 映射 (长格式或宽格式)。返回:
      mag_samples : MAG(归一化) -> set(sample)
      sample_mags : sample -> set(MAG(归一化))
      all_samples : set(sample)
    """
    mag_samples = {}
    sample_mags = {}
    if not os.path.exists(path):
        print(f"  [警告] 找不到 MAG_Sample_Mapping: {path} -> 视为无 MAG-样本 关联")
        return mag_samples, sample_mags, set()

    with open(path, newline="") as fh:
        reader = csv.reader(fh, delimiter="\t")
        rows = [r for r in reader if r and any(c.strip() for c in r)]
    if not rows:
        return mag_samples, sample_mags, set()

    header = rows[0]
    if mag_col is None:
        mag_col = detect_col(header,
                             ["mag", "genome", "bin", "representative", "rep", "mags", "scaffold", "contig", "genome_id", "mag_file"],
                             default=0)
    if sample_col is None:
        sample_col = detect_col(header,
                                ["sample", "sample_id", "sampleid", "samples", "strain", "isolate", "biosample", "sample_name"],
                                default=1)
    ncols = max(len(header), max(len(r) for r in rows))
    if mag_col is None or mag_col >= ncols:
        mag_col = 0
    if sample_col is None or sample_col >= ncols:
        sample_col = 1

    print(f"  识别到的列: MAG_col=#{mag_col}({header[mag_col] if mag_col < len(header) else '?'}) "
          f"Sample_col=#{sample_col}({header[sample_col] if sample_col < len(header) else '?'})")

    for r in rows[1:]:
        if mag_col >= len(r) or sample_col >= len(r):
            continue
        mag = normalize_mag(r[mag_col])
        raw_samples = r[sample_col]
        if not mag:
            continue
        if sample_sep:
            parts = [p for p in re.split(sample_sep, raw_samples) if p]
        else:
            parts = [p for p in re.split(r"[,\t; ]+", raw_samples) if p]
        for s in parts:
            s = s.strip()
            if not s:
                continue
            mag_samples.setdefault(mag, set()).add(s)
            sample_mags.setdefault(s, set()).add(mag)

    all_samples = set(sample_mags.keys())
    print(f"  MAG 总数: {len(mag_samples)}   样本总数: {len(all_samples)}")
    return mag_samples, sample_mags, all_samples


def read_sample_meta(path, sample_col=None, stage_col=None, matched_col=None):
    meta = {}
    if not os.path.exists(path):
        print(f"  [警告] 找不到 Sample_Group_Mapping: {path}")
        return meta

    with open(path, newline="") as fh:
        reader = csv.reader(fh, delimiter="\t")
        rows = [r for r in reader if r and any(c.strip() for c in r)]
    if not rows:
        return meta

    header = rows[0]
    if sample_col is None:
        sample_col = detect_col(header,
                                ["sample", "sample_id", "sampleid", "samples", "id", "sample_name", "name", "individual"],
                                default=0)
    if stage_col is None:
        stage_col = detect_col(header,
                               ["stage", "group", "diagnosis", "condition", "phase", "status", "cohort", "stages"],
                               default=1)
    if matched_col is None:
        matched_col = detect_col(header,
                                 ["match", "is_matched", "matched", "matched_265", "matched265", "match_265", "matched_265_flag"],
                                 default=None)
    ncols = max(len(header), max(len(r) for r in rows))
    print(f"  识别到的列: Sample_col=#{sample_col}({header[sample_col] if sample_col < len(header) else '?'}) "
          f"Stage_col=#{stage_col}({header[stage_col] if stage_col < len(header) else '?'}) "
          f"Matched_col=#{matched_col}({header[matched_col] if matched_col is not None and matched_col < len(header) else '无'})")

    for r in rows[1:]:
        if sample_col >= len(r):
            continue
        sid = r[sample_col].strip()
        if not sid:
            continue
        stage = r[stage_col].strip() if stage_col < len(r) else ""
        matched = True
        if matched_col is not None and matched_col < len(r):
            v = r[matched_col].strip().lower()
            matched = v in TRUTHY or v == "1" or v == "true" or v == "yes"
        meta[sid] = (stage, matched)
    return meta


def build_group_samples(meta, slice_mode, mode):
    """返回 dict: group_name -> set(sample_id)"""
    slice_samples = []
    for sid, (stage, matched) in meta.items():
        if slice_mode == "matched" and not matched:
            continue
        if not stage:
            continue
        slice_samples.append((sid, stage))

    groups = {}
    if mode == "stage":
        present = set(st for _, st in slice_samples)
        order = [s for s in STAGE_ORDER if s in present] + [s for s in present if s not in STAGE_ORDER]
        for st in order:
            groups[st] = {sid for sid, s in slice_samples if s == st}
    else:
        groups[HEALTHY_LABEL] = {sid for sid, s in slice_samples if s == NC_STAGE}
        groups[DISEASE_LABEL] = {sid for sid, s in slice_samples if s == AD_STAGE}
    return groups


# ---------------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="按四维度队列拆分非冗余 sORF Catalog 为分组总 FASTA")
    ap.add_argument("--catalog", required=True, help="非冗余 sORF Catalog (final_sORF_Catalog.unique.fa)")
    ap.add_argument("--mag-sample", default="MAG_Sample_Mapping.tsv", help="MAG->样本 映射 TSV")
    ap.add_argument("--meta", default="Sample_Group_Mapping.tsv", help="样本->分组 元数据 TSV")
    ap.add_argument("--outdir", default="sorf_grouped_catalog", help="输出目录")
    ap.add_argument("--mag-col", type=int, default=None)
    ap.add_argument("--sample-col", type=int, default=None)
    ap.add_argument("--stage-col", type=int, default=None)
    ap.add_argument("--matched-col", type=int, default=None)
    ap.add_argument("--copy-total", action="store_true", help="总库做真实拷贝而非链接")
    ap.add_argument("--total-name", default="sORF_All_Total.fa")
    ap.add_argument("--dry-run", action="store_true",
                    help="只诊断匹配情况(打印样例与统计), 不写任何文件")
    ap.add_argument("--sample-n", type=int, default=5, help="打印多少条样例 Header / 映射 MAG")
    ap.add_argument("--mismatch-n", type=int, default=10, help="打印多少条未匹配 Header(含候选 MAG)")
    args = ap.parse_args()

    if not os.path.exists(args.catalog):
        sys.exit(f"错误: 找不到 --catalog: {args.catalog}")

    print("=" * 78)
    print(" 四维度分组总 FASTA 生成" + ("  [DRY-RUN 诊断]" if args.dry_run else ""))
    print("=" * 78)
    print(f"[输入] Catalog      : {args.catalog}")
    print(f"[输入] MAG->样本    : {args.mag_sample}")
    print(f"[输入] 样本->分组   : {args.meta}")
    if not args.dry_run:
        os.makedirs(args.outdir, exist_ok=True)

    # 1) MAG->样本
    print("\n[1/3] 读取 MAG->样本 映射 ...")
    mag_samples, sample_mags, all_samples = read_mag_sample(
        args.mag_sample, args.mag_col, args.sample_col)

    # 2) 样本->分组
    print("\n[2/3] 读取 样本->分组 元数据 ...")
    meta = read_sample_meta(args.meta, args.sample_col, args.stage_col, args.matched_col)
    n_matched = sum(1 for _, (_, m) in meta.items() if m)
    print(f"  样本总数: {len(meta)}   匹配265 数: {n_matched}")

    # 3) 构造队列 -> 组 的样本/MAG 集合
    print("\n[3/3] 构造队列 -> 组 的样本/MAG 集合 ...")
    cohort_groups = {}
    cohort_samples = {}
    for c in COHORTS:
        g_samples = build_group_samples(meta, c["slice"], c["mode"])
        g_mags = {}
        for gname, ss in g_samples.items():
            mags = set()
            for s in ss:
                mags |= sample_mags.get(s, set())
            g_mags[gname] = mags
        cohort_groups[c["id"]] = g_mags
        cohort_samples[c["id"]] = g_samples
        print(f"    {c['id']:9s} 组数={len(g_samples)} 样本数={sum(len(v) for v in g_samples.values()):5d} "
              f"命中MAG去重后={len(set().union(*g_mags.values())):5d} 组内MAG合计={sum(len(v) for v in g_mags.values())}")

    # 归一化映射: normalized MAG -> 任一可写回的原始 MAG (仅用于展示)
    norm_to_raw = {}
    for k in mag_samples:
        nk = normalize_mag(k)
        if nk not in norm_to_raw:
            norm_to_raw[nk] = k
    mag_set = set(mag_samples.keys())   # 已归一化的 MAG 键

    # 打印映射表样例
    print(f"\n  映射表 MAG 样例 (前 {args.sample_n} 个, 已归一化):")
    for k in list(mag_set)[:args.sample_n]:
        print(f"    [MAG] {k!r}   <- 样本 {len(mag_samples[k])} 个")

    if args.dry_run:
        run_dry(args, COHORTS, mag_set, cohort_groups, norm_to_raw)
        return

    # ================= 真正的切分 =================
    print("\n[切分] 流式切分 Catalog (单遍读入, 多文件写出) ...")
    handles = {}
    for c in COHORTS:
        folder = os.path.join(args.outdir, c["folder"])
        os.makedirs(folder, exist_ok=True)
        for gname in cohort_groups[c["id"]]:
            fname = f"{c['id']}_{gname}.fa"
            handles[(c["id"], gname)] = open(os.path.join(folder, fname), "w")

    total_path = os.path.join(args.outdir, args.total_name)
    try:
        if args.copy_total:
            shutil.copyfile(args.catalog, total_path)
            print(f"  总库 [拷贝]  -> {total_path}")
        else:
            os.link(args.catalog, total_path)
            print(f"  总库 [硬链接] -> {total_path}")
    except (OSError, NotImplementedError):
        try:
            os.symlink(os.path.abspath(args.catalog), total_path)
            print(f"  总库 [符号链接] -> {total_path}")
        except OSError:
            shutil.copyfile(args.catalog, total_path)
            print(f"  总库 [拷贝]  -> {total_path}")

    n_total = 0
    n_written = 0
    n_unmatched = 0
    group_count = {k: 0 for k in handles}
    group_length = {k: [] for k in handles}
    unmatched_sample = []

    with open(args.catalog, "r") as fin:
        header = None
        seq = []
        def flush():
            nonlocal header, seq, n_total, n_written, n_unmatched
            if header is None:
                return
            n_total += 1
            seqlen = sum(len(s) for s in seq)
            cands = extract_mag_candidates(header)
            matched_mag = None
            for cand in cands:
                cm = normalize_mag(cand)
                if cm and cm in mag_set:
                    matched_mag = cm
                    break
            if matched_mag is None:
                n_unmatched += 1
                if len(unmatched_sample) < args.mismatch_n:
                    unmatched_sample.append((header, cands[:4]))
                header, seq = None, []
                return
            for c in COHORTS:
                gm = cohort_groups[c["id"]]
                for gname, mags in gm.items():
                    if matched_mag in mags:
                        k = (c["id"], gname)
                        h = handles[k]
                        h.write(header); h.write("\n")
                        for line in seq:
                            h.write(line); h.write("\n")
                        group_count[k] += 1
                        group_length[k].append(seqlen)
                        n_written += 1
            header, seq = None, []

        for line in fin:
            if line.startswith(">"):
                flush()
                header = line.strip()
                seq = []
            else:
                seq.append(line.strip())
        flush()

    for h in handles.values():
        h.close()

    # manifest
    print("\n[输出] 生成 group_manifest.tsv ...")
    manifest = os.path.join(args.outdir, "group_manifest.tsv")
    with open(manifest, "w") as mf:
        mf.write("\t".join(["Cohort", "Group", "FASTA_file", "N_sORF", "N_MAG", "N_Sample",
                            "Mean_aaLength", "File_size"]))
        mf.write("\n")
        for c in COHORTS:
            folder = os.path.join(args.outdir, c["folder"])
            for gname in cohort_groups[c["id"]]:
                k = (c["id"], gname)
                fname = f"{c['id']}_{gname}.fa"
                fpath = os.path.join(folder, fname)
                lens = group_length[k]
                mean_len = (sum(lens) / len(lens)) if lens else 0
                size = os.path.getsize(fpath) if os.path.exists(fpath) else 0
                mf.write("\t".join([c["id"], gname, fname, str(group_count[k]),
                                   str(len(cohort_groups[c["id"]][gname])),
                                   str(len(cohort_samples[c["id"]][gname])),
                                   f"{mean_len:.1f}", str(size)]))
                mf.write("\n")
        tot_size = os.path.getsize(total_path) if os.path.exists(total_path) else 0
        mf.write("\t".join(["All", "Total", args.total_name, str(n_total),
                           str(len(mag_set)), str(len(all_samples)), "-", str(tot_size)]))
        mf.write("\n")

    print(f"\n  总册数 (Catalog records)   : {n_total:,}")
    print(f"  写出肽段引用数 (去重跨组)  : {n_written:,}")
    print(f"  未能匹配到队列的肽段数    : {n_unmatched:,}")
    for c in COHORTS:
        print(f"    {c['id']}: " + ", ".join(
            f"{g}={group_count[(c['id'], g)]:,}" for g in cohort_groups[c["id"]]))

    if n_unmatched and n_total:
        print(f"\n  ⚠️  共 {n_unmatched:,} 条肽段未匹配 (占总数的 "
              f"{100.0*n_unmatched/n_total:.2f}%), 可能 MAG id 写法不一致。")
        print(f"  建议先运行: --dry-run 查看样例。以下为前几条未匹配 Header:")
        for hdr, cands in unmatched_sample:
            print(f"      {hdr[:120]}")
            print(f"        候选MAG: {cands}")

    print("\n完成! 分组总 FASTA 位于 (整目录打包下载即可):")
    print("  " + os.path.abspath(args.outdir))
    print(f"  分组清单: {manifest}")


def run_dry(args, cohorts, mag_set, cohort_groups, norm_to_raw):
    """诊断模式: 不写文件, 打印 Catalog 样例 Header / 映射表原始值 与匹配统计。"""
    # 打印映射表原始 MAG_File 值 (未归一化), 看清真实写法
    print("\n[DRY-RUN] 映射表 MAG_File 原始值 (前 %d 行, 未归一化) ..." % args.sample_n)
    if os.path.exists(args.mag_sample):
        n = 0
        with open(args.mag_sample, newline="") as fh:
            rdr = csv.reader(fh, delimiter="\t")
            for row in rdr:
                if not row or not any(c.strip() for c in row):
                    continue
                print("    RAW | " + " | ".join(c.strip() for c in row[:6]))
                n += 1
                if n > args.sample_n:
                    break
    else:
        print("  (找不到映射表文件)")

    print("\n[DRY-RUN] 读取 Catalog 样例 Header (不写任何文件) ...")
    sample_headers = []
    with open(args.catalog, "r") as fin:
        for line in fin:
            if line.startswith(">"):
                sample_headers.append(line.strip())
                if len(sample_headers) >= args.sample_n:
                    break

    print(f"\n  Catalog Header 样例 (前 {args.sample_n} 条):")
    for h in sample_headers:
        m = HEADER_MAG_RE.search(h)
        raw_mag = m.group(1) if m else "(无 [MAG=...])"
        cands = extract_mag_candidates(h)
        norm = [normalize_mag(c) for c in cands]
        hit = [n for n in norm if n and n in mag_set]
        print(f"    {h[:130]}")
        print(f"        原始[MAG]={raw_mag!r}  候选MAG={cands}  归一化={norm}  ->  命中映射表={hit[:3]}")

    # 全量抽样统计 (流式数 10000 条, 快速评估匹配率)
    probe = 10000
    n_total = 0
    n_hit = 0
    print(f"\n  抽样统计 (前 {probe} 条肽段):")
    with open(args.catalog, "r") as fin:
        for line in fin:
            if line.startswith(">"):
                if n_total >= probe:
                    break
                n_total += 1
                cands = extract_mag_candidates(line.strip())
                if any((normalize_mag(c) in mag_set) for c in cands):
                    n_hit += 1
    if n_total == 0:
        print("  ⚠️  抽样未读到任何 '>' 行 —— 请确认 --catalog 是 FASTA。")
    else:
        print(f"    抽样肽段总数 : {n_total}")
        print(f"    能匹配到映射表: {n_hit}  ({100.0*n_hit/n_total:.1f}%)")
        print(f"    匹配率过低时, 请检查上方 Header 与映射表 MAG 的写法差异。")

    print("\n  DRY-RUN 结束。若匹配率正常(接近100%), 去掉 --dry-run 重新运行即可。")


if __name__ == "__main__":
    main()
