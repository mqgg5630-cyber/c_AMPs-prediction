#!/usr/bin/env bash
# proxy.sh - WSL2 proxy one-shot fixer (host IP changes on every WSL restart).
#   bash proxy.sh                 set git + env proxy to the Windows host, port $PORT (default 10808, socks5)
#   bash proxy.sh --install       also patch ~/.bashrc so EVERY new shell does this automatically
#   bash proxy.sh --off           unset git proxy for this run
#   PORT=7890 SCHEME=http bash proxy.sh --install    (Clash-style http proxy)
# After --install:  proxy_on / proxy_off / proxy_test are available in new shells.
set -u
PORT="${PORT:-10808}"; SCHEME="${SCHEME:-socks5}"
HOST_IP="$(ip route 2>/dev/null | awk '/default/{print $3; exit}')"
[ -z "$HOST_IP" ] && HOST_IP="$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf)"
URL="$SCHEME://$HOST_IP:$PORT"
case "${1:-}" in
  --off) git config --global --unset http.proxy; git config --global --unset https.proxy; echo "[proxy off]"; exit 0;;
esac
apply() {
  git config --global http.proxy  "$URL"; git config --global https.proxy "$URL"
  export http_proxy="$URL" https_proxy="$URL" HTTP_PROXY="$URL" HTTPS_PROXY="$URL"
  export no_proxy="localhost,127.0.0.1,::1,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8" NO_PROXY="$no_proxy"
  unset all_proxy ALL_PROXY
}
apply
echo "[proxy on] $URL"
if curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.github.com >/dev/null 2>&1; then echo "OK: github reachable via $URL"; else echo "[WARN] github NOT reachable via $URL - is the Windows proxy app running with 'allow LAN' on port $PORT?"; fi
if [ "${1:-}" = "--install" ]; then
  RC="$HOME/.bashrc"; cp "$RC" "$RC.bak.$(date +%s)"
  # remove the old block (any previous WSL proxy config) and re-add ours
  sed -i '/# >>> WSL proxy config >>>/,/# <<< WSL proxy config <<</d' "$RC"
  cat >> "$RC" <<EOB
# >>> WSL proxy config >>>
export PROXY_PORT=$PORT
export PROXY_SCHEME=$SCHEME
proxy_on () {
  local ip; ip=\$(ip route 2>/dev/null | awk '/default/{print \$3; exit}')
  local url="\$PROXY_SCHEME://\$ip:\$PROXY_PORT"
  export http_proxy="\$url" https_proxy="\$url" HTTP_PROXY="\$url" HTTPS_PROXY="\$url"
  export no_proxy="localhost,127.0.0.1,::1,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8" NO_PROXY="\$no_proxy"
  unset all_proxy ALL_PROXY
  git config --global http.proxy "\$url" 2>/dev/null; git config --global https.proxy "\$url" 2>/dev/null
  [ -n "\${1:-}" ] || echo "[proxy on] \$url"
}
proxy_off () {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
  git config --global --unset http.proxy 2>/dev/null; git config --global --unset https.proxy 2>/dev/null
  echo "[proxy off]"
}
proxy_test () { curl -s -m 8 -o /dev/null -w 'github: HTTP %{http_code} via %{proxy_used}\n' https://api.github.com || echo "github: unreachable"; }
proxy_on quiet
# <<< WSL proxy config <<<
EOB
  echo "OK: ~/.bashrc patched (old block removed, backup kept). New shells auto-run proxy_on; commands: proxy_on / proxy_off / proxy_test"
fi
