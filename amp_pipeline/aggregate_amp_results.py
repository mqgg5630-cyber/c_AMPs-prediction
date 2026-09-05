#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=================================================================================
 步骤二(本地): 汇总三模型预测结果 (Attention / LSTM / BERT)
=================================================================================

用途
----
在 run_pipeline_all_groups.sh 跑完之后调用, 遍历 amp_results 下的每个分组文件夹,
把三个单模型的概率文件 + 最终预测合并成:
  * 每个分组一张明细表 :  {group}/aggregated_results.tsv
        name   seq  len  att_prob  lstm_prob  bert_prob  n_votes  is_AMP  AMP_pred
  * 全部分组汇总表    : {results_root}/amp_all_peptides.tsv  (每条肽段一行, 带 group 列)
  * 分组层面摘要       : {results_root}/amp_summary.tsv      (各组预测数目/比例)

共识规则 (与官方 result.pl 完全一致)
------------------------------------
  对单条肽段, 三个模型各自给出 (0,1]:
      n_votes = (att>0.5) + (lstm>0.5) + (bert>0.5)
      若 n_votes == 3 -> is_AMP = 1 ; 否则 is_AMP = 0
    另外输出 is_AMP_flex(>=2票), 便于用户按更宽松阈值筛选。

用法
----
    python3 aggregate_amp_results.py amp_results [--threshold 0.5]
依赖: 仅标准库 (csv/os/re/argparse)。
=================================================================================
"""

import argparse
import csv
import glob
import os
import sys

STANDARD_AA = set("ACDEFGHIKLMNPQRSTVWY")

# 默认列名 (每个分组文件夹由 run_pipeline_one.sh 生成)
F_STD_COLS = ["name", "seq", "len", "att_prob", "lstm_prob", "bert_prob",
              "n_votes", "is_AMP", "AMP_pred", "is_AMP_flex"]


def read_fasta(path):
    """流式读取 FASTA, 返回 [(name, seq), ...] (只保留序列记录)。"""
    recs = []
    with open(path) as fh:
        name, seq = None, []
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if name is not None:
                    recs.append((name, "".join(seq)))
                name = line[1:].split()[0] if line[1:].strip() else line[1:]
                seq = []
            else:
                if name is not None:
                    seq.append(line.strip())
        if name is not None:
            recs.append((name, "".join(seq)))
    return recs


def read_proba(path):
    """读单列概率文件 (每行一个数值), 返回 float 列表。"""
    vals = []
    if not os.path.exists(path):
        return vals
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                vals.append(float(line))
            except ValueError:
                pass
    return vals


def is_standard_aa(seq):
    return len(seq) > 0 and all(c in STANDARD_AA for c in seq)


def process_group(group_dir, threshold, all_rows):
    """处理单个分组目录, 返回 (aggregated_rows, dict_summary)。"""
    input_fa = os.path.join(group_dir, "input.fa")
    att_p = os.path.join(group_dir, "attention_proba.tsv")
    lstm_p = os.path.join(group_dir, "lstm_proba.tsv")
    bert_p = os.path.join(group_dir, "bert_proba.tsv")

    if not all(os.path.exists(p) for p in (input_fa, att_p, lstm_p, bert_p)):
        n_recs = read_fasta(input_fa) if os.path.exists(input_fa) else []
        if n_recs:
            print(f"  [跳过] {group_dir}: 缺少必需文件 (input.fa 或 三模型概率)")
        else:
            print(f"  [跳过] {group_dir}: 输入为空或未生成, 不参与汇总")
        return [], {}

    recs = read_fasta(input_fa)
    att = read_proba(att_p)
    lstm = read_proba(lstm_p)
    bert = read_proba(bert_p)

    # format.pl 会剔除含 B/J/O/U/X/Z 的序列, 因此 Attention/LSTM 行数可能 < FASTA 记录数。
    # BERT 读取原始 FASTA (每行非'>' 为一条), 因此 BERT 行数 == 记录数。
    # 正常情况: sORF 全为标准 20 种标准AA, 三者行数一致 -> 直接按记录顺序对齐。
    att_lstm_recs = [r for r in recs if is_standard_aa(r[1])]

    # Attention/LSTM 对齐到标准AA子集 (这是它们实际看到的序列集合)
    n_al = min(len(att_lstm_recs), len(att), len(lstm))
    align_recs = att_lstm_recs[:n_al]
    att_al = att[:n_al]
    lstm_al = lstm[:n_al]

    # BERT 对齐: 优先认为它就是全部记录; 若行数不一致, 对齐到标准AA子集或截断
    if len(bert) == len(recs):
        bert_al = bert[:n_al]
    elif len(bert) == len(align_recs):
        bert_al = bert[:n_al]
    else:
        n_b = min(len(recs), len(bert), n_al)
        align_recs = align_recs[:n_b]
        att_al = att_al[:n_b]
        lstm_al = lstm_al[:n_b]
        bert_al = bert[:n_b]

    # 行数异常时给出提示
    if len(bert) != len(recs) or len(att) != len(att_lstm_recs) or len(lstm) != len(att_lstm_recs):
        print(f"  [警告] {group_dir}: 行数不匹配 -> FASTA={len(recs)}, 标准AA={len(att_lstm_recs)}, "
              f"Att={len(att)}, LSTM={len(lstm)}, BERT={len(bert)}; 已按位置对齐到 {len(align_recs)} 条")

    rows = []
    n_amp = 0
    n_amp_flex = 0
    for i, (name, seq) in enumerate(align_recs):
        a = att_al[i] if i < len(att_al) else 0.0
        l = lstm_al[i] if i < len(lstm_al) else 0.0
        b = bert_al[i] if i < len(bert_al) else 0.0
        votes = int(a > threshold) + int(l > threshold) + int(b > threshold)
        is_amp = 1 if votes == 3 else 0
        is_amp_flex = 1 if votes >= 2 else 0
        rows.append({
            "name": name, "seq": seq, "len": len(seq),
            "att_prob": round(a, 6), "lstm_prob": round(l, 6), "bert_prob": round(b, 6),
            "n_votes": votes, "is_AMP": is_amp, "AMP_pred": is_amp,
            "is_AMP_flex": is_amp_flex,
        })
        n_amp += is_amp
        n_amp_flex += is_amp_flex

    # 写明细表
    agg_path = os.path.join(group_dir, "aggregated_results.tsv")
    with open(agg_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=F_STD_COLS, delimiter="\t")
        w.writeheader()
        for r in rows:
            w.writerow(r)

    # 汇总
    group_name = os.path.basename(group_dir.rstrip("/"))
    summary = {
        "group": group_name,
        "n_seq": len(rows),
        "n_AMP3": n_amp,
        "AMP3_pct": (100.0 * n_amp / len(rows)) if rows else 0.0,
        "n_AMP_flex2": n_amp_flex,
        "AMP_flex2_pct": (100.0 * n_amp_flex / len(rows)) if rows else 0.0,
    }

    # 追加到全量表
    for r in rows:
        out_row = dict(r)
        out_row["group"] = group_name
        all_rows.append(out_row)

    print(f"   {group_name:28s} n={len(rows):6d}  3票AMP={n_amp:6d} ({summary['AMP3_pct']:.1f}%)  "
          f">=2票={n_amp_flex:6d} ({summary['AMP_flex2_pct']:.1f}%)")
    return rows, summary


def main():
    ap = argparse.ArgumentParser(description="汇总三个模型的 AMP 预测结果 (分组视角)")
    ap.add_argument("results_root", help="run_pipeline_all_groups.sh 的输出目录, 如 amp_results")
    ap.add_argument("--threshold", type=float, default=0.5, help="单模型判定为 AMP 的概率阈值, 默认0.5")
    ap.add_argument("--out", default=None, help="汇总表输出路径, 默认放在 results_root 下")
    args = ap.parse_args()

    root = args.results_root
    if not os.path.isdir(root):
        sys.exit(f"错误: 找不到结果目录 {root}")

    print("=" * 78)
    print(" 三模型 AMP 结果汇总")
    print("=" * 78)
    print(f"结果目录   : {root}")
    print(f"单模型阈值 : {args.threshold}")

    # 找到所有含 input.fa 的分组目录 (兼容单目录 / 一级子目录 / 二级队列子目录)
    candidates = [root] + sorted(glob.glob(os.path.join(root, "*"))) + sorted(glob.glob(os.path.join(root, "*", "*")))
    group_dirs = []
    for d in candidates:
        if os.path.isdir(d) and os.path.isfile(os.path.join(d, "input.fa")):
            if d not in group_dirs:
                group_dirs.append(d)

    print("\n[单组明细汇总]")
    summaries = []
    all_rows = []   # 每条肽段一行 (带 group 列)
    for gd in group_dirs:
        _, summ = process_group(gd, args.threshold, all_rows)
        if summ:
            summaries.append(summ)

    if not summaries:
        print("未找到任何分组结果。请先运行 run_pipeline_all_groups.sh。")
        return

    print("\n[写分组汇总]")
    summary_path = os.path.join(root, "amp_summary.tsv")
    with open(summary_path, "w", newline="") as fh:
        cols = ["group", "n_seq", "n_AMP3", "AMP3_pct", "n_AMP_flex2", "AMP_flex2_pct"]
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t")
        w.writeheader()
        for s in summaries:
            w.writerow(s)

    print("  分组汇总表 -> " + summary_path)

    # 全量肽段表
    if all_rows:
        all_path = os.path.join(root, "amp_all_peptides.tsv")
        cols = ["group", "name", "seq", "len", "att_prob", "lstm_prob", "bert_prob",
                "n_votes", "is_AMP", "is_AMP_flex"]
        with open(all_path, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t")
            w.writeheader()
            for r in all_rows:
                w.writerow({k: r.get(k, "") for k in cols})
        print("  全量肽段表  -> " + all_path)

    total_seq = sum(s["n_seq"] for s in summaries)
    total_amp3 = sum(s["n_AMP3"] for s in summaries)
    total_flex = sum(s["n_AMP_flex2"] for s in summaries)
    print("\n[汇总]")
    print(f"  分组数    : {len(summaries)}")
    print(f"  肽段合计  : {total_seq:,}")
    print(f"  3票AMP    : {total_amp3:,}  ({100.0*total_amp3/total_seq if total_seq else 0:.1f}%)")
    print(f"  >=2票AMP  : {total_flex:,}  ({100.0*total_flex/total_seq if total_seq else 0:.1f}%)")
    print("\n完成!")


if __name__ == "__main__":
    main()
