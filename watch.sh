#!/usr/bin/env bash
# watch.sh - Linux twin of watch.ps1: the LOCAL side of the arena <-> local loop.
#   bash watch.sh --register [N]   cron every N minutes (default 2): poll handshake, run check, push verdict
#   bash watch.sh --unregister     remove the cron entry
#   bash watch.sh --status         cron / heartbeat / last round
#   bash watch.sh --test           run ONE poll right now (foreground, verbose)
#   bash watch.sh --once           (what cron calls) one poll, quiet, locked
# Protocol identical to watch.ps1: results/status/handshake.json
#   arena_state=awaiting_check & local_state=pending  -> sync, run check_cmd_linux,
#   write results/status/check_r<N>_<stamp>.txt, set local_state=passed|failed, push.
# hands_free: every poll also auto_pull + auto_push (excluding secrets & handshake).
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
SELF="$REPO/watch.sh"; [ -f "$SELF" ] || SELF="$REPO/skills/git-sync/scripts/watch.sh"
TAG="git-sync-watch:$REPO"
set_state() { "$PY" - "$STATE_DIR/state.json" "$@" <<'PY'
import json, sys, os, datetime
p = sys.argv[1]; d = {}
if os.path.isfile(p):
    try: d = json.load(open(p))
    except Exception: d = {}
for kv in sys.argv[2:]:
    k, _, v = kv.partition('='); d[k] = v
d['updated'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
json.dump(d, open(p, 'w'), ensure_ascii=False)
PY
}
auto_pull() { [ "$AUTO_PULL" = true ] || return 0; bash "$SCRIPTS/sync.sh" >>"$LOG" 2>&1 && echo ok || echo fail; }
auto_push() { [ "$AUTO_PUSH" = true ] || return 0; bash "$SCRIPTS/push.sh" --auto "$AUTO_PREFIX $(hostname) $(date '+%F %T')" >>"$LOG" 2>&1 && echo ok || echo fail; }

poll() {
  date +%s > "$STATE_DIR/heartbeat"
  set_state last_run="$(date '+%F %T')" host="$(hostname)" last_action=poll
  guard_branch
  git fetch -q "$REMOTE" || { say "fetch failed"; set_state last_action=error last_note="fetch failed"; return 1; }
  hs="$(git show "$REMOTE/$BRANCH:$HANDSHAKE" 2>/dev/null || true)"
  if [ -z "$hs" ]; then
    if [ "$HANDS_FREE" = true ]; then say "hands-free pull=$(auto_pull) push=$(auto_push) (no handshake yet)"; else say "idle - no handshake yet"; fi
    set_state last_action=idle; return 0
  fi
  a="$(json_get "$hs" arena_state)"; l="$(json_get "$hs" local_state)"; round="$(json_get "$hs" round)"
  if [ "$a" != awaiting_check ] || [ "$l" != pending ]; then
    if [ "$HANDS_FREE" = true ]; then say "idle (arena=$a local=$l) hands-free pull=$(auto_pull) push=$(auto_push)"; else say "idle (arena=$a local=$l)"; fi
    set_state last_action=idle last_note="arena=$a local=$l"; return 0
  fi
  say "round $round requested: $(json_get "$hs" note)"
  bash "$SCRIPTS/sync.sh" >>"$LOG" 2>&1 || { say "round $round: sync FAILED"; set_state last_action=error last_note="sync failed"; return 1; }
  stamp="$(date '+%Y%m%d-%H%M%S')"; logrel="$(dirname "$HANDSHAKE")/check_r${round}_${stamp}.txt"; mkdir -p "$(dirname "$logrel")"
  say "round $round: running $CHECK_CMD (timeout ${TIMEOUT_MIN}m)"
  t0=$(date +%s); out="$(mktemp)"
  timeout -k 30 "$((TIMEOUT_MIN*60))" bash -c "$CHECK_CMD" >"$out" 2>&1; code=$?
  secs=$(( $(date +%s) - t0 )); verdict=failed; [ $code -eq 0 ] && verdict=passed
  { echo "check round $round on $(hostname) - $verdict (exit $code)"; echo "cmd: $CHECK_CMD"; echo "elapsed: ${secs}s"; [ $code -eq 124 ] && echo "TIMEOUT: killed after $TIMEOUT_MIN min"; echo; cat "$out"; } > "$logrel"; rm -f "$out"
  "$PY" - "$HANDSHAKE" "$verdict" <<'PY'
import json, sys, datetime, socket
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding='utf-8-sig'))
d['local_state'] = v; d['local_updated'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'); d['host'] = socket.gethostname()
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2); open(p, 'a').write('\n')
PY
  git add -A "$HANDSHAKE" "$logrel"
  ok=0; for try in 1 2 3; do
    git commit -q -m "check: round $round $verdict" 2>/dev/null || true
    if git push -q "$REMOTE" "$BRANCH" 2>>"$LOG"; then ok=1; break; fi
    git pull -q --rebase "$REMOTE" "$BRANCH" 2>>"$LOG" || true; sleep 3
  done
  if [ $ok = 1 ]; then say "round $round checked ($verdict) - verdict pushed"; set_state last_action=push last_push=ok last_round="$round" last_verdict="$verdict"
  else say "round $round checked ($verdict) but push FAILED - run: bash auth.sh"; set_state last_action=push last_push=failed last_round="$round"; return 1; fi
}

case "${1:-}" in
  --register)
    N="${2:-2}"; command -v crontab >/dev/null || { echo "[ERROR] crontab not found: sudo apt install cron && sudo service cron start"; exit 1; }
    pgrep -x cron >/dev/null || pgrep -x crond >/dev/null || echo "[WARN] cron daemon not running - WSL: sudo service cron start  (add to /etc/wsl.conf [boot] command=service cron start)"
    ( crontab -l 2>/dev/null | grep -v "$TAG"; echo "*/$N * * * * cd '$REPO' && PATH=\$PATH:/usr/local/bin:/usr/lib/wsl/lib:$HOME/miniconda3/bin:$HOME/miniconda3/condabin bash '$SELF' --once # $TAG" ) | crontab -
    echo "OK: watcher registered (cron every $N min)  log: $LOG"; echo "== smoke test (one poll now):"; bash "$SELF" --test;;
  --unregister) ( crontab -l 2>/dev/null | grep -v "$TAG" ) | crontab -; echo "OK: watcher unregistered";;
  --status)
    crontab -l 2>/dev/null | grep -q "$TAG" && echo "cron      : registered ($(crontab -l | grep "$TAG" | cut -d' ' -f1-5))" || echo "cron      : NOT registered"
    pgrep -x cron >/dev/null || pgrep -x crond >/dev/null && echo "cron daemon: running" || echo "cron daemon: NOT running (sudo service cron start)"
    hb="$STATE_DIR/heartbeat"; [ -f "$hb" ] && echo "heartbeat : $(( ($(date +%s) - $(cat "$hb")) / 60 )) min ago" || echo "heartbeat : never"
    [ -f "$STATE_DIR/state.json" ] && echo "state     : $(cat "$STATE_DIR/state.json")"
    echo "hands-free: $HANDS_FREE (pull=$AUTO_PULL push=$AUTO_PUSH)"; echo "log tail  : $LOG"; tail -5 "$LOG" 2>/dev/null | sed 's/^/   /';;
  --test) poll;;
  --once) exec 9>"$STATE_DIR/lock"; flock -n 9 || { log "lock held - skipping"; exit 0; }; poll >/dev/null 2>&1;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//';;
esac
