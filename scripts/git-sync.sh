#!/usr/bin/env bash
# Git-based sync for the pass-cli encrypted vault.
#
# Tracks only the encrypted vault file(s) in a private git remote. Everything
# else in the vault directory (audit log, backups, config) is ignored.
#
# Subcommands:
#   status                 JSON: enabled/remote/branch/dirty/ahead/behind/last
#   init [remote-url]      create the repo, initial commit, optionally set/push
#   push [message]         commit tracked files and push
#   pull                   fast-forward pull
#   remote <url>           set/change the origin remote
set -uo pipefail

VAULT_DIR="${PASS_CLI_VAULT_DIR:-$HOME/.pass-cli}"
TRACKED=(vault.enc)
BRANCH="${PASS_CLI_GIT_BRANCH:-main}"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
gitq() { git -C "$VAULT_DIR" "$@"; }
is_repo() { gitq rev-parse --is-inside-work-tree >/dev/null 2>&1; }

ensure_gitignore() {
  local gi="$VAULT_DIR/.gitignore"
  if [ ! -f "$gi" ]; then
    cat > "$gi" <<'EOF'
audit.log
vault.enc.meta.json
vault.enc.backup
*.backup
*.tmp.*
config.yml
config.yaml
EOF
  else
    grep -qx 'vault.enc.meta.json' "$gi" || printf 'vault.enc.meta.json\n' >> "$gi"
  fi
}

tracked_files() {
  local out=() f
  for f in "${TRACKED[@]}"; do [ -f "$VAULT_DIR/$f" ] && out+=("$f"); done
  printf '%s\n' "${out[@]:-}"
}

current_branch() {
  gitq rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$BRANCH"
}

cmd_status() {
  if ! is_repo; then
    printf '{"ok":true,"enabled":false}\n'
    return 0
  fi
  local remote branch dirty=false ahead=0 behind=0 last
  remote="$(gitq remote get-url origin 2>/dev/null || true)"
  branch="$(current_branch)"
  if [ -n "$(gitq status --porcelain 2>/dev/null)" ]; then dirty=true; fi
  if [ -n "$remote" ]; then
    gitq fetch --quiet origin "$branch" >/dev/null 2>&1 || true
    ahead="$(gitq rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)"
    behind="$(gitq rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)"
  fi
  last="$(gitq log -1 --pretty=%cI 2>/dev/null || true)"
  printf '{"ok":true,"enabled":true,"remote":"%s","branch":"%s","dirty":%s,"ahead":%s,"behind":%s,"last":"%s"}\n' \
    "$(json_escape "$remote")" "$(json_escape "$branch")" "$dirty" "$ahead" "$behind" "$(json_escape "$last")"
}

stage_and_commit() {
  local msg="$1" files=()
  ensure_gitignore
  mapfile -t files < <(tracked_files)
  gitq add .gitignore "${files[@]}" >/dev/null 2>&1 || true
  if ! gitq diff --cached --quiet; then
    gitq -c user.name="$(git config --global user.name || echo pass-cli)" \
        -c user.email="$(git config --global user.email || echo pass-cli@localhost)" \
        commit -q -m "$msg" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

cmd_init() {
  local remote="${1:-}"
  mkdir -p "$VAULT_DIR"
  if ! is_repo; then
    gitq init -q >/dev/null 2>&1 || { printf '{"ok":false,"error":"git init failed"}\n'; return 1; }
    gitq checkout -q -b "$BRANCH" >/dev/null 2>&1 || true
  fi
  stage_and_commit "vault: initial commit" || true
  if [ -n "$remote" ]; then
    gitq remote remove origin >/dev/null 2>&1 || true
    gitq remote add origin "$remote"
  fi
  local r; r="$(gitq remote get-url origin 2>/dev/null || true)"
  if [ -n "$r" ]; then
    if ! gitq push -u origin "$BRANCH" >/dev/null 2>&1; then
      printf '{"ok":false,"error":"push failed; remote may already have history"}\n'
      return 1
    fi
  fi
  printf '{"ok":true,"remote":"%s","branch":"%s"}\n' "$(json_escape "$r")" "$BRANCH"
}

cmd_remote() {
  local url="${1:-}"
  if [ -z "$url" ]; then printf '{"ok":false,"error":"no url"}\n'; return 1; fi
  is_repo || { printf '{"ok":false,"error":"not initialized"}\n'; return 1; }
  gitq remote remove origin >/dev/null 2>&1 || true
  gitq remote add origin "$url"
  printf '{"ok":true,"remote":"%s"}\n' "$(json_escape "$url")"
}

cmd_push() {
  is_repo || { printf '{"ok":false,"error":"git sync not initialized"}\n'; return 1; }
  local msg="${1:-vault: $(date -Iseconds)}"
  stage_and_commit "$msg" || true
  local branch; branch="$(current_branch)"
  if gitq remote get-url origin >/dev/null 2>&1; then
    if ! gitq push origin "$branch" >/dev/null 2>&1; then
      printf '{"ok":false,"error":"push failed (check remote/auth or pull first)"}\n'
      return 1
    fi
  fi
  printf '{"ok":true,"pushed":true,"branch":"%s"}\n' "$(json_escape "$branch")"
}

cmd_pull() {
  is_repo || { printf '{"ok":false,"error":"git sync not initialized"}\n'; return 1; }
  local branch; branch="$(current_branch)"
  gitq remote get-url origin >/dev/null 2>&1 || { printf '{"ok":false,"error":"no remote"}\n'; return 1; }
  gitq fetch origin "$branch" >/dev/null 2>&1 || { printf '{"ok":false,"error":"fetch failed"}\n'; return 1; }
  if gitq pull --ff-only origin "$branch" >/dev/null 2>&1; then
    printf '{"ok":true,"pulled":true}\n'
  else
    printf '{"ok":false,"error":"cannot fast-forward: local and remote diverged"}\n'
    return 1
  fi
}

case "${1:-}" in
  status) shift || true; cmd_status "$@" ;;
  init) shift || true; cmd_init "$@" ;;
  remote) shift || true; cmd_remote "$@" ;;
  push) shift || true; cmd_push "$@" ;;
  pull) shift || true; cmd_pull "$@" ;;
  *) printf '{"ok":false,"error":"usage: git-sync.sh status|init|remote|push|pull"}\n'; exit 2 ;;
esac
