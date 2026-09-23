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
  # auto account pin (v2.10.0): whoever owns the repo, use their stored token for this clone
  owner="$(git remote get-url "$REMOTE" | sed -E 's#.*github.com[:/]##; s#/.*##')"
  ACC="$HOME/.config/git-sync/accounts"
  if [ -z "$(git config --local git-sync.account 2>/dev/null)" ]; then
    if [ -f "$ACC/$owner" ]; then bash "$SCRIPTS/auth.sh" --account "$owner"
    else for f in "$ACC"/*; do [ -f "$f" ] || continue; l="$(basename "$f")"
           if bash "$SCRIPTS/auth.sh" --accounts 2>/dev/null | grep -q "^   $l : push=yes"; then bash "$SCRIPTS/auth.sh" --account "$l"; break; fi; done; fi
  fi
  bash "$SCRIPTS/auth.sh" || { echo "!! no account can push $owner's repo. Store the owner's token once:"; echo "     bash auth.sh --add $owner   (then re-run: bash bootstrap.sh --auto)"; }
  bash "$SCRIPTS/watch.sh" --register 2
  bash "$SCRIPTS/hardware.sh" --deep || true
fi
bash "$SCRIPTS/doctor.sh"
