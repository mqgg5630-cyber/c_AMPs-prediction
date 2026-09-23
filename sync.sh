#!/usr/bin/env bash
# sync.sh - Linux twin of sync.ps1: fetch + switch to the configured branch + pull --ff-only
# (local changes are auto-stashed and re-applied).  Usage: bash sync.sh
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
guard_branch
git fetch -q "$REMOTE" || { echo "[ERROR] fetch failed (network/auth)"; exit 1; }
stashed=0
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git stash push -q -m "git-sync auto-stash $(date '+%F %T')" && stashed=1 && echo "== local changes stashed"
fi
if git pull -q --ff-only "$REMOTE" "$BRANCH" 2>/dev/null; then echo "OK: $BRANCH up to date ($(git rev-parse --short HEAD))"; rc=0
elif git pull -q --rebase "$REMOTE" "$BRANCH" >/dev/null 2>&1; then echo "OK: $BRANCH rebased onto $REMOTE ($(git rev-parse --short HEAD))"; rc=0
else git rebase --abort >/dev/null 2>&1 || true; echo "[ERROR] pull failed (ff-only + rebase) - run: bash doctor.sh --fix"; rc=1; fi
if [ "$stashed" = 1 ]; then git stash pop -q && echo "== stash re-applied" || echo "[WARN] stash pop had conflicts - see: git stash list"; fi
exit $rc
