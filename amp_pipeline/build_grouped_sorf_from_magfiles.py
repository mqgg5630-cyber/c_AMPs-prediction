#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=================================================================================
 步骤一(服务器端) v2: 直接从「每 MAG 的 ORF 文件」生成四队列分组总 FASTA
=================================================================================

为什么需要这个 v2
-----------------
你手上的 final_sORF_Catalog.unique.fa 是用 getorf 默认 header 合并去重得到的,
header 形如  >k141_34437_1665_[60054_-_60197]_
并【没有】注入 [MAG=...] / sORF_MAGID 标识。因此单靠这个 catalog 无法还原每条
肽段来自哪个 MAG, 也就无法按样本/队列分组。

但 sorf_output/ 里【每个】代表 MAG 都有一个 ORF 文件 (如 A602__bin.11.fa.orf.fa),
文件名本身就含 MAG 身份。本脚本《直接从这些每-MAG ORF 文件》切分:

  每条肽段 -> 来自哪个 MAG (文件名) -> 属于哪些样本 (MAG_Sample_Mapping)
          -> 属于哪些队列分组 (Sample_Group_Mapping) -> 写入对应组 FASTA

从而在【不依赖 catalog header】的情况下, 正确还原四队列分组。

输入
----
   --sorf-dir  : 含 1971 个 *__bin.*.fa.orf.fa 文件的目录 (= sorf_output)
                 (若无 --catalog, 则总库 = 这些文件流式去重得出; 若有 --catalog 则直接引用)
   --mag-sample: MAG_Sample_Mapping.tsv   (MAG_File 或 MAG_ID 列标识 MAG)
   --meta      : Sample_Group_Mapping.tsv
   --catalog   : 可选; final_sORF_Catalog.unique.fa。总库从此文件硬链接/拷贝
                 (推荐提供, 总库即现有非冗余库)

输出 (--outdir)
----
   sORF_All_Total.fa  (若提供 --catalog, 直接引用它; 否则由 per-MAG 文件流式去重得出)
   Cohort1_Matched265_5Stage/Cohort1_{NC,SCS,SCD,MCI,AD}.fa
   Cohort2_Matched265_NCvsAD/Cohort2_{Healthy_NC,Disease_AD}.fa
   Cohort3_Full476_5Stage/   Cohort3_{NC,SCS,SCD,MCI,AD}.fa
   Cohort4_Full476_NCvsAD/   Cohort4_{Healthy_NC,Disease_AD}.fa
   group_manifest.tsv

去重策略
--------
  每个【组】内用序列的 64-bit 哈希做精确去重 (跨 MAG 重复只保留该组一次)。
  同一序列在不同组可各自保留 (不同队列/组是独立切片, 属预期)。
  --no-dedup 可关闭组内去重 (保留每 MAG 每条肽段)。

依赖: 仅标准库 (argparse/csv/os/re/sys/shutil/hashlib)。流式读, 组内 seen 存哈希, 内存可控。
=================================================================================
"""

import argparse
import csv
import glob
import hashlib
import os
import re
import sys
import time

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

# 已知基因组/ORF 扩展名后缀 (用于从文件名提取 MAG id)
ORF_EXT_RE = re.compile(r"(\.orf\.fa)$", re.IGNORECASE)
GENOME_EXT_RE = re.compile(r"\.(fa|fna|fasta|ffn|faa|fas|gz)$", re.IGNORECASE)
PREFIX_RE = re.compile(r"^(mag|drep|representative|rep|bin|genome|scaffold|contig)[_\-\.]", re.IGNORECASE)
# 匹配 per-MAG ORF 文件: 优先 `*__bin.*.fa.orf.fa`, 兼容 `*.orf.fa`
ORF_FILE_GLOB = "*__bin.*.fa.orf.fa"
ORF_FILE_GLOB_ANY = "*.orf.fa"


def strip_ext(x):
    """循环去掉已知基因组/ORF 扩展名, 保留 MAG id。"""
    if not x:
        return x
    for _ in range(5):
        y = ORF_EXT_RE.sub("", x)
        if y != x:
            x = y
            continue
        y = GENOME_EXT_RE.sub("", x)
        if y != x:
            x = y
            continue
        break
    return x


def normalize_mag(x):
    if x is None:
        return None
    x = x.strip()
    if not x:
        return None
    x = os.path.basename(x)
    x = strip_ext(x)
    x = PREFIX_RE.sub("", x)
    x = x.strip("_.-")
    return x.lower()


def seq_hash(seq):
    """64-bit 序列哈希, 用于组内精确去重 (碰撞率极低)。"""
    return int.from_bytes(hashlib.blake2b(seq.encode("utf-8"), digest_size=8).digest(), "big")


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
    """MAG(归一化) -> set(Sample); Sample -> set(MAG)。"""
    mag_samples, sample_mags = {}, {}
    if not os.path.exists(path):
        print(f"  [警告] 找不到 MAG_Sample_Mapping: {path}")
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
                                ["sample", "sample_id", "sampleid", "samples", "strain", "isolate", "biosample", "sample_name", "sampleid"],
                                default=1)
    ncols = max(len(header), max(len(r) for r in rows))
    if mag_col is None or mag_col >= ncols:
        mag_col = 0
    if sample_col is None or sample_col >= ncols:
        sample_col = 1

    print(f"  识别 MAG 列=#{mag_col}({header[mag_col] if mag_col < len(header) else '?'}) "
          f"Sample列=#{sample_col}({header[sample_col] if sample_col < len(header) else '?'})")

    for r in rows[1:]:
        if mag_col >= len(r) or sample_col >= len(r):
            continue
        mag = normalize_mag(r[mag_col])
        raw = r[sample_col]
        if not mag:
            continue
        if sample_sep:
            parts = [p for p in re.split(sample_sep, raw) if p]
        else:
            parts = [p for p in re.split(r"[,\t; ]+", raw) if p]
        for s in parts:
            s = s.strip()
            if not s:
                continue
            mag_samples.setdefault(mag, set()).add(s)
            sample_mags.setdefault(s, set()).add(mag)

    print(f"  MAG 总数: {len(mag_samples)}   样本总数: {len(sample_mags)}")
    return mag_samples, sample_mags, set(sample_mags.keys())


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
                                 ["match", "is_matched", "matched", "matched_265", "matched265", "match_265"],
                                 default=None)
    ncols = max(len(header), max(len(r) for r in rows))
    print(f"  识别 Sample列=#{sample_col}({header[sample_col] if sample_col < len(header) else '?'}) "
          f"Stage列=#{stage_col}({header[stage_col] if stage_col < len(header) else '?'}) "
          f"Matched列=#{matched_col}({header[matched_col] if matched_col is not None and matched_col < len(header) else '无'})")

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


def build_group_mags(cohort_samples, sample_mags):
    """cohort_id -> group -> set(MAG)。"""
    out = {}
    for cid, gs in cohort_samples.items():
        gm = {}
        for gname, ss in gs.items():
            mags = set()
            for s in ss:
                mags |= sample_mags.get(s, set())
            gm[gname] = mags
        out[cid] = gm
    return out


def iter_orffile(path):
    """流式产出一条条 (header, seq)。"""
    header, seq = None, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if header is not None:
                    yield header, "".join(seq)
                header = line.strip()
                seq = []
            else:
                if header is not None:
                    seq.append(line.strip())
        if header is not None:
            yield header, "".join(seq)


def main():
    ap = argparse.ArgumentParser(description="v2: 从每-MAG ORF 文件直接生成四队列分组总 FASTA")
    ap.add_argument("--sorf-dir", required=True, help="含 *__bin.*.fa.orf.fa 文件的目录 (sorf_output)")
    ap.add_argument("--mag-sample", default="MAG_Sample_Mapping.tsv", help="MAG->样本 映射 TSV")
    ap.add_argument("--meta", default="Sample_Group_Mapping.tsv", help="样本->分组 元数据 TSV")
    ap.add_argument("--catalog", default=None,
                    help="可选: 现有 final_sORF_Catalog.unique.fa。给出则总库直接引用它; 否则由 per-MAG 文件去重得出")
    ap.add_argument("--outdir", default="sorf_grouped_catalog", help="输出目录")
    ap.add_argument("--mag-col", type=int, default=None)
    ap.add_argument("--sample-col", type=int, default=None)
    ap.add_argument("--stage-col", type=int, default=None)
    ap.add_argument("--matched-col", type=int, default=None)
    ap.add_argument("--copy-total", action="store_true", help="总库做真实拷贝而非链接")
    ap.add_argument("--total-name", default="sORF_All_Total.fa")
    ap.add_argument("--no-dedup", action="store_true", help="关闭组内序列去重")
    ap.add_argument("--dry-run", action="store_true", help="只诊断, 不写文件")
    args = ap.parse_args()

    if not os.path.isdir(args.sorf_dir):
        sys.exit(f"错误: 找不到 --sorf-dir: {args.sorf_dir}")

    print("=" * 78)
    print(" v2: 从 per-MAG ORF 文件构建四队列分组总 FASTA" + ("  [DRY-RUN]" if args.dry_run else ""))
    print("=" * 78)
    print(f"[输入] sorf-dir   : {args.sorf_dir}")
    print(f"[输入] MAG->样本  : {args.mag_sample}")
    print(f"[输入] 样本->分组 : {args.meta}")
    print(f"[输入] catalog    : {args.catalog or '(无, 由 per-MAG 文件去重得出)'}")
    if not args.dry_run:
        os.makedirs(args.outdir, exist_ok=True)

    # per-MAG ORF 文件列表 (primary glob + 备用 glob 取并集去重)
    orf_files = sorted(set(glob.glob(os.path.join(args.sorf_dir, ORF_FILE_GLOB)))
                       | set(glob.glob(os.path.join(args.sorf_dir, ORF_FILE_GLOB_ANY))))
    print(f"\n  匹配到 per-MAG ORF 文件数: {len(orf_files)}")
    if len(orf_files) == 0:
        print("  ⚠️  未匹配到 *__bin.*.fa.orf.fa / *.orf.fa。请确认 --sorf-dir 正确。列出前 20 个文件:")
        for f in sorted(glob.glob(os.path.join(args.sorf_dir, "*")))[:20]:
            print("      " + f)
        sys.exit(1)

    print("\n[1/3] 读取 MAG->样本 映射 ...")
    mag_samples, sample_mags, all_samples = read_mag_sample(
        args.mag_sample, args.mag_col, args.sample_col)

    print("\n[2/3] 读取 样本->分组 元数据 ...")
    meta = read_sample_meta(args.meta, args.sample_col, args.stage_col, args.matched_col)
    n_matched = sum(1 for _, (_, m) in meta.items() if m)
    print(f"  样本总数: {len(meta)}   匹配265: {n_matched}")

    print("\n[3/3] 构造队列 -> 组 的样本/MAG ...")
    cohort_samples = {}
    cohort_mags = {}
    for c in COHORTS:
        g_samples = build_group_samples(meta, c["slice"], c["mode"])
        cohort_samples[c["id"]] = g_samples
        cohort_mags[c["id"]] = build_group_mags({c["id"]: g_samples}, sample_mags)[c["id"]]
        print(f"    {c['id']:9s} 组数={len(g_samples)} 样本数={sum(len(v) for v in g_samples.values()):5d} "
              f"组内MAG合计={sum(len(v) for v in cohort_mags[c['id']].values())}")

    # 为每个 MAG 计算出它要写入的组 (cohort, group) 列表
    mag_to_groups = {}
    for c in COHORTS:
        gm = cohort_mags[c["id"]]
        for gname, mags in gm.items():
            for m in mags:
                mag_to_groups.setdefault(m, set()).add((c["id"], gname))
    print(f"  去重后需要处理的 MAG 数: {len(mag_to_groups)}")

    if args.dry_run:
        print("\n[DRY-RUN] 打印 per-MAG 文件样例与匹配 (不写文件):")
        shown = 0
        unmatched = []
        for f in orf_files:
            mag = normalize_mag(os.path.basename(f))
            grps = mag_to_groups.get(mag)
            if shown < 6:
                print(f"    {os.path.basename(f):45s} -> MAG={mag!r} 组数={len(grps) if grps else 0}")
                shown += 1
            if not grps:
                unmatched.append((f, mag))
        if unmatched:
            print(f"  ⚠️  有 {len(unmatched)} 个 MAG 文件未能在映射表中找到归属:")
            for f, m in unmatched[:8]:
                print(f"      {os.path.basename(f)} -> MAG={m!r}")
        print("\n  DRY-RUN 结束。若匹配正常, 去掉 --dry-run 重跑。")
        return

    # ============ 正式切分 ============
    # 为每个 MAG 记录它属于哪个 cohort 的哪个组 (mags -> list of (cid, group))
    # 逐 cohort 处理以降低峰值内存: 每个 cohort 只保留它自己的 seen 去重集合。
    total_path = os.path.join(args.outdir, args.total_name)
    total_records = None   # 总库肽段数 (catalog 引用时未知, 置 None)

    # 总库: 若给 --catalog 直接引用(拷贝/硬链接), 否则由 per-MAG 文件流式去重得出
    if args.catalog and os.path.exists(args.catalog):
        try:
            if args.copy_total:
                import shutil; shutil.copyfile(args.catalog, total_path)
                print(f"  总库 [拷贝] -> {total_path}")
            else:
                os.link(args.catalog, total_path)
                print(f"  总库 [硬链接] -> {total_path}")
        except (OSError, NotImplementedError):
            import shutil; shutil.copyfile(args.catalog, total_path)
            print(f"  总库 [拷贝] -> {total_path}")
    else:
        print(f"  [信息] 未提供 --catalog, 总库将由 per-MAG 文件流式去重得出 -> {total_path}")
        total_write = open(total_path, "w")
        total_seen = set() if not args.no_dedup else None
        total_records = 0

    n_written_groups = 0
    count = {}   # (cid, gname) -> int
    sample_header_shown = [0]

    # 每个 cohort 单独跑一遍所有 ORF 文件 (内存: 只保留该 cohort 的 seen 集)
    for c in COHORTS:
        cid = c["id"]
        folder = os.path.join(args.outdir, c["folder"])
        os.makedirs(folder, exist_ok=True)
        handles, seen, cnt = {}, {}, {}
        for gname in cohort_mags[cid]:
            k = (cid, gname)
            fname = f"{cid}_{gname}.fa"
            handles[k] = open(os.path.join(folder, fname), "w")
            seen[k] = set() if not args.no_dedup else None
            cnt[k] = 0
        n_files = len(orf_files)
        t0 = time.time()
        for idx, f in enumerate(orf_files):
            mag = normalize_mag(os.path.basename(f))
            # 该 MAG 在本 cohort 属于哪个组 (每 cohort 至多一组)
            grp = None
            for gname, mags in cohort_mags[cid].items():
                if mag in mags:
                    grp = gname
                    break
            if grp is None:
                continue
            k = (cid, grp)
            for header, seq in iter_orffile(f):
                if sample_header_shown[0] < 4:
                    print(f"    [样例] {os.path.basename(f)}: {header[:80]}")
                    sample_header_shown[0] += 1
                if not args.no_dedup:
                    h = seq_hash(seq)
                    if h in seen[k]:
                        continue
                    seen[k].add(h)
                hs = handles[k]
                hs.write(header); hs.write("\n")
                hs.write(seq); hs.write("\n")
                cnt[k] += 1
                n_written_groups += 1
                # 若总库由 per-MAG 去重得出, 在这里累加 (遇到即写, seen 跨 cohort 共享, 只收一次)
                if total_records is not None:
                    if not args.no_dedup:
                        h = seq_hash(seq)
                        if h in total_seen:
                            continue
                        total_seen.add(h)
                    total_write.write(header); total_write.write("\n")
                    total_write.write(seq); total_write.write("\n")
                    total_records += 1
            # 进度
            if (idx + 1) % max(1, n_files // 10) == 0 or (idx + 1) == n_files:
                el = time.time() - t0
                print(f"    [进度] {cid} 已处理 MAG {idx+1}/{n_files}  (用时 {el:.0f}s, 当前该组已写 {cnt[k]:,})", flush=True)
        for h in handles.values():
            h.close()
        count.update(cnt)
        el = time.time() - t0
        print(f"    [完成] {cid} 用时 {el:.0f}s  " + ", ".join(
            f"{g}={cnt[(cid, g)]:,}" for g in cohort_mags[cid]))

    if total_records is not None:
        total_write.close()

    # manifest
    print("\n[输出] group_manifest.tsv ...")
    manifest = os.path.join(args.outdir, "group_manifest.tsv")
    with open(manifest, "w") as mf:
        mf.write("\t".join(["Cohort", "Group", "FASTA_file", "N_sORF", "N_MAG", "N_Sample", "File_size"]))
        mf.write("\n")
        for c in COHORTS:
            folder = os.path.join(args.outdir, c["folder"])
            for gname in cohort_mags[c["id"]]:
                k = (c["id"], gname)
                fname = f"{c['id']}_{gname}.fa"
                fpath = os.path.join(folder, fname)
                size = os.path.getsize(fpath) if os.path.exists(fpath) else 0
                mf.write("\t".join([c["id"], gname, fname, str(count[k]),
                                   str(len(cohort_mags[c["id"]][gname])),
                                   str(len(cohort_samples[c["id"]][gname])), str(size)]))
                mf.write("\n")
        tot_size = os.path.getsize(total_path) if os.path.exists(total_path) else 0
        tot_ct = total_records if total_records is not None else "-"
        mf.write("\t".join(["All", "Total", args.total_name, str(tot_ct),
                           str(len(mag_to_groups)), str(len(all_samples)), str(tot_size)]))
        mf.write("\n")

    print(f"\n  写出组内肽段 (去重跨组/跨cohort) : {n_written_groups:,}")
    if total_records is not None:
        print(f"  总库肽段数 (per-MAG 去重)       : {total_records:,}")
    else:
        print(f"  总库: 引用 --catalog (sORF_All_Total.fa 内容即 final_sORF_Catalog.unique.fa)")
    for c in COHORTS:
        print(f"    {c['id']}: " + ", ".join(
            f"{g}={count[(c['id'], g)]:,}" for g in cohort_mags[c["id"]]))

    print("\n完成! 分组总 FASTA 位于 (整目录打包下载即可):")
    print("  " + os.path.abspath(args.outdir))
    print(f"  分组清单: {manifest}")


if __name__ == "__main__":
    main()
