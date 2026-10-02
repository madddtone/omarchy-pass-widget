#!/usr/bin/env python3
"""Import credentials into a pass-cli vault from common export files.

Supports CSV (Chrome/Edge/Brave, Bitwarden, 1Password, Proton Pass, KeePass),
JSON arrays/objects, and ZIP archives of CSVs (Proton Pass exports a zip).

Usage:
  import.py <file> [--dry-run] [--overwrite] [--json] [--default-category C]
            [--pass-cli PATH] [--config PATH] [--quiet]

Passwords are passed to `pass-cli add` via argv, which is briefly visible to
same-user processes on Linux. Run on a trusted machine.
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import zipfile

HEADER_ALIASES = {
    "service": ["name", "title", "service", "itemname", "item name", "login", "site", "account name"],
    "username": ["username", "user", "login_username", "login username", "user name", "login name", "account"],
    "email": ["email", "e-mail", "email address", "emailaddress"],
    "password": ["password", "pass", "login_password", "login password", "secret"],
    "url": ["url", "website", "uri", "login_uri", "login uri", "login url", "web site", "link"],
    "notes": ["note", "notes", "extra", "comments", "comment"],
    "category": ["category", "folder", "group", "collection", "vault", "tags"],
    "kind": ["type", "kind"],
    "totp": ["totp", "otp", "login_totp", "login totp", "otpsecret", "otp secret", "one-time password", "authenticator key"],
}

LOGIN_KINDS = {"", "login", "password", "credential", "logins"}


def log(msg, quiet=False):
    if not quiet:
        print(msg, file=sys.stderr)


def canonical_header(name):
    n = re.sub(r"[_\-]+", " ", (name or "")).strip().lower()
    n = re.sub(r"\s+", " ", n)
    for key, aliases in HEADER_ALIASES.items():
        if n in aliases:
            return key
    for key, aliases in HEADER_ALIASES.items():
        for alias in aliases:
            if n == alias:
                return key
    return None


def map_row(raw):
    out = {}
    for k, v in raw.items():
        key = canonical_header(k)
        if key and key not in out:
            out[key] = "" if v is None else str(v).strip()
    for key in ("service", "username", "email", "password", "url", "notes", "category", "kind", "totp"):
        out.setdefault(key, "")
    return out


def rows_from_csv_text(text):
    text = text.lstrip("\ufeff")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
    except Exception:
        dialect = csv.excel
    reader = csv.reader(io.StringIO(text), dialect)
    rows = list(reader)
    rows = [r for r in rows if any((c or "").strip() for c in r)]
    if not rows:
        return []
    header = rows[0]
    mapped = [canonical_header(h) for h in header]
    if not any(mapped):
        return []
    result = []
    for row in rows[1:]:
        raw = {}
        for i, cell in enumerate(row):
            if i < len(header):
                raw[header[i]] = cell
        m = map_row(raw)
        if any(m.values()):
            result.append(m)
    return result


def rows_from_json(obj):
    if isinstance(obj, dict):
        for key in ("items", "credentials", "entries", "logins", "data"):
            if isinstance(obj.get(key), list):
                obj = obj[key]
                break
        else:
            obj = [obj]
    if not isinstance(obj, list):
        return []
    result = []
    for entry in obj:
        if isinstance(entry, dict):
            m = map_row({k: v for k, v in entry.items() if not isinstance(v, (dict, list))})
            if any(m.values()):
                result.append(m)
    return result


def load_rows(path):
    lower = path.lower()
    if lower.endswith(".zip"):
        rows = []
        with zipfile.ZipFile(path) as z:
            for info in z.namelist():
                if info.lower().endswith(".csv"):
                    rows.extend(rows_from_csv_text(z.read(info).decode("utf-8", "replace")))
                elif info.lower().endswith(".json"):
                    try:
                        rows.extend(rows_from_json(json.loads(z.read(info).decode("utf-8", "replace"))))
                    except Exception:
                        pass
        return rows
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    if lower.endswith(".json") or text.lstrip()[:1] in "[{":
        try:
            return rows_from_json(json.loads(text))
        except Exception as exc:
            log("JSON parse failed: %s" % exc)
            return []
    return rows_from_csv_text(text)


def derive_service(row, used, index):
    name = (row.get("service") or "").strip()
    if not name:
        url = row.get("url") or ""
        host = re.sub(r"^[a-z][a-z0-9+.\-]*://", "", url, flags=re.I)
        host = host.split("/")[0].split("@")[-1].split(":")[0]
        host = re.sub(r"^www\.", "", host, flags=re.I)
        name = host or (row.get("username") or "").strip()
    if not name:
        name = "imported-%d" % index
    base = name
    n = 2
    while name in used:
        name = "%s-%d" % (base, n)
        n += 1
    used.add(name)
    return name


def run_pass_cli(args, bin_path, config):
    cmd = [bin_path]
    if config:
        cmd += ["--config", config]
    cmd += args
    return subprocess.run(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def list_existing(bin_path, config):
    proc = run_pass_cli(["list", "--format", "simple"], bin_path, config)
    if proc.returncode != 0:
        return None
    return set(line.strip() for line in proc.stdout.splitlines() if line.strip())


CANDIDATE_DIRS = ["Downloads", "Desktop", "Documents", ""]
CANDIDATE_EXTS = (".csv", ".json", ".zip")
CANDIDATE_SKIP = {
    "package.json", "package-lock.json", "tsconfig.json", "composer.json",
    "composer.lock", "manifest.json", "settings.json", "keybindings.json",
    ".eslintrc.json", "deno.json", "bun.lockb",
}


def list_candidates(limit=40):
    home = os.path.expanduser("~")
    found = []
    seen = set()
    for rel in CANDIDATE_DIRS:
        directory = os.path.join(home, rel) if rel else home
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            if not name.lower().endswith(CANDIDATE_EXTS):
                continue
            if name in CANDIDATE_SKIP:
                continue
            path = os.path.join(directory, name)
            if path in seen or not os.path.isfile(path):
                continue
            seen.add(path)
            try:
                stat = os.stat(path)
            except OSError:
                continue
            found.append({"path": path, "name": name, "dir": rel or "~", "size": stat.st_size, "mtime": int(stat.st_mtime)})
    found.sort(key=lambda f: f["mtime"], reverse=True)
    return found[:limit]


def browse(directory):
    directory = os.path.abspath(os.path.expanduser(directory or "~"))
    if not os.path.isdir(directory):
        return {"ok": False, "error": "not a directory: %s" % directory, "dir": directory, "entries": []}
    dirs, files = [], []
    try:
        names = os.listdir(directory)
    except OSError as exc:
        return {"ok": False, "error": str(exc), "dir": directory, "entries": []}
    for name in names:
        if name.startswith("."):
            continue
        path = os.path.join(directory, name)
        if os.path.isdir(path):
            dirs.append({"type": "dir", "name": name, "path": path})
        elif os.path.isfile(path) and name.lower().endswith(CANDIDATE_EXTS) and name not in CANDIDATE_SKIP:
            files.append({"type": "file", "name": name, "path": path})
    dirs.sort(key=lambda e: e["name"].lower())
    files.sort(key=lambda e: e["name"].lower())
    parent = os.path.dirname(directory)
    if parent == directory:
        parent = ""
    return {"ok": True, "dir": directory, "parent": parent, "home": os.path.expanduser("~"), "entries": dirs + files}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--list-candidates", action="store_true")
    ap.add_argument("--browse", nargs="?", const="~", default=None)
    ap.add_argument("--default-category", default="")
    ap.add_argument("--pass-cli", default=os.environ.get("PASS_CLI_BIN") or "pass-cli")
    ap.add_argument("--config", default=os.environ.get("PASS_CLI_CONFIG") or "")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if args.list_candidates:
        print(json.dumps({"ok": True, "candidates": list_candidates()}))
        return 0

    if args.browse is not None:
        print(json.dumps(browse(args.browse)))
        return 0

    if not args.file:
        print(json.dumps({"ok": False, "error": "no file given"}))
        return 2

    if not os.path.exists(args.file):
        print(json.dumps({"ok": False, "error": "file not found: %s" % args.file}))
        return 2

    rows = load_rows(args.file)
    if not rows:
        print(json.dumps({"ok": False, "error": "no credentials found (unsupported format?)"}))
        return 2

    existing = list_existing(args.pass_cli, args.config)
    if existing is None and not args.dry_run:
        print(json.dumps({"ok": False, "error": "could not read the vault (is it unlocked? run 'pass-cli keychain enable')"}))
        return 3
    existing = existing or set()

    used = set()
    added, updated, skipped, failed = 0, 0, 0, 0
    errors = []
    results = []

    total_rows = len(rows)
    for i, row in enumerate(rows, 1):
        # Progress on stderr so the widget can show movement; stdout stays JSON.
        print("PROGRESS %d %d" % (i, total_rows), file=sys.stderr, flush=True)
        label = (row.get("service") or "").strip() or ("imported-%d" % i)
        kind = (row.get("kind") or "").strip().lower()
        password = row.get("password") or ""
        # Decide skips before naming so a skipped row never consumes a service
        # name that a real entry would otherwise use.
        if kind not in LOGIN_KINDS:
            skipped += 1
            results.append({"service": label, "action": "skip", "reason": "type:" + kind})
            continue
        if not password:
            # pass-cli cannot store an empty password and prompts on a TTY we
            # do not provide. Usually a passkey-only entry; skip it.
            skipped += 1
            results.append({"service": label, "action": "skip", "reason": "no-password"})
            continue

        service = derive_service(row, used, i)
        username = row.get("username") or row.get("email") or ""
        url = row.get("url") or ""
        notes = row.get("notes") or ""
        category = row.get("category") or args.default_category
        totp = row.get("totp") or ""

        exists = service in existing
        action = "update" if (exists and args.overwrite) else ("skip" if exists else "add")
        results.append({"service": service, "action": action, "username": username})

        if action == "skip":
            skipped += 1
            continue
        if args.dry_run:
            if action == "update":
                updated += 1
            else:
                added += 1
            continue

        cli = ["update", service, "--force"] if action == "update" else ["add", service]
        cli += ["--username", username or service]
        cli += ["--password", password]
        if url:
            cli += ["--url", url]
        if notes:
            cli += ["--notes", notes]
        if category:
            cli += ["--category", category]
        if totp:
            if totp.lower().startswith("otpauth://"):
                cli += ["--totp-uri", totp]
            elif re.fullmatch(r"[A-Za-z2-7=]{16,}", totp):
                label = service + (":" + username if username else "")
                cli += ["--totp-uri", "otpauth://totp/%s?secret=%s" % (label, totp.upper())]

        proc = run_pass_cli(cli, args.pass_cli, args.config)
        if proc.returncode == 0:
            if action == "update":
                updated += 1
            else:
                added += 1
        else:
            failed += 1
            msg = (proc.stderr or proc.stdout or "").strip().splitlines()
            errors.append({"service": service, "error": msg[0] if msg else "unknown error"})

    summary = {
        "ok": failed == 0,
        "total": len(rows),
        "added": added,
        "updated": updated,
        "skipped": skipped,
        "failed": failed,
        "dryRun": args.dry_run,
        "errors": errors[:50],
        "items": results,
    }
    print(json.dumps(summary))
    if not args.json and not args.dry_run:
        log("Imported %d, updated %d, skipped %d, failed %d (of %d)"
            % (added, updated, skipped, failed, len(rows)), args.quiet)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
