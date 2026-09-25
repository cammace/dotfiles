#!/bin/bash
# Cmd-click handler for GitHub refs, wired as an iTerm2 Smart Selection "Run Command" action.
#   Parameter (interpolated): ~/.iterm2/gh-ref-open.sh \(matches[2]) \(jobPid) \(matches[1])
#   $1 = number   $2 = foreground job pid (or a dir)   $3 = owner/repo, absent for a bare #123.
# iTerm2 backslash-escapes captures for Run Command, so they go unquoted; the repo
# sits last so an empty capture drops off the end instead of shifting args.
# Bare "#123" tries the git remote of the foreground job's real cwd first, read with
# lsof - iTerm2's \d / \(path) is stale when `cd && claude` runs on one line. If that
# repo has no such number (a vault session citing a viewer issue), FALLBACK_REPOS are
# tried in order. The issues endpoint answers for PRs too and returns the /pull/ URL.
# GH_REF_OPEN_DRYRUN=1 prints instead of opening.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
FALLBACK_REPOS=(commhospital/viewer commhospital/ETL-Studio commhospital/ai-marketplace cammace/clio)
num="$1" dir="$2" repo="$3"
if [ ! -d "$dir" ]; then dir=$(/usr/sbin/lsof -a -p "$dir" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); fi
[ -n "$num" ] || exit 1

lookup() {  # prints the html_url only when the number exists; gh prints 404 bodies to stdout
  local u; u=$(gh api "repos/$1/issues/$num" --jq .html_url 2>/dev/null) || return 1
  case "$u" in https://*) echo "$u" ;; *) return 1 ;; esac
}

if [ -n "$repo" ]; then
  url=$(lookup "$repo") || url="https://github.com/$repo/issues/$num"
else
  here=$(git -C "$dir" remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
  url=""
  for r in $here "${FALLBACK_REPOS[@]}"; do
    url=$(lookup "$r") && break
  done
  if [ -z "$url" ]; then
    [ -n "$here" ] || exit 1
    url="https://github.com/$here/issues/$num"
  fi
fi

if [ -n "$GH_REF_OPEN_DRYRUN" ]; then echo "$url"; else open -a "Google Chrome" "$url"; fi
