#!/usr/bin/env bash
# Safe non-interactive pass-cli runner for the kalel.pass widget.
# Options before the command:
#   --bin <path>      explicit pass-cli binary
#   --config <path>   pass-cli config file
#   --discard         send pass-cli stdout to /dev/null (for actions where the
#                     secret must not enter QML; pass-cli copies it itself)
#   --clip-clear <s>  after the command, detach a helper that clears the
#                     clipboard in <s> seconds if it still holds our value.
#                     pass-cli's own 5s clear runs in a goroutine that dies
#                     with the process, so it never fires for us.
#   --                end of options
set -uo pipefail

BIN_OPT=""
CONFIG_OPT=""
DISCARD=0
CLIP_CLEAR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin) BIN_OPT="${2:-}"; shift 2 ;;
    --config) CONFIG_OPT="${2:-}"; shift 2 ;;
    --discard) DISCARD=1; shift ;;
    --clip-clear) CLIP_CLEAR="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

BIN="$BIN_OPT"
if [[ -z "$BIN" ]]; then
  BIN="$(command -v pass-cli 2>/dev/null || true)"
fi
if [[ -z "$BIN" ]]; then
  for c in "$HOME/.local/bin/pass-cli" /usr/local/bin/pass-cli /usr/bin/pass-cli; do
    if [[ -x "$c" ]]; then BIN="$c"; break; fi
  done
fi
if [[ -z "$BIN" ]]; then
  echo "pass-cli binary not found" >&2
  exit 127
fi

CONFIG_ARGS=()
if [[ -n "$CONFIG_OPT" ]]; then
  CONFIG_ARGS=(--config "$CONFIG_OPT")
fi

TIMEOUT="${PASS_CLI_TIMEOUT:-8}"

if [[ -n "$CLIP_CLEAR" && "$CLIP_CLEAR" =~ ^[0-9]+$ && "$CLIP_CLEAR" -gt 0 ]]; then
  # Copy the secret ourselves so the value we later compare against the
  # clipboard is exactly what we put there. pass-cli's own 5s clear runs in a
  # goroutine that dies with the process, so it never fires for us.
  # Invoke as: --clip-clear <s> -- <get args with --quiet --no-clipboard>.
  expected="$(timeout --signal=TERM "$TIMEOUT" "$BIN" "${CONFIG_ARGS[@]}" "$@" </dev/null)"
  rc=$?
  expected="${expected%$'\n'}"
  if [[ $rc -eq 0 && -n "$expected" ]]; then
    printf '%s' "$expected" | wl-copy
    (
      sleep "$CLIP_CLEAR"
      current="$(wl-paste 2>/dev/null || true)"
      [[ "$current" == "$expected" ]] && wl-copy --clear 2>/dev/null
    ) >/dev/null 2>&1 &
  else
    printf '%s\n' "$expected" >&2
  fi
  exit "$rc"
fi

if [[ "$DISCARD" -eq 1 ]]; then
  exec timeout --signal=TERM "$TIMEOUT" "$BIN" "${CONFIG_ARGS[@]}" "$@" </dev/null >/dev/null
else
  exec timeout --signal=TERM "$TIMEOUT" "$BIN" "${CONFIG_ARGS[@]}" "$@" </dev/null
fi
