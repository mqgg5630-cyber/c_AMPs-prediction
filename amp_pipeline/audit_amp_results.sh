#!/bin/bash
# audit_amp_results.sh —— 只读盘点 amp_results（98G）：按文件类型汇总 + 抽查
# aggregated_results.tsv 是否完整吸收了 *_proba.tsv 的信息（决定 proba 能否当中间数据删）。
# 用法: bash amp_pipeline/audit_amp_results.sh [amp_results 路径]
# 只读，不删任何东西。
set -u
export LC_ALL=C
R="${1:-/home/w24e/c_AMPs-prediction/amp_results}"
echo "== 结构 =="; ls "$R"
echo "== 按文件名汇总（大小 / 个数） =="
find "$R" -type f -printf "%s %f\n" | awk '{s[$2]+=$1; c[$2]++} END{for(f in s) printf "%-30s %5d 个 %10.2f GB\n", f, c[f], s[f]/1024/1024/1024}' | sort -k3 -rh
echo "== 抽查一组 =="
g="$(find "$R" -name aggregated_results.tsv | head -1)"; d="$(dirname "$g")"; echo "目录: $d"
for f in "$d"/*; do [ -f "$f" ] && printf "%-40s %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"; done
echo "--- 各文件行数 ---"; wc -l "$d"/* 2>/dev/null | grep -v total
echo "--- aggregated 表头 ---"; head -1 "$g"
for p in attention_proba lstm_proba bert_proba input_formatted_300 final_prediction; do
  f="$(ls "$d"/$p* 2>/dev/null | head -1)"
  [ -n "${f:-}" ] && { echo "--- $(basename "$f") 前2行 ---"; head -2 "$f" | cut -c1-200; }
done
echo "--- 抽查 proba 值是否 = aggregated 对应列（第 1000/100000 行） ---"
for n in 1000 100000; do
  a="$(sed -n "${n}p" "$g" | cut -f1,4,5,6)"
  echo "aggregated 行$n: $a" | cut -c1-160
done
