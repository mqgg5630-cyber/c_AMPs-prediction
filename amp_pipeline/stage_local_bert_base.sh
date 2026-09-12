#!/bin/bash
# 把 pytorch_pretrained_bert 缓存里的 bert-base-uncased 三件套整理到 Models/bert-base-uncased/
# (vocab.txt / config.json / pytorch_model.bin), 之后加载 bert.bin 不再联网, 秒开。
# 用法: bash amp_pipeline/stage_local_bert_base.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DST="$PROJECT_DIR/Models/bert-base-uncased"
mkdir -p "$DST"
need=0
for f in vocab.txt config.json pytorch_model.bin; do [ -s "$DST/$f" ] || need=1; done
if [ "$need" = 0 ]; then echo "  [bert-base-uncased] 本地已齐全: $DST"; exit 0; fi

CACHES=("$HOME/.pytorch_pretrained_bert" "$HOME/.cache/torch/pytorch_pretrained_bert")
find_by_meta() {  # find_by_meta <url 关键字>  -> 打印对应的缓存文件路径
    for c in "${CACHES[@]}"; do
        [ -d "$c" ] || continue
        for j in "$c"/*.json; do
            [ -f "$j" ] || continue
            if grep -q "$1" "$j" 2>/dev/null; then echo "${j%.json}"; return 0; fi
        done
    done
    return 1
}
v=$(find_by_meta "bert-base-uncased-vocab.txt" || true)
c=$(find_by_meta "bert-base-uncased-config.json" || true)
m=$(find_by_meta "bert-base-uncased-pytorch_model.bin" || true)
# 兜底: 按内容/大小识别
[ -z "$v" ] && v=$(grep -l "^\[CLS\]$" "${CACHES[@]/%//*}" 2>/dev/null | head -1 || true)
[ -z "$c" ] && c=$(grep -l '"vocab_size": 30522' "${CACHES[@]/%//*}" 2>/dev/null | grep -v '\.json$' | head -1 || true)
[ -z "$m" ] && m=$(find "${CACHES[@]}" -maxdepth 1 -type f -size +400M 2>/dev/null | grep -v '\.json$' | head -1 || true)

ok=1
[ -n "$v" ] && [ -s "$v" ] && cp "$v" "$DST/vocab.txt" && echo "  vocab.txt        <- $v" || { echo "  [缺] vocab.txt"; ok=0; }
[ -n "$c" ] && [ -s "$c" ] && cp "$c" "$DST/config.json" && echo "  config.json      <- $c" || { echo "  [缺] config.json"; ok=0; }
[ -n "$m" ] && [ -s "$m" ] && cp "$m" "$DST/pytorch_model.bin" && echo "  pytorch_model.bin <- $m" || { echo "  [缺] pytorch_model.bin"; ok=0; }
if [ "$ok" = 0 ]; then
    echo "  [提示] 缓存不全, 已删除半成品目录以免干扰加载 (联网跑一次 prediction_bert.py 后再执行本脚本)"
    rm -rf "$DST"; exit 1
fi
echo "  [bert-base-uncased] 已就绪: $DST  (以后加载 bert.bin 不再联网)"
