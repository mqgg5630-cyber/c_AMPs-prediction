#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=================================================================================
 UniDL4BioPep: 提取牙周炎组中「单个模型 prob > 阈值」的肽段
=================================================================================

与 extract_multiact_hits.py 不同，本脚本不是要求 22 个模型同时超过阈值，
而是把 22 个模型分别处理：某个模型的 prob > 0.8，就把该肽段写入该模型
自己的 FASTA 文件。例如：

    1._ACE_inhibitory_activity_prob > 0.8

满足的肽段写入 ACE 模型的 FASTA；其他 21 个模型分别独立统计。

默认只处理 Periodontitis_Specific（牙周炎组），默认严格使用 > 0.8。
输入 CSV 会分块读取，并且只载入 sequence、ID 和 prob 列，适合大文件。

默认输出：
    <results_dir>/Periodontitis_Specific_SingleActivity_gt0.8/
    ├── fasta/                         # 22 个模型各一个 FASTA
    ├── csv/                           # 22 个模型各一个命中明细 CSV
    ├── single_activity_summary.csv    # 22 个模型的汇总数量
    └── per_batch_counts.csv           # 每个 batch、每个模型的数量

依赖：pandas（其余为 Python 标准库）。
=================================================================================
"""

import argparse
import csv
import os
import re
import sys

import pandas as pd

# 用户这次预测中 22 个模型的 prob 列前缀，顺序与预测结果中的模型顺序一致。
EXPECTED_ACTIVITIES = [
    "1._ACE_inhibitory_activity",
    "2._DPPIV_inhibitory_activity",
    "3._Bitter",
    "4._Umami",
    "5._Antimicrobial_activity",
    "6._Antimalarial_activity-alternative",
    "6._Antimalarial_activity-main",
    "7._Quorum_sensing_activity",
    "8._ACP_Anticancer_activity-main",
    "8._ACP_Anticancer_activity-alternative",
    "9._Anti-MRSA_strains_activity",
    "10._TTCA",
    "11._BBP_Blood-Brain_Barrier_Peptides",
    "12._APP__Anti-parasitic",
    "13.NeuroPred",
    "14._antibacterial_AB",
    "15._Antifungal_AF",
    "16._AV_Antiviral",
    "17._Toxicity_2021_Dataset",
    "18._antioxidant_FRS",
    "19._allergenicity",
    "20._CPP_cell_penerationg_peptide",
]

ID_COL_CANDIDATES = [
    "id", "name", "sequence_id", "seq_id", "peptide_id", "peptide",
    "fasta_id", "mag", "magid", "sorf", "sorf_id", "uniprot",
]


def parse_args():
    ap = argparse.ArgumentParser(
        description="分别提取牙周炎组 22 个模型 prob > 阈值的肽段",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument(
        "results_dir",
        help="预测结果根目录（含 Periodontitis_Specific 子目录）",
    )
    ap.add_argument(
        "--dataset",
        default="Periodontitis_Specific",
        help="要处理的数据集子目录",
    )
    ap.add_argument("--threshold", type=float, default=0.8,
                    help="概率阈值")
    ap.add_argument("--inclusive", action="store_true",
                    help="使用 >= 阈值；默认是严格 > 阈值")
    ap.add_argument("--chunksize", type=int, default=100_000,
                    help="每次读取 CSV 的行数，用于降低内存占用")
    ap.add_argument("--outdir", default=None,
                    help="输出目录，默认写在 results_dir 下")
    ap.add_argument(
        "--dedup", action="store_true",
        help="每个模型按 sequence 去重；默认保留每个满足条件的输入记录",
    )
    return ap.parse_args()


def batch_sort_key(fname):
    m = re.search(r"batch[_-]?(\d+)", fname)
    return (int(m.group(1)) if m else 10 ** 9, fname)


def pick_id_col(columns):
    lower_map = {str(c).lower(): c for c in columns}
    for candidate in ID_COL_CANDIDATES:
        if candidate in lower_map and str(lower_map[candidate]).lower() != "sequence":
            return lower_map[candidate]
    return None


def clean_seq(value):
    return re.sub(r"\s+", "", str(value))


def safe_filename(name):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


def inspect_batch(path):
    """读取表头，返回 (prob_columns, id_col, usecols)。"""
    header = pd.read_csv(path, nrows=0)
    columns = list(header.columns)
    if "sequence" not in columns:
        raise ValueError(
            f"缺少 sequence 列: {path}\n实际列: {columns[:10]} ...")

    all_prob_cols = [c for c in columns if str(c).endswith("_prob")]
    expected_pairs = [
        (activity, f"{activity}_prob")
        for activity in EXPECTED_ACTIVITIES
        if f"{activity}_prob" in columns
    ]

    # 正常情况下使用预先定义的 22 个模型顺序；若列名有变化，则退回到 CSV 中
    # 实际检测到的所有 *_prob 列，并在屏幕上给出警告。
    if len(expected_pairs) == len(EXPECTED_ACTIVITIES):
        pairs = expected_pairs
    else:
        print(
            f"  ⚠️ {os.path.basename(path)}: 预期 22 个模型列只找到 "
            f"{len(expected_pairs)} 个，将使用实际检测到的 {len(all_prob_cols)} 个 *_prob 列",
            flush=True,
        )
        pairs = [(str(c)[:-len("_prob")], c) for c in all_prob_cols]

    prob_cols = [(activity, col) for activity, col in pairs]
    id_col = pick_id_col(columns)
    usecols = ["sequence"]
    if id_col is not None and id_col not in usecols:
        usecols.append(id_col)
    usecols.extend(col for _, col in prob_cols if col not in usecols)
    return prob_cols, id_col, usecols


def main():
    args = parse_args()
    if args.chunksize <= 0:
        sys.exit("❌ --chunksize 必须是大于 0 的整数")

    results_dir = os.path.abspath(args.results_dir)
    dataset_dir = os.path.join(results_dir, args.dataset)
    if not os.path.isdir(dataset_dir):
        sys.exit(f"❌ 数据集目录不存在: {dataset_dir}")

    op = ">=" if args.inclusive else ">"
    tag = f"gt{args.threshold:g}"
    outdir = args.outdir or os.path.join(
        results_dir, f"{args.dataset}_SingleActivity_{tag}")
    fasta_dir = os.path.join(outdir, "fasta")
    csv_dir = os.path.join(outdir, "csv")
    os.makedirs(fasta_dir, exist_ok=True)
    os.makedirs(csv_dir, exist_ok=True)

    files = sorted(
        [f for f in os.listdir(dataset_dir) if f.endswith("_Predictions.csv")],
        key=batch_sort_key,
    )
    if not files:
        sys.exit(f"❌ 没找到预测文件: {dataset_dir}/*_Predictions.csv")

    # 先检查第一个 batch，确定本次使用的模型列和输出文件名。
    try:
        prob_pairs, first_id_col, _ = inspect_batch(
            os.path.join(dataset_dir, files[0]))
    except Exception as exc:
        sys.exit(f"❌ 无法读取首个 batch: {exc}")

    if not prob_pairs:
        sys.exit("❌ 没有找到任何 *_prob 列")

    activities = [activity for activity, _ in prob_pairs]
    activity_to_col = dict(prob_pairs)
    print(f"📁 结果目录 : {results_dir}")
    print(f"📂 数据集   : {args.dataset}")
    print(f"🎯 筛选规则 : 每个模型分别统计 prob {op} {args.threshold}")
    print(f"🔢 模型数   : {len(activities)}")
    print(f"📁 输出目录 : {outdir}")
    print(f"💾 读取方式 : 分块读取，每块 {args.chunksize} 行")
    print(f"🔁 去重     : {'是' if args.dedup else '否（保留每条满足条件的记录）'}\n")

    # 每个模型分别打开一个 FASTA 和一个明细 CSV，边读取边写出，避免把大量
    # 命中序列全部放进内存。--dedup 时只额外保存当前模型的 sequence 集合。
    handles = {}
    writers = {}
    seen = {activity: set() for activity in activities} if args.dedup else None
    fasta_paths = {}
    csv_paths = {}
    for number, activity in enumerate(activities, start=1):
        stem = f"{number:02d}_{safe_filename(activity)}_{tag}"
        fasta_path = os.path.join(fasta_dir, stem + ".fasta")
        csv_path = os.path.join(csv_dir, stem + "_hits.csv")
        fasta_fh = open(fasta_path, "w", encoding="utf-8")
        fasta_fh.write(
            f"; {args.dataset}; model={activity}; prob {op} {args.threshold}; "
            f"dedup={args.dedup}\n"
        )
        csv_fh = open(csv_path, "w", encoding="utf-8", newline="")
        writer = csv.writer(csv_fh)
        writer.writerow(["fasta_header", "sequence", "prob", "source_batch"])
        handles[activity] = (fasta_fh, csv_fh)
        writers[activity] = writer
        fasta_paths[activity] = fasta_path
        csv_paths[activity] = csv_path

    raw_totals = {activity: 0 for activity in activities}
    fasta_totals = {activity: 0 for activity in activities}
    input_totals = {activity: 0 for activity in activities}
    batch_rows = []

    try:
        for file_number, fname in enumerate(files, start=1):
            path = os.path.join(dataset_dir, fname)
            batch = fname[:-len("_Predictions.csv")]
            batch_raw = {activity: 0 for activity in activities}
            batch_fasta = {activity: 0 for activity in activities}
            n_in = 0
            try:
                prob_pairs_now, id_col, usecols = inspect_batch(path)
                reader = pd.read_csv(
                    path,
                    usecols=usecols,
                    chunksize=args.chunksize,
                    keep_default_na=False,
                    low_memory=False,
                )
                for df in reader:
                    n_in += len(df)
                    for activity in activities:
                        col = activity_to_col[activity]
                        if col not in df.columns:
                            continue
                        values = pd.to_numeric(df[col], errors="coerce")
                        mask = values.ge(args.threshold) if args.inclusive else values.gt(args.threshold)
                        batch_raw[activity] += int(mask.sum())

                        for idx, row in df.loc[mask].iterrows():
                            seq = clean_seq(row["sequence"])
                            if not seq:
                                continue
                            if seen is not None:
                                if seq in seen[activity]:
                                    continue
                                seen[activity].add(seq)
                            if id_col is not None:
                                pid = str(row[id_col]).strip() or f"row{idx}"
                            else:
                                pid = f"{args.dataset}_{batch}_row{idx}"
                            prob = float(values.loc[idx])
                            header = (
                                f"{pid} | dataset={args.dataset} batch={batch} "
                                f"model={activity} prob={prob:.6f}"
                            )
                            fasta_fh, csv_fh = handles[activity]
                            fasta_fh.write(f">{header}\n{seq}\n")
                            writers[activity].writerow(
                                [header, seq, f"{prob:.6f}", batch]
                            )
                            batch_fasta[activity] += 1
            except Exception as exc:
                print(f"  ⚠️ {fname} 读取失败，跳过: {exc}", flush=True)
                for activity in activities:
                    batch_rows.append([
                        args.dataset, batch, n_in, activity,
                        batch_raw[activity], batch_fasta[activity], "READ_ERROR",
                    ])
                continue

            available_cols = {col for _, col in prob_pairs_now}
            missing = [activity for activity in activities
                       if activity_to_col[activity] not in available_cols]
            status = "MISSING_PROB" if missing else "OK"
            if missing:
                print(f"  ⚠️ {batch}: 缺少 {len(missing)} 个模型 prob 列", flush=True)

            for activity in activities:
                input_totals[activity] += n_in
                raw_totals[activity] += batch_raw[activity]
                fasta_totals[activity] += batch_fasta[activity]
                batch_rows.append([
                    args.dataset, batch, n_in, activity,
                    batch_raw[activity], batch_fasta[activity], status,
                ])

            total_exported = sum(batch_fasta.values())
            print(
                f"  ✅ [{file_number}/{len(files)}] {batch}: "
                f"{n_in} 条输入，22 模型合计导出 {total_exported} 条",
                flush=True,
            )
    finally:
        for fasta_fh, csv_fh in handles.values():
            fasta_fh.close()
            csv_fh.close()

    summary_rows = []
    for number, activity in enumerate(activities, start=1):
        summary_rows.append([
            number,
            activity,
            activity_to_col[activity],
            input_totals[activity],
            raw_totals[activity],
            fasta_totals[activity],
            os.path.relpath(fasta_paths[activity], outdir),
            os.path.relpath(csv_paths[activity], outdir),
        ])

    summary_path = os.path.join(outdir, "single_activity_summary.csv")
    pd.DataFrame(
        summary_rows,
        columns=[
            "model_no", "activity", "prob_column", "input_n",
            "rows_gt_threshold", "fasta_n", "fasta_file", "hits_csv",
        ],
    ).to_csv(summary_path, index=False)

    batch_path = os.path.join(outdir, "per_batch_counts.csv")
    pd.DataFrame(
        batch_rows,
        columns=[
            "dataset", "batch", "input_n", "activity",
            "rows_gt_threshold", "fasta_n", "status",
        ],
    ).to_csv(batch_path, index=False)

    summary_df = pd.read_csv(summary_path)
    print("\n" + "=" * 100)
    print("📊 牙周炎组：22 个模型分别 prob > 阈值的统计")
    print("=" * 100)
    print(summary_df.to_string(index=False))
    print("\n✅ 完成")
    print(f"   22 个 FASTA: {fasta_dir}")
    print(f"   22 个命中明细 CSV: {csv_dir}")
    print(f"   汇总表: {summary_path}")
    print(f"   每 batch 统计: {batch_path}")


if __name__ == "__main__":
    main()
