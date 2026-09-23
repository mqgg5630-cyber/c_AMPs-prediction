#!/usr/bin/env bash
# auth.sh - Linux twin of auth.ps1: make pushes silent (no prompt) and PROVE it.
#   bash auth.sh            show which credential would be used + dry-run push
#   bash auth.sh --gh-login one-time interactive `gh auth login` then gh as git credential helper
#   bash auth.sh --account <login>   pin THIS clone to a gh account (multi-account machines)
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
SCRIPTS="$REPO/skills/git-sync/scripts"
case "${1:-}" in
  --gh-login)
    command -v gh >/dev/null || { echo "[ERROR] gh (GitHub CLI) not installed: sudo apt install gh  (or conda install gh -c conda-forge)"; exit 1; }
    gh auth login -h github.com -p https -w && gh auth setup-git && echo "OK: gh is now the git credential helper";;
  --account)
    login="${2:?--account <gh login>}"
    command -v gh >/dev/null || { echo "[ERROR] gh not installed"; exit 1; }
    git config --local --unset-all credential.helper 2>/dev/null || true
    git config --local credential.helper '' ; git config --local --add credential.helper "!f() { gh auth git-credential \"\$@\"; }; f"
    git config --local credential.https://github.com.username "$login"
    echo "OK: this clone pinned to gh account '$login' (other clones unaffected)";;
  --unpin) git config --local --unset-all credential.helper; git config --local --unset credential.https://github.com.username 2>/dev/null; echo "OK: unpinned";;
esac
echo "== remote : $(git remote get-url "$REMOTE")"
echo "== helpers: $(git config --get-all credential.helper | tr '\n' ' ')"
command -v gh >/dev/null && echo "== gh     : $(gh auth status 2>&1 | grep -E 'Logged in|account' | head -3 | tr -s ' ' | tr '\n' ';')"
if git ls-remote -q --exit-code "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1 && git push --dry-run -q "$REMOTE" "$BRANCH" 2>/dev/null; then
  echo "OK: silent push PROVEN (ls-remote + push --dry-run, prompts disabled)"; exit 0
fi
echo "[FAIL] cannot push silently. Fix with ONE of:"
echo "   bash auth.sh --gh-login          # recommended (GitHub CLI, one browser login)"
echo "   git config --global credential.helper store && git push   # classic token cache (plain-text file)"
exit 4
