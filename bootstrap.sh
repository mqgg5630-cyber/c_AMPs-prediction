#!/usr/bin/env bash
# bootstrap.sh - Linux twin of bootstrap.ps1: first-time setup in a fresh clone.
#   bash bootstrap.sh          identity check + fetch + switch branch + first pull
#   bash bootstrap.sh --auto   ... + auth check + register the cron watcher + hardware report
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
AUTO=0; [ "${1:-}" = "--auto" ] && AUTO=1
grep -qi microsoft /proc/version 2>/dev/null && bash "$SCRIPTS/proxy.sh" --install
git config user.name  >/dev/null || git config user.name  "$(whoami)@$(hostname)"
git config user.email >/dev/null || git config user.email "$(whoami)@$(hostname).local"
git config pull.ff only; git config core.autocrlf input
guard_branch; git fetch -q "$REMOTE" && git pull -q --ff-only "$REMOTE" "$BRANCH" && echo "OK: on $BRANCH ($(git rev-parse --short HEAD))"
chmod +x *.sh skills/git-sync/scripts/*.sh code/*.sh 2>/dev/null
[ -f code/local_check.sh ] || { echo "[WARN] code/local_check.sh missing"; }
if [ $AUTO = 1 ]; then
  bash "$SCRIPTS/auth.sh" || echo "!! fix auth first (bash auth.sh --gh-login), then: bash watch.sh --register"
  bash "$SCRIPTS/watch.sh" --register 2
  bash "$SCRIPTS/hardware.sh" --deep || true
fi
bash "$SCRIPTS/doctor.sh"
