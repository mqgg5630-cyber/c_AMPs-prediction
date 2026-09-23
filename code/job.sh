#!/usr/bin/env bash
# job: confirm the deliverables landed on this machine and print their absolute paths
cd "$(dirname "$0")/.."
for f in deliverable/AMP三模型预测_结果与方法.md deliverable/AMP三模型预测_结果与方法.docx; do
  [ -s "$f" ] && echo "OK  $(readlink -f "$f")  ($(du -h "$f" | cut -f1))" || { echo "MISSING $f"; exit 1; }
done
