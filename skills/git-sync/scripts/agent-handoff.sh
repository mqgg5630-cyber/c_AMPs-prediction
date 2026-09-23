#!/usr/bin/env bash
# agent-handoff.sh - print the EXACT block the user must paste on their machine.
#
# Why this exists (field report 2026-09-16, sessions 01a0a95e / 01a0a984):
#   the one and only bridge between the sandbox and the user's PC is that block.
#   Agents kept hand-writing it and getting it wrong:
#     * the wrong repo (deliverables pushed to `zhongqi`, watcher registered for
#       `git-pull-arena`) -> the request sat in `pending` for hours
#     * the wrong branch (a previous session's `arena/01a0a8xx-...`)
#     * a sandbox path (`/home/user/...`) inside a Windows PowerShell block
#   So: do not type it. Run this and paste its output verbatim.
#
# Usage:
#   bash skills/git-sync/scripts/agent-handoff.sh              # print the block
#   bash skills/git-sync/scripts/agent-handoff.sh --json       # machine readable
#   bash skills/git-sync/scripts/agent-handoff.sh --dir NAME   # suggested folder
#
# Exit: 0 printed, 1 unusable repo/config, 3 config branch != HEAD (fix first).

set -u -o pipefail
# v2.10.0: --linux [folder]  prints the Linux/WSL paste block instead of PowerShell
if [ "${1:-}" = "--linux" ]; then
  R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"; cd "$R"
  URL="$(git remote get-url origin)"; BR="$(python3 -c "import json;print(json.load(open('skills/git-sync/sync.config.json',encoding='utf-8-sig'))['branch'])")"
  HEADBR="$(git rev-parse --abbrev-ref HEAD)"; [ "$BR" = "$HEADBR" ] || { echo "[REFUSED] config branch $BR != HEAD $HEADBR" >&2; exit 3; }
  DEST="${2:-$(basename "$URL" .git)}"; OWNER="$(echo "$URL" | sed -E 's#.*github.com[:/]##; s#/.*##')"
  cat <<EOB
\`\`\`bash
# Linux / WSL - paste as one block. Existing folder is NOT overwritten (clone skips if it exists).
mkdir -p "\$(dirname "$DEST")"
[ -d "$DEST/.git" ] || git clone -b $BR $URL "$DEST"
cd "$DEST"
grep -qi microsoft /proc/version 2>/dev/null && bash proxy.sh --install && source ~/.bashrc   # WSL2 only
sudo service cron start 2>/dev/null
ls ~/.config/git-sync/accounts/$OWNER >/dev/null 2>&1 || bash auth.sh --add $OWNER    # once per machine: paste $OWNER's token
bash bootstrap.sh --auto      # identity + branch + auto account pin + cron watcher + hardware report
bash doctor.sh                # expect: OK branch / ahead 0 behind 0 / watcher registered / silent push works
\`\`\`
EOB
  exit 0
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

CFG="skills/git-sync/sync.config.json"
JSON=0
FOLDER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --dir)  FOLDER="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,19\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

HEAD_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -z "$HEAD_BRANCH" ] && { echo "[ERROR] not a git repository" >&2; exit 1; }

json_key() {  # $1 key  (tolerates the UTF-8 BOM PowerShell 5.1 writes)
  [ -f "$CFG" ] || return 0
  python3 - "$CFG" "$1" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
print(d.get(sys.argv[2], ''))
PY
}

BRANCH="$(json_key branch)"
REMOTE="$(json_key remote)"; [ -z "$REMOTE" ] && REMOTE="origin"

# sed fallback: python may be missing or be the Windows Store stub
if [ -z "$BRANCH" ]; then
  BRANCH="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" 2>/dev/null | head -1)"
  REMOTE="$(sed -n 's/.*"remote"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" 2>/dev/null | head -1)"
  [ -z "$REMOTE" ] && REMOTE="origin"
fi
[ -z "$BRANCH" ] && BRANCH="$HEAD_BRANCH"

URL="$(git remote get-url "$REMOTE" 2>/dev/null)"
if [ -z "$URL" ]; then
  echo "[ERROR] this clone has no remote '$REMOTE', so there is no URL to hand over." >&2
  echo "        remotes present: $(git remote | tr '\n' ' ')" >&2
  echo "        add one first:  git remote add $REMOTE https://github.com/<user>/<repo>.git" >&2
  exit 1
fi

REPO_NAME="$(basename "$URL" .git)"
SHORT="${BRANCH#arena/}"; SHORT="${SHORT%%-*}"
[ -z "$FOLDER" ] && FOLDER="${REPO_NAME}-${SHORT}"

# The account policy (v2.9.2): a conversation/repo that belongs to an account
# pushes with THAT account. The repo owner is the account that must be pinned;
# the machine default stays whatever the user normally uses. So the pasted
# block gets a .\auth.ps1 -Account <owner> line.
OWNER="$(printf '%s' "$URL" | sed -n 's#.*[:/]\([^/:]*\)/[^/]*$#\1#p')"
case "$OWNER" in ""|*" "*|*"@"*) OWNER="" ;; esac

if [ "$BRANCH" != "$HEAD_BRANCH" ]; then
  echo "[REFUSED] sync.config.json branch=$BRANCH but HEAD is $HEAD_BRANCH" >&2
  echo "          the watcher would poll a branch nobody pushes to." >&2
  echo "          fix skills/git-sync/sync.config.json (or re-run agent-install.sh) first." >&2
  exit 3
fi

PUSHED="yes"
git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1 || PUSHED="no"

if [ "$JSON" = 1 ]; then
  python3 - "$URL" "$BRANCH" "$FOLDER" "$PUSHED" "$REPO_NAME" "$OWNER" <<'PY'
import json, sys
url, branch, folder, pushed, repo, owner = sys.argv[1:7]
print(json.dumps({"url": url, "branch": branch, "folder": folder,
                  "branch_pushed": pushed == "yes", "repo": repo,
                  "owner": owner, "account": owner}, ensure_ascii=False))
PY
  exit 0
fi

PIN_LINE=''
ACCT_LINE=''
if [ -n "$OWNER" ]; then
  PIN_LINE=".\auth.ps1 -Account $OWNER    # policy: push as the REPO OWNER's account"
  ACCT_LINE="   account   : $OWNER  (the repo owner - this clone is pinned to it)"
fi

cat <<EOF
== paste this on YOUR machine (Windows PowerShell) - generated, do not retype

\`\`\`powershell
cd E:\\0github\\git-sync
git clone -b $BRANCH $URL $FOLDER
cd $FOLDER
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\\bootstrap.ps1 -Auto      # identity + branch + silent-push auth + register the watcher
${PIN_LINE}
.\\doctor.ps1               # branch=$BRANCH, ahead/behind 0/0, watcher/heartbeat/auth OK
.\\watch.ps1 -Status
\`\`\`

   repo      : $REPO_NAME ($URL)
   branch    : $BRANCH  (pushed to $REMOTE: $PUSHED)
   folder    : $FOLDER   (a NEW folder - never overwrite an existing clone)
   watcher   : git-sync-watch-$FOLDER
${ACCT_LINE}
EOF

if [ "$PUSHED" = "no" ]; then
  cat <<EOF

[NOTE] $REMOTE/$BRANCH does not exist yet - push first:
   bash skills/git-sync/scripts/agent-sync.sh "feat: ..."
EOF
fi

cat <<EOF

already cloned this branch before? then instead of the clone:
   cd <that folder> ; .\\sync.ps1 ; .\\watch.ps1 -Focus ; .\\doctor.ps1

this block registers a watcher; -Register parks the OTHER git-sync-watch-* tasks
on that machine. To bring them back:  .\\watch.ps1 -RestoreParked
EOF
