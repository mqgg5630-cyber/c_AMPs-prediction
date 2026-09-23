#!/usr/bin/env bash
# doctor.sh - Linux twin of doctor.ps1: env / branch / remote / ahead-behind / dirty / watcher / auth.
# Usage: bash doctor.sh [--fix]
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
FIX=0; [ "${1:-}" = "--fix" ] && FIX=1
echo "== git-sync doctor (linux)  skill v$(cat skills/git-sync/VERSION 2>/dev/null)"
echo "   repo    : $REPO"; echo "   config  : $CFG"; echo "   git     : $(git --version | cut -d' ' -f3)   python: $("$PY" -V 2>&1)"
cur="$(git rev-parse --abbrev-ref HEAD)"
if [ "$cur" = "$BRANCH" ]; then echo "OK: branch $cur"; else echo "WARN: HEAD is $cur, config says $BRANCH"; [ $FIX = 1 ] && guard_branch && echo "   fixed: switched to $BRANCH"; fi
git fetch -q "$REMOTE" 2>/dev/null && echo "OK: fetch $REMOTE" || echo "FAIL: fetch $REMOTE (network/proxy?)"
ab="$(git rev-list --left-right --count "HEAD...$REMOTE/$BRANCH" 2>/dev/null || echo "? ?")"
echo "   ahead/behind : ${ab/ / / }"
[ $FIX = 1 ] && [ "${ab#* }" != "0" ] && git pull -q --ff-only "$REMOTE" "$BRANCH" && echo "   fixed: pulled"
n="$(git status --porcelain | wc -l)"; [ "$n" = 0 ] && echo "OK: worktree clean" || echo "WARN: $n uncommitted path(s)  (bash push.sh \"msg\")"
s="$(git stash list | wc -l)"; [ "$s" = 0 ] || echo "WARN: $s stash entries"
big="$(git ls-files -z | xargs -0 -r du -m 2>/dev/null | awk '$1>50{print "   "$2" ("$1" MB)"}')"; [ -z "$big" ] || { echo "WARN: tracked files > 50 MB:"; echo "$big"; }
# watcher
if crontab -l 2>/dev/null | grep -q "git-sync-watch:$REPO"; then echo "OK: watcher registered (cron)"; else echo "WARN: watcher not registered  (bash watch.sh --register)"; fi
hb="$STATE_DIR/heartbeat"; if [ -f "$hb" ]; then age=$(( ($(date +%s) - $(stat -c %Y "$hb")) / 60 )); echo "   heartbeat : ${age} min ago $( [ $age -le 6 ] && echo '(fresh)' || echo '(STALE)')"; else echo "   heartbeat : never"; fi
[ -f "$STATE_DIR/state.json" ] && echo "   last      : $(cat "$STATE_DIR/state.json")"
# auth
if git push --dry-run -q "$REMOTE" "$BRANCH" 2>/dev/null; then echo "OK: silent push works"; else echo "FAIL: silent push  (bash auth.sh --gh-login)"; fi
