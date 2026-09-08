#!/usr/bin/env python3
"""Stop hook: block the turn while a watched repo has commits that never reached its remote.

Why this exists: on 2026-09-06 `~/Developer/homelab` was found four commits ahead of
origin, the oldest stranded three days across three separate sessions. Every session had
the rule available to it - `homelab/CLAUDE.md` says plainly that `git push` is fine there -
and every session still ended its turn at the commit. Prose did not fix it, so this checks
instead. See `feedback_patch_check_dont_walk_noise`: fix the producer.

What it then ran into, and what fixed it (2026-09-08): a session started in the Clio vault
could not satisfy this hook. `Clio.nosync/.claude/settings.json` denied `Bash(git push *)`,
a deny rule matches the command string and not the repo, and a hook `allow` cannot lift a
deny - so this hook demanded a push the permission layer refused, in exactly the topology
the `homelab` agent runs in (a subagent of a Clio session). That deny is now replaced by
`Clio.nosync/hooks/git-transport-guard.py`, which fences push/pull on the VAULT'S repo only.
If this hook ever blocks a stop that cannot be satisfied again, the fix is in that guard,
not here - and never route around it by pushing from a session that was denied.

Contract (only doc-confirmed semantics are used):
  exit 0, no output   -> nothing stranded, stop proceeds silently
  exit 2 + stderr     -> blocks the stop; stderr is fed to the model as the reason
  exit 0 + stdout JSON `systemMessage` -> shown to the user, does not block

Deliberately NOT used: the `decision`/`continue` JSON fields. For Stop the blocking value is
`decision: "block"` (verified 2026-09-06 against the hooks guide), but a wrong field name
silently no-ops - precisely the failure mode this hook exists to catch
(`feedback_instrument_before_trusting_silence`) - and exit 2 needs no field name at all.
"""

import hashlib
import json
import os
import subprocess
import sys

# Repos that are pushed to directly (no PR flow). Extend deliberately: a repo whose
# convention is "open a PR" does NOT belong here, or the hook will nag about work that
# is correctly waiting on review.
WATCHED = [
    os.path.expanduser("~/Developer/homelab"),
    # Added 2026-09-08: it was found 3 commits ahead alongside homelab's 4. Its own
    # CLAUDE.md says "always commit and push to main" because the git_pull add-on
    # watches `main` - an unpushed commit there is a change that never ships.
    os.path.expanduser("~/Developer/home-assistant-config"),
]

MARKER_DIR = "/tmp/claude-unpushed-commits"


def git(repo, *args):
    """Run a read-only git command. Returns stripped stdout, or None on any failure."""
    try:
        p = subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return p.stdout.strip() if p.returncode == 0 else None


def mid_operation(repo):
    """True during a rebase/merge/cherry-pick - never nag someone mid-surgery."""
    gitdir = git(repo, "rev-parse", "--git-dir")
    if not gitdir:
        return True
    if not os.path.isabs(gitdir):
        gitdir = os.path.join(repo, gitdir)
    return any(
        os.path.exists(os.path.join(gitdir, n))
        for n in ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD")
    )


def inspect(repo):
    """Return a report dict when the repo has unpushed commits, else None."""
    if not os.path.isdir(repo) or git(repo, "rev-parse", "--git-dir") is None:
        return None
    if mid_operation(repo):
        return None

    # Detached HEAD has no upstream to be ahead of.
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    if not branch:
        return None

    # No upstream means nothing to push to - a local-only branch is not stranded work.
    if git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}") is None:
        return None

    counts = git(repo, "rev-list", "--left-right", "--count", "@{u}...HEAD")
    if not counts:
        return None
    try:
        behind, ahead = (int(n) for n in counts.split())
    except ValueError:
        return None
    if ahead == 0:
        return None

    subjects = git(repo, "log", "--format=%h %ad %s", "--date=short", "-n", "5", "@{u}..HEAD")
    head = git(repo, "rev-parse", "HEAD") or ""
    return {
        "repo": repo,
        "branch": branch,
        "ahead": ahead,
        "behind": behind,
        "head": head,
        "subjects": subjects or "",
    }


def already_nagged(session_id, reports):
    """Block once per (session, exact set of HEADs). New commits re-arm the check."""
    key = session_id + "|" + ",".join(r["head"] for r in reports)
    digest = hashlib.sha256(key.encode()).hexdigest()[:16]
    marker = os.path.join(MARKER_DIR, digest)
    if os.path.exists(marker):
        return True
    try:
        os.makedirs(MARKER_DIR, mode=0o700, exist_ok=True)
        open(marker, "w").close()
    except OSError:
        pass  # cannot dedupe; blocking once more is the safe direction
    return False


def render(reports):
    lines = []
    for r in reports:
        lines.append(
            f"{r['repo']} ({r['branch']}) is {r['ahead']} commit(s) ahead of its remote"
            + (f" and {r['behind']} behind" if r["behind"] else "")
            + ":"
        )
        lines.append(r["subjects"])
        if r["behind"]:
            lines.append(
                f"  Behind by {r['behind']}, so a plain push will be rejected. "
                "Fetch and rebase first, then push."
            )
        else:
            lines.append(f"  git -C {r['repo']} push")
    return "\n".join(lines)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}

    reports = [r for r in (inspect(p) for p in WATCHED) if r]
    if not reports:
        sys.exit(0)

    body = render(reports)
    session_id = str(payload.get("session_id", ""))

    # stop_hook_active means a previous block already triggered a continuation. The docs'
    # own example exits 0 here; the harness force-stops only after 8 consecutive blocks
    # (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP), so yielding at the first is deliberate - one
    # block is a reminder, eight is a session held hostage.
    if payload.get("stop_hook_active") or already_nagged(session_id, reports):
        print(json.dumps({"systemMessage": "Unpushed commits remain:\n" + body}))
        sys.exit(0)

    print(
        "Work was committed but never pushed, so it exists only on this machine:\n\n"
        + body
        + "\n\nPush it, or tell Cam why it should stay local. These repos push directly - "
        "they are not waiting on a PR.",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
