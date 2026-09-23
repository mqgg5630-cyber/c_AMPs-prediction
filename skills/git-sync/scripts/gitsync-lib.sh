#!/usr/bin/env bash
# gitsync-lib.sh - shared helpers for the Linux user-side scripts
# (sync.sh / push.sh / watch.sh / doctor.sh / hardware.sh).
# Same protocol as the Windows .ps1 set: one repo, one branch, handshake.json.
# Sourced, not executed.

_gs_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repo root: scripts live either in <repo>/ (root copies) or <repo>/skills/git-sync/scripts/
if [ -f "$_gs_here/skills/git-sync/sync.config.json" ]; then REPO="$_gs_here";
elif [ -f "$_gs_here/../sync.config.json" ]; then REPO="$(cd "$_gs_here/../../.." && pwd)";
else REPO="$(git -C "$_gs_here" rev-parse --show-toplevel 2>/dev/null || echo "$_gs_here")"; fi
cd "$REPO" || exit 1

CFG="${GIT_SYNC_CONFIG:-}"
if [ -z "$CFG" ]; then
  if [ -n "${GIT_SYNC_PROFILE:-}" ] && [ -f "skills/git-sync/sync.config.$GIT_SYNC_PROFILE.json" ]; then
    CFG="skills/git-sync/sync.config.$GIT_SYNC_PROFILE.json"
  else CFG="skills/git-sync/sync.config.json"; fi
fi
[ -f "$CFG" ] || { echo "[ERROR] config not found: $CFG" >&2; exit 1; }

PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "[ERROR] python3 is required" >&2; exit 1; }

cfg() {  # cfg <key> [default]
  "$PY" - "$CFG" "$1" "${2:-}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
v = d.get(sys.argv[2], sys.argv[3])
if isinstance(v, bool): v = 'true' if v else 'false'
if isinstance(v, (list, dict)): v = json.dumps(v, ensure_ascii=False)
print(v if v is not None else '')
PY
}

BRANCH="$(cfg branch)"; REMOTE="$(cfg remote origin)"
HANDSHAKE="$(cfg handshake results/status/handshake.json)"; HANDSHAKE="${HANDSHAKE//\\//}"
CHECK_CMD="$(cfg check_cmd_linux "bash code/local_check.sh")"
TIMEOUT_MIN="$(cfg check_timeout_min 30)"
HANDS_FREE="$(cfg hands_free false)"; AUTO_PULL="$(cfg auto_pull false)"; AUTO_PUSH="$(cfg auto_push false)"
AUTO_PREFIX="$(cfg auto_push_prefix "local: auto")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/git-sync/$(basename "$REPO")"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/watch.log"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
say() { echo "$*"; log "$*"; }
guard_branch() {
  case "$BRANCH" in main|master|'') echo "[REFUSED] config branch is '$BRANCH'" >&2; exit 1;; esac
  local cur; cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ "$cur" != "$BRANCH" ]; then
    git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" "$REMOTE/$BRANCH" || { echo "[ERROR] cannot switch to $BRANCH" >&2; exit 1; }
  fi
}
json_get() {  # json_get <file-or-text> <key>
  "$PY" - "$1" "$2" <<'PY'
import json, sys, os
src = sys.argv[1]
txt = open(src, encoding='utf-8-sig').read() if os.path.isfile(src) else src
try: print(json.loads(txt).get(sys.argv[2], '') or '')
except Exception: print('')
PY
}
