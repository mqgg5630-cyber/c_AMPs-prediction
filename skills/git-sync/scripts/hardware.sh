#!/usr/bin/env bash
# hardware.sh - Linux twin of hardware.ps1: write results/hardware/latest.{md,json} + history and push.
# Usage: bash hardware.sh [--deep]   (--deep probes torch/CUDA in every conda env; slow)
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
DEEP=0; [ "${1:-}" = "--deep" ] && DEEP=1
HW="$(cfg hardware_dir results/hardware)"; mkdir -p "$HW/history"
stamp="$(date '+%Y%m%d-%H%M%S')"; host="$(hostname)"
os="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-$(uname -sr)}")"; grep -qi microsoft /proc/version 2>/dev/null && os="$os (WSL2)"
cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')  x$(nproc)"
mem="$(free -g | awk '/Mem:/{print $2" GB total, "$7" GB available"}')"
disk="$(df -h "$REPO" | awk 'NR==2{print $4" free of "$2" ("$6")"}')"
gpu="none"; drv=""; if command -v nvidia-smi >/dev/null; then gpu="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | paste -sd';')"; drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"; fi
conda_base="$(conda info --base 2>/dev/null | grep -m1 '^/' || true)"; envs=""
[ -n "$conda_base" ] && envs="$(ls -1 "$conda_base/envs" 2>/dev/null | paste -sd' ')"
deep_md=""
if [ "$DEEP" = 1 ] && [ -n "$conda_base" ]; then
  for e in "$conda_base/envs"/*/; do n="$(basename "$e")"; p="$e/bin/python"; [ -x "$p" ] || continue
    r="$("$p" -c "import torch;print('torch',torch.__version__,'cuda',torch.cuda.is_available())" 2>/dev/null || echo "no torch")"
    t="$("$p" -c "import tensorflow as tf;print('tf',tf.__version__)" 2>/dev/null || true)"
    deep_md="$deep_md
| $n | $("$p" -V 2>&1 | cut -d' ' -f2) | $r | ${t:-} |"; done
fi
{
echo "# Hardware report - $host ($stamp)"; echo
echo "| item | value |"; echo "|---|---|"
echo "| OS | $os |"; echo "| CPU | $cpu |"; echo "| Memory | $mem |"; echo "| Disk | $disk |"
echo "| GPU | $gpu |"; echo "| Driver | ${drv:-n/a} |"; echo "| conda | ${conda_base:-none} |"; echo "| envs | ${envs:-none} |"
echo "| git | $(git --version | cut -d' ' -f3) |"; echo "| repo | $REPO |"
[ -n "$deep_md" ] && { echo; echo "## conda envs (--deep)"; echo; echo "| env | python | torch | tf |"; echo "|---|---|---|---|$deep_md"; }
} > "$HW/latest.md"
cp "$HW/latest.md" "$HW/history/$stamp.md"; ls -1t "$HW/history" | tail -n +31 | xargs -r -I{} rm -f "$HW/history/{}"
"$PY" - "$HW/latest.json" "$host" "$stamp" "$os" "$cpu" "$mem" "$disk" "$gpu" "$drv" "$conda_base" "$envs" <<'PY'
import json, sys
k = ['host','stamp','os','cpu','memory','disk','gpu','driver','conda_base','conda_envs']
d = dict(zip(k, sys.argv[2:])); d['platform'] = 'linux'; d['conda_envs'] = d['conda_envs'].split()
json.dump(d, open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PY
cat "$HW/latest.md"
bash "$SCRIPTS/push.sh" "hardware: report from $host ($stamp)"
