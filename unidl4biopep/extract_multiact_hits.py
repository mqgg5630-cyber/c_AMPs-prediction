#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=================================================================================
 UniDL4BioPep 22 活性预测: 提取「22 种活性概率全部 > 阈值」的肽段 (FASTA) + 数量统计表
=================================================================================

输入 (UniDL4BioPep 预测主循环的产物, 目录结构):
----
Predictions_Results_With_Probability_XXXXXXXX_XXXXXX/
├── Healthy_Specific/
│   ├── healthy_batch_1_Predictions.csv
│   ├── ...
│   └── healthy_batch_25_Predictions.csv
└── Periodontitis_Specific/
    ├── perio_batch_1_Predictions.csv
    └── ...

每个 CSV 里必须有 sequence 列, 以及 22 个活性各自的
{活性名}_prob / {活性名}_class / {活性名}_filtered 三列
(活性数 = 1~20, 其中 6 号与 8 号各有 main/alternative 两个版本, 合计 22)。

筛选规则
--------
某条肽段只有当【全部 22 个】{活性名}_prob 都严格大于阈值 (默认 0.8) 时才被提取。
若某个 batch 的 prob 列少于 22 个 (说明该批有模型预测失败), 该 batch 视为不完整,
不产生 FASTA 命中, 只在统计表中标记 status=INCOMPLETE。

输出 (默认写到 <results_dir>/MultiAct_Extraction_gt0.8/):
----
├── <dataset>_gt0.8_multiact.fasta              # 该数据集全量命中 FASTA (默认按序列去重)
├── <dataset>_gt0.8_multiact_hits.csv           # 命中明细: header / 序列 / min_prob / 来源 batch
├── per_batch/<dataset>/<batch>_gt0.8.fasta     # 按 batch 拆分的 FASTA
├── summary_count_table.csv                     # 数量统计表: 每个 (数据集, batch) 一行 + 汇总行
└── per_activity_hits_gt0.8.csv                 # 每个活性单独的 prob>阈值 数量 (22 x 2 数据集)

用法
----
    python3 extract_multiact_hits.py \
        /home/wsh/UniDL4BioPep-main/Predictions_Results_With_Probability_20260604_204744

    # 换阈值 0.7
    python3 extract_multiact_hits.py <results_dir> --threshold 0.7

    # 用 >= 阈值 (而不是严格 >)
    python3 extract_multiact_hits.py <results_dir> --inclusive

    # 输出到别处 / 只跑某个数据集 / 不去重
    python3 extract_multiact_hits.py <results_dir> \
        --outdir /path/to/out --datasets Healthy_Specific --no-dedup

依赖: pandas (其余均为标准库)。
=================================================================================
"""

import argparse
import os
import re
import sys

import pandas as pd

EXPECTED_ACTIVITIES = 22   # 1~20 号模型, 6/8 号各含 main+alternative, 共 22 个 prob 列

# 按优先级尝试的「肽段 ID」列 (忽略大小写匹配, 命中即用, 找不到则自动编号)
ID_COL_CANDIDATES = [
    "id", "name", "sequence_id", "seq_id", "peptide_id", "peptide",
    "fasta_id", "mag", "magid", "sorf", "sorf_id", "uniprot",
]


# ----------------------------------------------------------------------
# 工具函数
# ----------------------------------------------------------------------

def parse_args():
    ap = argparse.ArgumentParser(
        description="提取 22 种活性概率全部 > 阈值的肽段为 FASTA, 并输出数量统计表",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("results_dir",
                    help="预测结果根目录 (含 Healthy_Specific/ 与 Periodontitis_Specific/)")
    ap.add_argument("--threshold", type=float, default=0.8,
                    help="概率阈值, 默认 0.8")
    ap.add_argument("--inclusive", action="store_true",
                    help="使用 >= 阈值 (默认是严格 > 阈值)")
    ap.add_argument("--require-cols", type=int, default=EXPECTED_ACTIVITIES,
                    help="prob 列少于该数目的 batch 视为不完整, 不产生命中")
    ap.add_argument("--outdir", default=None,
                    help="输出目录, 默认 <results_dir>/MultiAct_Extraction_gt<阈值>")
    ap.add_argument("--datasets", nargs="*", default=None, metavar="NAME",
                    help="只处理指定的数据集子目录 (如 Healthy_Specific)")
    ap.add_argument("--no-dedup", action="store_true",
                    help="合并 FASTA 时不按序列去重 (默认去重, 保留 min_prob 最高的一条)")
    return ap.parse_args()


def batch_sort_key(fname):
    """按文件名里的 batch 数字排序: healthy_batch_1_Predictions.csv -> 1"""
    m = re.search(r"batch[_-]?(\d+)", fname)
    return (int(m.group(1)) if m else 10 ** 9, fname)


def pick_id_col(df):
    """在 df 里找一个像 ID 的列 (忽略大小写), 找不到返回 None。"""
    lower_map = {str(c).lower(): c for c in df.columns}
    for cand in ID_COL_CANDIDATES:
        if cand in lower_map and lower_map[cand].lower() != "sequence":
            return lower_map[cand]
    return None


def clean_seq(s):
    return re.sub(r"\s+", "", str(s))


def find_dataset_dirs(results_dir, only=None):
    """扫描 results_dir 下含 *_Predictions.csv 的子目录, 返回 {dirname: [files]}"""
    dirs = {}
    for d in sorted(os.listdir(results_dir)):
        p = os.path.join(results_dir, d)
        if not os.path.isdir(p):
            continue
        files = [f for f in os.listdir(p) if f.endswith("_Predictions.csv")]
        if not files:
            continue
        if only is not None and d not in only:
            continue
        dirs[d] = sorted(files, key=batch_sort_key)
    return dirs


def load_batch(path):
    """读取一个 batch 的预测 CSV, 返回 (df, prob_cols)"""
    df = pd.read_csv(path, keep_default_na=False, low_memory=False)
    if "sequence" not in df.columns:
        raise ValueError(
            f"缺少 sequence 列: {path}\n实际列: {list(df.columns)[:10]} ...")
    prob_cols = [c for c in df.columns if str(c).endswith("_prob")]
    for c in prob_cols:
        df[c] = pd.to_numeric(df[c], errors="coerce")   # 非数字 -> NaN, NaN 不算命中
    return df, prob_cols


def write_fasta(path, records, comment):
    """records: [(header, seq)]"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(f"; {comment}\n")
        for header, seq in records:
            fh.write(f">{header}\n")
            fh.write(f"{seq}\n")


# ----------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------

def main():
    args = parse_args()

    results_dir = os.path.abspath(args.results_dir)
    if not os.path.isdir(results_dir):
        sys.exit(f"❌ 结果目录不存在: {results_dir}")

    th = args.threshold
    op = ">=" if args.inclusive else ">"
    tag = f"gt{th:g}"

    outdir = args.outdir or os.path.join(
        results_dir, f"MultiAct_Extraction_{tag}")
    os.makedirs(outdir, exist_ok=True)

    dataset_dirs = find_dataset_dirs(results_dir, args.datasets)
    if not dataset_dirs:
        sys.exit("❌ 没找到任何含 *_Predictions.csv 的数据集子目录")

    print(f"📁 结果目录 : {results_dir}")
    print(f"🎯 筛选规则 : {EXPECTED_ACTIVITIES} 个活性 prob 全部 {op} {th}")
    print(f"📁 输出目录 : {outdir}")
    print(f"📂 数据集   : {', '.join(dataset_dirs)}\n")

    summary_rows = []          # 数量统计表
    activity_rows = []         # 每活性命中统计

    for ds_name, files in dataset_dirs.items():
        ds_hits = []           # (seq, min_prob, header, source_batch)
        ds_input_total = 0

        print(f"{'=' * 70}")
        print(f"🔬 {ds_name}  ({len(files)} 个 batch)")
        print(f"{'=' * 70}")

        for fname in files:
            fpath = os.path.join(results_dir, ds_name, fname)
            stem = fname[:-len("_Predictions.csv")]
            try:
                df, prob_cols = load_batch(fpath)
            except Exception as e:
                print(f"  ⚠️ {fname} 读取失败, 跳过: {e}")
                summary_rows.append([ds_name, stem, 0, 0, 0, "READ_ERROR"])
                continue

            n_in = len(df)
            ds_input_total += n_in
            id_col = pick_id_col(df)
            incomplete = len(prob_cols) < args.require_cols

            if incomplete:
                print(f"  ⚠️ {stem}: 只有 {len(prob_cols)} 个 prob 列 "
                      f"(< {args.require_cols}), 视为不完整, 跳过")
                summary_rows.append(
                    [ds_name, stem, n_in, len(prob_cols), 0, "INCOMPLETE"])
                continue

            # ---------------- 每活性命中数 ----------------
            for c in prob_cols:
                act = str(c)[:-len("_prob")]
                n_act = int((df[c] >= th).sum() if args.inclusive
                            else (df[c] > th).sum())
                activity_rows.append([ds_name, act, n_in, n_act])

            # ---------------- 22 个 prob 全部超阈值 ----------------
            cmp_df = (df[prob_cols] >= th) if args.inclusive else (df[prob_cols] > th)
            mask = cmp_df.all(axis=1)
            min_prob = df[prob_cols].min(axis=1)
            n_hits = int(mask.sum())
            print(f"  ✅ {stem}: {n_in} 条序列, 22 个 prob 全部 {op} {th} "
                  f"的有 {n_hits} 条")
            summary_rows.append(
                [ds_name, stem, n_in, len(prob_cols), n_hits, "OK"])

            if n_hits == 0:
                continue

            # ---------------- 记录命中 + per-batch FASTA ----------------
            batch_records = []
            for idx, row in df[mask].iterrows():
                seq = clean_seq(row["sequence"])
                if not seq:
                    continue
                if id_col is not None:
                    pid = str(row[id_col]).strip() or f"row{idx}"
                else:
                    pid = f"{ds_name}_{stem}_row{idx}"
                mp = float(min_prob[idx])
                hdr = (f"{pid} | dataset={ds_name} batch={stem} "
                       f"min_prob={mp:.4f}")
                ds_hits.append((seq, mp, hdr, stem))
                batch_records.append((hdr, seq))

            batch_fasta = os.path.join(
                outdir, "per_batch", ds_name, f"{stem}_{tag}.fasta")
            write_fasta(batch_fasta, batch_records,
                        f"{ds_name} {stem}: 22 activities prob all {op} {th}")

        # ---------------- 数据集级合并 (默认按序列去重) ----------------
        if args.no_dedup:
            final = ds_hits
        else:
            best = {}     # seq -> (min_prob, header, source_batch)
            order = []    # 保持首次出现顺序
            for seq, mp, hdr, src in ds_hits:
                if seq not in best:
                    best[seq] = (mp, hdr, src)
                    order.append(seq)
                elif mp > best[seq][0]:
                    best[seq] = (mp, hdr, src)
            final = [(s, best[s][0], best[s][1], best[s][2]) for s in order]

        ds_fasta = os.path.join(outdir, f"{ds_name}_{tag}_multiact.fasta")
        write_fasta(
            ds_fasta, [(h, s) for s, _, h, _ in final],
            f"{ds_name}: {EXPECTED_ACTIVITIES} activities prob all {op} {th} "
            f"(dedup={not args.no_dedup})")

        ds_hits_csv = os.path.join(outdir, f"{ds_name}_{tag}_multiact_hits.csv")
        with open(ds_hits_csv, "w") as fh:
            fh.write("fasta_header,sequence,min_prob,source_batch\n")
            for seq, mp, hdr, src in final:
                fh.write(f'"{hdr}","{seq}",{mp:.4f},"{src}"\n')

        n_dedup = len(ds_hits) - len(final) if not args.no_dedup else 0
        print(f"  💾 {ds_name}: 命中 {len(final)} 条"
              + (f" (跨 batch 去重去掉 {n_dedup} 条重复序列)" if n_dedup else "")
              + f" -> {ds_fasta}\n")

        summary_rows.append([ds_name, "TOTAL", ds_input_total,
                             args.require_cols, len(final), "TOTAL"])

    # ------------------------------------------------------------------
    # 数量统计表
    # ------------------------------------------------------------------
    summary_df = pd.DataFrame(
        summary_rows,
        columns=["dataset", "batch", "input_n", "prob_cols", "hits_n", "status"])

    grand = pd.DataFrame([
        ["ALL", "GRAND_TOTAL",
         int(summary_df.loc[summary_df["status"] == "TOTAL", "input_n"].sum()),
         args.require_cols,
         int(summary_df.loc[summary_df["status"] == "TOTAL", "hits_n"].sum()),
         "GRAND"]],
        columns=summary_df.columns)
    summary_out = pd.concat([summary_df, grand], ignore_index=True)
    summary_csv = os.path.join(outdir, "summary_count_table.csv")
    summary_out.to_csv(summary_csv, index=False)

    activity_df = pd.DataFrame(
        activity_rows, columns=["dataset", "activity", "input_n", "hits_gt_th"])
    act_csv = os.path.join(outdir, f"per_activity_hits_{tag}.csv")
    activity_df.to_csv(act_csv, index=False)

    # ------------------------------------------------------------------
    # 打印
    # ------------------------------------------------------------------
    pd.set_option("display.width", 200)
    pd.set_option("display.max_rows", 200)

    print("=" * 70)
    print(f"📊 数量统计表 (22 个 prob 全部 {op} {th})")
    print("=" * 70)
    print(summary_out.to_string(index=False))

    print("\n" + "=" * 70)
    print(f"📊 每个活性单独的 prob {op} {th} 命中数")
    print("=" * 70)
    print(activity_df.to_string(index=False))

    print("\n" + "=" * 70)
    print("✅ 完成, 输出文件:")
    print(f"   {summary_csv}")
    print(f"   {act_csv}")
    for ds in dataset_dirs:
        print(f"   {os.path.join(outdir, f'{ds}_{tag}_multiact.fasta')}")
    print(f"   {os.path.join(outdir, 'per_batch')}")
    print("=" * 70)


if __name__ == "__main__":
    main()
