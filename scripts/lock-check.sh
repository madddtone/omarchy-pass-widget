#!/usr/bin/env bash
# Verify the user's system password without storing anything.
# Reads the password from stdin (never argv) and validates it through PAM via
# `sudo -v`. The sudo timestamp is invalidated before and after, so this does
# not leave sudo unlocked.
#
#   printf '%s\n' "<password>" | lock-check.sh   -> {"ok":true|false}
set -uo pipefail

IFS= read -r pw || true
if [ -z "${pw:-}" ]; then
  printf '{"ok":false}\n'
  exit 0
fi

sudo -k >/dev/null 2>&1 || true
if printf '%s\n' "$pw" | sudo -S -v -p '' >/dev/null 2>&1; then
  sudo -k >/dev/null 2>&1 || true
  printf '{"ok":true}\n'
else
  printf '{"ok":false}\n'
fi
