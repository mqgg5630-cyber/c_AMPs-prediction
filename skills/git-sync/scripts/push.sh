#!/usr/bin/env bash
# push.sh - Linux twin of push.ps1: pull --ff-only -> add -A -> commit -> push.
# Refuses main/master. Silent by default (no credential prompt; exit 4 if none).
# Usage: bash push.sh "message" [--gate] [--exclude-auto]
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
MSG=""; GATE=0; AUTO=0
for a in "$@"; do case "$a" in --gate) GATE=1;; --auto) AUTO=1;; *) MSG="$a";; esac; done
[ -z "$MSG" ] && MSG="local: update $(date '+%F %T')"
guard_branch
git fetch -q "$REMOTE" || { echo "[ERROR] fetch failed"; exit 1; }
git pull -q --ff-only "$REMOTE" "$BRANCH" 2>/dev/null || { echo "[ERROR] branch diverged - run: bash sync.sh"; exit 1; }
if [ "$GATE" = 1 ]; then g="$(cfg gate)"; [ -n "$g" ] && { echo "== gate: $g"; bash -c "$g" || { echo "[GATE FAILED] not committing"; exit 2; }; }; fi
git add -A
if [ "$AUTO" = 1 ]; then
  # never auto-push secrets or the handshake
  for pat in $(cfg auto_push_exclude '[]' | "$PY" -c 'import json,sys;print(" ".join(json.load(sys.stdin)))'); do git reset -q -- "$pat" 2>/dev/null || true; git ls-files -z -- "$pat" 2>/dev/null | xargs -0 -r git reset -q -- 2>/dev/null || true; done
  git reset -q -- "$HANDSHAKE" 2>/dev/null || true
fi
if git diff --cached --quiet; then echo "== nothing to commit"; exit 0; fi
git commit -q -m "$MSG" || exit 1
out="$(git push "$REMOTE" "$BRANCH" 2>&1)"; rc=$?
if [ $rc -ne 0 ]; then
  echo "$out" | tail -3
  if echo "$out" | grep -qiE "authentication|could not read Username|Permission denied|403"; then echo "[AUTH] no silent credential - run: bash auth.sh"; exit 4; fi
  exit 1
fi
echo "OK: pushed $(git rev-parse --short HEAD) -> $REMOTE/$BRANCH"
