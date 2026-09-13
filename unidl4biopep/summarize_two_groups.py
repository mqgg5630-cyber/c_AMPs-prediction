#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Healthy_Specific 与 Periodontitis_Specific 的 22 模型结果整理成两张表。"""

import argparse
import os
import sys

import pandas as pd

DATASETS = ["Healthy_Specific", "Periodontitis_Specific"]


def parse_args():
    ap = argparse.ArgumentParser(
        description="汇总健康人组和牙周炎组 22 个模型的独立筛选结果",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("results_dir", help="预测结果根目录")
    ap.add_argument(
        "--outdir", default=None,
        help="汇总表输出目录，默认与 results_dir 相同",
    )
    return ap.parse_args()


def main():
    args = parse_args()
    results_dir = os.path.abspath(args.results_dir)
    outdir = os.path.abspath(args.outdir or results_dir)
    os.makedirs(outdir, exist_ok=True)

    output_paths = []
    for dataset in DATASETS:
        source = os.path.join(
            results_dir,
            f"{dataset}_SingleActivity_gt0.8",
            "single_activity_summary.csv",
        )
        if not os.path.isfile(source):
            print(f"❌ 找不到 {dataset} 的汇总表: {source}", file=sys.stderr)
            print("请先完成该数据集的 22 模型独立提取。", file=sys.stderr)
            return 1

        df = pd.read_csv(source)
        required = {"model_no", "activity", "prob_column", "input_n",
                    "rows_gt_threshold", "fasta_n"}
        missing = required.difference(df.columns)
        if missing:
            print(f"❌ {source} 缺少列: {sorted(missing)}", file=sys.stderr)
            return 1

        # 同一组内每个模型的 input_n 应相同；这里按每个模型实际 input_n 计算比例。
        df["hit_rate_pct"] = (
            df["rows_gt_threshold"] / df["input_n"] * 100
        ).round(4)
        columns = [
            "model_no", "activity", "prob_column", "input_n",
            "rows_gt_threshold", "hit_rate_pct", "fasta_n",
            "fasta_file", "hits_csv",
        ]
        columns = [c for c in columns if c in df.columns]
        output = os.path.join(
            outdir, f"{dataset}_model_summary_gt0.8.csv")
        df[columns].to_csv(output, index=False)
        output_paths.append(output)

        print("\n" + "=" * 100)
        print(f"📊 {dataset}")
        print("=" * 100)
        print(df[columns].to_string(index=False))
        print(f"\n已写入: {output}")

    print("\n✅ 两张汇总表已生成:")
    for path in output_paths:
        print(f"   {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
