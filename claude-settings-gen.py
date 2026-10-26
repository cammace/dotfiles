#!/usr/bin/env python3
"""claude-settings-gen.py - build this Mac's Claude Code settings from another Mac's.

    ~/claude-settings-gen.py SOURCE.json [--out PATH] [--dry-run]

~/.claude/settings.json is hand-built on the laptop and holds absolute paths,
so it cannot be tracked as-is. Copy the laptop's file over (scp), then run this
on the target Mac. It:
  - rewrites the source home (/Users/<name>, read from the file) to $HOME
  - drops every hook whose script is not on this Mac (iTerm2's cc-status, the
    vgradle and Blueprint guards), so no hook fails on every event
  - drops permission rules for paths under $HOME that do not exist here
  - on machine-role server, drops the voice keys (no microphone)
The old file is kept as settings.json.bak-<timestamp>. Python 3 stdlib only.
"""
import argparse
import json
import os
import re
import shlex
import shutil
import sys
import time

HOME = os.path.expanduser("~")
ROLE_FILE = os.path.join(HOME, ".config", "machine-role")
SERVER_DROP_KEYS = ("voice", "voiceEnabled", "preferredNotifChannel")


def role():
    try:
        with open(ROLE_FILE) as f:
            return f.read().strip() or "laptop"
    except OSError:
        return "laptop"


def source_home(text):
    homes = set(re.findall(r"/Users/([A-Za-z0-9._-]+)", text))
    homes.discard(os.path.basename(HOME))
    if len(homes) > 1:
        sys.exit(f"source names more than one home ({', '.join(sorted(homes))}); pass a single-account file")
    return f"/Users/{homes.pop()}" if homes else None


def script_of(command):
    """The first absolute or ~ path in a hook command, or None."""
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    for w in words:
        w = os.path.expandvars(os.path.expanduser(w))
        if w.startswith("/"):
            return w
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("source")
    ap.add_argument("--out", default=os.path.join(HOME, ".claude", "settings.json"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    text = open(a.source).read()
    old = source_home(text)
    if old:
        text = text.replace(old + "/", HOME + "/").replace(f'"{old}"', f'"{HOME}"')
    cfg = json.loads(text)
    dropped = []

    hooks = cfg.get("hooks", {})
    for event in list(hooks):
        groups = []
        for g in hooks[event]:
            kept = []
            for h in g.get("hooks", []):
                path = script_of(h.get("command", "")) if h.get("type", "command") == "command" else None
                if path and path.startswith(HOME) and not os.path.exists(path):
                    dropped.append(f"hook {event}: {path}")
                else:
                    kept.append(h)
            if kept:
                groups.append({**g, "hooks": kept})
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]

    perms = cfg.get("permissions", {})
    for kind in ("allow", "ask", "deny"):
        rules = perms.get(kind)
        if not rules:
            continue
        keep = []
        for r in rules:
            paths = re.findall(re.escape(HOME) + r"/[^\s)*\"']+", r)
            gone = [p for p in paths if not os.path.exists(p.rstrip("/"))]
            # A deny rule is a fence: keep it even when its path is missing.
            if gone and kind != "deny":
                dropped.append(f"permission {kind}: {r}")
            else:
                keep.append(r)
        perms[kind] = keep

    if role() == "server":
        for k in SERVER_DROP_KEYS:
            if k in cfg:
                del cfg[k]
                dropped.append(f"key {k} (server)")

    out = json.dumps(cfg, indent=2) + "\n"
    print(f"source home: {old or '(none)'} -> {HOME}; role: {role()}")
    for d in dropped:
        print(f"  dropped {d}")
    left = out.count("/Users/") - out.count(HOME + "/") - out.count(f'"{HOME}"')
    if left:
        print(f"  WARNING: {left} other /Users/ path(s) remain; check them", file=sys.stderr)
    if a.dry_run:
        print(f"dry run: would write {a.out} ({len(out)} bytes)")
        return
    if os.path.exists(a.out):
        shutil.copy2(a.out, f"{a.out}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        f.write(out)
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
