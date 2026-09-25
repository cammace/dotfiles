#!/bin/bash
# Cmd-click handler for GitHub refs, wired as an iTerm2 Smart Selection "Run Command" action.
#   Parameter (interpolated): ~/.iterm2/gh-ref-open.sh \(matches[2]) \(jobPid) \(matches[1])
#   $1 = number   $2 = foreground job pid (or a dir)   $3 = owner/repo, absent for a bare #123.
# iTerm2 backslash-escapes captures for Run Command, so they go unquoted; the repo
# sits last so an empty capture drops off the end instead of shifting args.
# Bare "#123" resolves against the git remote of the foreground job's real cwd, read
# with lsof - iTerm2's \d / \(path) is stale when `cd && claude` runs on one line.
# `gh browse N` picks issues/ or pull/ itself. GH_REF_OPEN_DRYRUN=1 prints instead of opening.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
num="$1" dir="$2" repo="$3"
if [ ! -d "$dir" ]; then dir=$(/usr/sbin/lsof -a -p "$dir" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); fi
[ -n "$num" ] || exit 1

if [ -n "$repo" ]; then
  url=$(gh browse "$num" -R "$repo" -n 2>/dev/null) || url="https://github.com/$repo/issues/$num"
else
  url=$(cd "$dir" 2>/dev/null && gh browse "$num" -n 2>/dev/null) || exit 1
fi

if [ -n "$GH_REF_OPEN_DRYRUN" ]; then echo "$url"; else open -a "Google Chrome" "$url"; fi
