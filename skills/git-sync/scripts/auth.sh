#!/usr/bin/env bash
# auth.sh - Linux twin of auth.ps1: silent pushes + MULTI-ACCOUNT (v2.9.x parity).
#
#   bash auth.sh                         which credential this clone uses + PROVE silent push (dry-run)
#   bash auth.sh --add <login>           store a token for account <login>  (prompted, never echoed;
#                                        or  TOKEN=ghp_xxx bash auth.sh --add <login>)
#   bash auth.sh --accounts              list stored accounts + can each one push THIS repo? (live test)
#   bash auth.sh --account <login>       pin THIS clone to <login> (local git config only; other clones untouched)
#   bash auth.sh --unpin                 remove the pin (back to the machine default = credential.helper store)
#   bash auth.sh --remove <login>        delete a stored token
#   bash auth.sh --gh-login              alternative: GitHub CLI login (needs working proxy)
#
# Tokens live in ~/.config/git-sync/accounts/<login>  (chmod 600). Pinning writes a per-clone
# credential helper that reads that file - the machine-wide 'store' helper is bypassed for this clone.
# Rule (same as Windows): whoever owns the repo, use THEIR account for that clone.
set -u -o pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_d/gitsync-lib.sh" ]; then . "$_d/gitsync-lib.sh"; else . "$_d/skills/git-sync/scripts/gitsync-lib.sh"; fi
ACC_DIR="$HOME/.config/git-sync/accounts"; mkdir -p "$ACC_DIR"; chmod 700 "$ACC_DIR"
URL="$(git remote get-url "$REMOTE")"
OWNER_REPO="$(echo "$URL" | sed -E 's#.*github.com[:/]##; s#\.git$##')"

test_account() {  # test_account <login> -> prints push=yes/no
  local tok; tok="$(cat "$ACC_DIR/$1" 2>/dev/null)"; [ -z "$tok" ] && { echo "no-token"; return; }
  local perm; perm="$(curl -s -m 15 -H "Authorization: token $tok" "https://api.github.com/repos/$OWNER_REPO" | "$PY" -c 'import json,sys
try:
  d=json.load(sys.stdin); p=d.get("permissions",{}); print("yes" if p.get("push") else ("no(read-only)" if "id" in d else "no("+str(d.get("message",""))+")"))
except Exception: print("no(api error)")')"
  echo "$perm"
}
pin_helper() {  # per-clone helper reading the account file
  local login="$1"
  git config --local --unset-all credential.helper 2>/dev/null || true
  git config --local --add credential.helper ''          # empty entry = ignore global/system helpers
  git config --local --add credential.helper "!f() { [ \"\$1\" = get ] && { echo username=$login; echo password=\$(cat '$ACC_DIR/$login'); }; }; f"
  git config --local credential.useHttpPath false
  git config --local git-sync.account "$login"
}

case "${1:-}" in
  --add)
    login="${2:?--add <login>}"
    if [ -n "${TOKEN:-}" ]; then tok="$TOKEN"; else read -r -s -p "Paste a GitHub token (PAT, repo scope) for $login: " tok; echo; fi
    [ -n "$tok" ] || { echo "[ERROR] empty token"; exit 1; }
    me="$(curl -s -m 15 -H "Authorization: token $tok" https://api.github.com/user | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get("login",""))' 2>/dev/null)"
    [ "$me" = "$login" ] || { echo "[ERROR] token belongs to '${me:-?}', not '$login' (or network/proxy problem)"; exit 1; }
    printf '%s' "$tok" > "$ACC_DIR/$login"; chmod 600 "$ACC_DIR/$login"; echo "OK: token stored for $login  ($ACC_DIR/$login)"
    echo "   push access to $OWNER_REPO: $(test_account "$login")"; exit 0;;
  --remove) rm -f "$ACC_DIR/${2:?--remove <login>}"; echo "OK: removed"; exit 0;;
  --accounts)
    echo "== repo: $OWNER_REPO"; echo "== pinned here: $(git config --local git-sync.account 2>/dev/null || echo '(none - machine default)')"
    for f in "$ACC_DIR"/*; do [ -f "$f" ] || { echo "   (no stored accounts - bash auth.sh --add <login>)"; break; }; l="$(basename "$f")"; echo "   $l : push=$(test_account "$l")"; done
    if [ -f "$HOME/.git-credentials" ]; then echo "== machine default (credential.helper store) users: $(sed -E 's#https?://([^:]+):.*#\1#' "$HOME/.git-credentials" | sort -u | paste -sd' ')"; fi
    exit 0;;
  --account)
    login="${2:?--account <login>}"; [ -f "$ACC_DIR/$login" ] || { echo "[ERROR] no token for $login - first: bash auth.sh --add $login"; exit 1; }
    pin_helper "$login"; echo "OK: this clone pinned to '$login' (other clones unaffected)";;
  --unpin) git config --local --unset-all credential.helper 2>/dev/null; git config --local --unset git-sync.account 2>/dev/null; echo "OK: unpinned (machine default)";;
  --gh-login)
    command -v gh >/dev/null || { echo "[ERROR] gh not installed: sudo apt install gh"; exit 1; }
    gh auth login -h github.com -p https -w && gh auth setup-git;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac

echo "== remote : $URL"
echo "== pinned : $(git config --local git-sync.account 2>/dev/null || echo '(none - machine default: '"$(git config --get-all credential.helper | paste -sd' ')"')')"
[ -n "$(git config --global http.proxy 2>/dev/null)" ] && echo "== proxy  : $(git config --global http.proxy)"
out="$(timeout 40 git push --dry-run "$REMOTE" "$BRANCH" 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then echo "OK: silent push PROVEN (push --dry-run, prompts disabled)"; exit 0; fi
echo "[FAIL] cannot push silently (exit $rc):"; echo "$out" | grep -v "^$" | tail -3 | sed 's/^/   /'
if echo "$out" | grep -q "denied to"; then
  who="$(echo "$out" | sed -n 's/.*denied to \([^.]*\).*/\1/p' | head -1)"
  echo "   -> account '$who' has NO push right on $OWNER_REPO. Either invite it as collaborator, or pin the owner's account:"
  echo "      bash auth.sh --add ${OWNER_REPO%%/*}    &&    bash auth.sh --account ${OWNER_REPO%%/*}"
elif [ $rc -eq 124 ] || echo "$out" | grep -qi "timed out\|proxyconnect\|Could not resolve\|Failed to connect"; then
  echo "   -> network/proxy problem. Run: bash proxy.sh   (then retry)"
else
  echo "   -> no usable credential. Run: bash auth.sh --add <login> && bash auth.sh --account <login>"
fi
exit 4
