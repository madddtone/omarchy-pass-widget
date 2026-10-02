# Omarchy Pass Widget

A native [Omarchy](https://omarchy.org/) shell widget for the
[`pass-cli`](https://github.com/reyamira/pass-cli) password manager.

It runs inside the Omarchy shell (Quickshell) as a single plugin and gives you
two surfaces:

- a **bar popup** anchored to a key icon, and
- a **fullscreen vault browser** summoned by keybinding,

both keyboard-first, with search, copy, TOTP, a password generator, add/edit,
CSV import, and optional **GitHub git-sync** of the encrypted vault.

```
┌─ Pass ───────────────────────────────────────────────────────┐
│  Search vault…                                   Recent      │
├────────────┬────────────────────────┬────────────────────────┤
│ CATEGORIES │  github                │  github                │
│ All        │  user@example.com      │  Username  user@…      │
│ Personal   │  proton                │  Password  •••••• Show │
│ Work       │  accounts.google.com   │  Website   …      Open │
└────────────┴────────────────────────┴────────────────────────┘
```

## Requirements

- Omarchy (Quickshell shell)
- [`pass-cli`](https://github.com/reyamira/pass-cli) on `PATH`
- A `pass-cli` vault, ideally with keychain enabled
  (`pass-cli init` then `pass-cli keychain enable`) so the widget can read the
  vault non-interactively
- Optional: `git` + `gh` for GitHub sync; `python3` for CSV import

## Install

```bash
omarchy plugin add https://github.com/madddtone/omarchy-pass-widget.git --enable --yes
omarchy bar move madddtone.pass --section right
```

Or by hand: copy this directory to `~/.config/omarchy/plugins/madddtone.pass/`,
then `omarchy-shell shell rescanPlugins` and `omarchy plugin enable madddtone.pass`.

## Keybinding

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + CTRL + P", "Pass", "omarchy-shell shell summon madddtone.pass")
```

Left-click the bar icon opens the popup; right-click opens the fullscreen
browser.

## Keyboard

| Key | Action |
|---|---|
| type | search (service, username, URL, category, notes) |
| `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End` | move selection |
| `Enter` | copy password (auto-clears after 5s) |
| `Shift+Enter` | copy username |
| `Ctrl+Enter` | copy TOTP code |
| `Ctrl+O` | open URL in browser |
| `Ctrl+S` | reveal / hide password |
| `Ctrl+E` | edit selected |
| `Ctrl+N` | new credential |
| `Ctrl+G` | generate a password |
| `Ctrl+I` | import (CSV/JSON/ZIP) |
| `Ctrl+P` | git sync |
| `Ctrl+L` | lock now (requires the password again) |
| `Delete` | delete selected |
| `Tab` | toggle sort (recent / A–Z) |
| `R`/`Esc` | refresh / back |

## Import

`Ctrl+I` opens a file browser (starts at `~`, shows `.csv`/`.json`/`.zip`).
Supports Proton Pass, Chrome/Edge/Brave, Bitwarden, 1Password, and KeePass
exports. Headers are auto-mapped; duplicate names get `-2`, `-3`, … suffixes;
passwordless (passkey-only) rows are skipped and reported.

## GitHub sync

`Ctrl+P` shows sync status and Push/Pull. The widget git-tracks **only the
encrypted `vault.enc`** and pushes it to a private remote (auto-push after
changes is on by default). It is file-level sync of the encrypted blob — use
one machine at a time; if two diverge, git reports it and you pick a side.

## Lock (system password)

Set **Require system password to open** to `On` (settings, or `"requirePin": "On"`
on the widget's entry in `shell.json`). While enabled, every time the vault opens
it shows a lock screen and asks for your **login password** before revealing
anything. `Ctrl+L` locks it again immediately.

The password is verified through PAM via `sudo -v` with the value passed over
stdin, and the sudo timestamp is invalidated before and after — so nothing is
stored and sudo is not left unlocked. It requires your account to use a
password (not fingerprint-only login).

This is a privacy gate, not vault encryption: the vault file stays encrypted by
`pass-cli`, but anyone with your session and keychain can still run `pass-cli`
directly.

## Settings

Per-widget settings (via `~/.config/omarchy/shell.json` or the bar settings UI):
`glyph`, `showLabel`, `hideUsernames`, `lockMinutes`, `defaultCopyField`,
`passCliBin`, `vaultConfig`, `gitRemote`, `gitAuto`, `requirePin`.

## Security

- Passwords are never read into the widget for display except when you press
  **Show**; copying is delegated to `pass-cli` / `wl-copy`.
- Entering a password in the add/edit form is handed off to a terminal so the
  secret never enters the shell's QML memory.
- The vault on disk is encrypted (AES-256-GCM); only that file is synced.
- Auto-lock is UI-level only (the keychain keeps the vault unlocked).

## License

MIT — see [LICENSE](LICENSE).
