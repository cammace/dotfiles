#!/usr/bin/env bash
# PreToolUse gate. Wired PER REPO in each repo's .claude/settings.local.json
# (hooks.PreToolUse, matcher "Bash", timeout 900) — NOT user-level. As of 2026-08-24
# only `website` and `security` wire it; every other repo pushes ungated.
# Runs a Codex adversarial review ONLY before Claude:
#   1. opens a pull request        (`gh pr create` in any segment of the command), or
#   2. pushes to a branch that already has an OPEN PR (`git push`).
# Every other Bash command exits silently in a few ms — Codex is never invoked.
#
# Decision mapping:
#   verdict "approve"          → allow (systemMessage with the review summary)
#   verdict "needs-attention"  → deny  (findings fed back to Claude to fix)
#   gate cannot run (no codex, timeout, bad output) → ask (Cam decides; never silent)
#
# Bypass (only with Cam's explicit go-ahead): prefix the command with CODEX_PR_GATE_SKIP=1
# Test mode: CODEX_PR_GATE_TEST=1 in the environment prints what would run, skips Codex.
set -o pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"codex-pr-review-gate: jq not found, cannot inspect the command. Proceed without the Codex review?"}}'
  exit 0
fi

ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }
deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
note() { jq -cn --arg m "$1" '{systemMessage:$m}'; }

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
[ "$tool" = "Bash" ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0

case "$cmd" in *CODEX_PR_GATE_SKIP=1*) exit 0 ;; esac

cwd=$(jq -r '.cwd // empty' <<<"$input")
session_id=$(jq -r '.session_id // empty' <<<"$input")

# --- classify: does any shell segment invoke `git push` or `gh pr create`? ---
# Split on command separators, then find the real subcommand per segment
# (skipping VAR=VAL prefixes and pre-subcommand options), so strings like
# `git commit -m "push fix"` never match.
#
# The segment walk also tracks WHICH DIRECTORY the publish runs in, because the
# hook's own cwd is the session cwd and says nothing about a worktree the
# command cd'd into. Three sources, most specific first: `git -C <dir>` (push
# only), a `cd <dir>` segment earlier in the same command, then `.cwd` from the
# hook payload. Simple `VAR=value` assignments are recorded so `$VAR` in a later
# `cd`/`-C` path resolves — `WT=/path/to/wt; git -C $WT push` is the common shape.
# Getting this wrong reviews a DIFFERENT branch's diff and denies on findings
# that are not in the PR: `--cwd` is the only thing that selects the tree, since
# codex-companion has no branch/ref option.
mode=""
repo_override=""
cur_dir=""          # dir in effect from the last `cd` segment
push_dir=""         # cur_dir when the `git push` segment was seen
pr_dir=""           # cur_dir when the `gh pr create` segment was seen
pr_head=""          # --head/-H on `gh pr create`, if given
varnames=(); varvals=()

# Expand $NAME / ${NAME} using assignments seen earlier in this command.
# Substitute LONGEST NAME FIRST: `$W` is a prefix of `$WT`, so shortest-first
# would rewrite `WT=/b; git -C $WT push` (with W=/a also set) to `/aT` and send
# the review to the wrong tree. Multi-assignment one-liners like
# `WT=<dir> S=<scratch> git -C $WT push` are the normal shape here.
expand_vars() {
  local s="$1" k idx a b tmp
  local -a order=()
  for idx in "${!varnames[@]}"; do order+=("$idx"); done
  for ((a=1; a<${#order[@]}; a++)); do            # insertion sort, descending name length
    tmp=${order[$a]}
    for ((b=a-1; b>=0 && ${#varnames[${order[$b]}]} < ${#varnames[$tmp]}; b--)); do
      order[$((b+1))]=${order[$b]}
    done
    order[$((b+1))]=$tmp
  done
  for idx in "${order[@]}"; do
    k="${varnames[$idx]}"
    s="${s//\$\{$k\}/${varvals[$idx]}}"
    s="${s//\$$k/${varvals[$idx]}}"
  done
  printf '%s' "$s"
}

while IFS= read -r seg; do
  read -ra toks <<<"$seg" || continue
  n=${#toks[@]}
  [ "$n" -eq 0 ] && continue
  i=0
  # Record VAR=VAL prefixes (and bare `VAR=VAL` segments) before skipping them.
  while [ $i -lt $n ] && [[ "${toks[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    varnames+=("${toks[$i]%%=*}")
    varvals+=("$(expand_vars "${toks[$i]#*=}")")
    i=$((i+1))
  done
  [ $i -ge $n ] && continue
  prog="${toks[$i]##*/}"
  i=$((i+1))
  if [ "$prog" = "cd" ]; then
    # `cd` with no operand means $HOME; `cd -` is unresolvable, so drop the hint.
    #
    # Segments are also every LINE of the command, heredoc bodies included, so a
    # commit message line like "cd into the worktree first" parses as a cd. Only
    # honour an absolute/~ path or a directory that actually exists; anything
    # else is prose and must leave cur_dir untouched, or the resolution check
    # below would ask about a directory the command never named.
    if [ $i -lt $n ]; then
      cd_arg=$(expand_vars "${toks[$i]}")
      case "${toks[$i]}" in
        -) cur_dir="" ;;
        -*) ;;
        *) case "$cd_arg" in
             "~")   cur_dir="$HOME" ;;
             "~/"*) cur_dir="$HOME/${cd_arg#\~/}" ;;
             /*)    cur_dir="$cd_arg" ;;
             *)
               # Relative target: resolve against the directory a PRIOR cd
               # segment established, so `cd frontend && cd ../worktrees/x`
               # chains. Falls back to the payload cwd for the first hop.
               # The -d test doubles as the prose filter above: an unresolvable
               # path is a commit-message line, not a directory change.
               cd_base="${cur_dir:-${cwd:-$PWD}}"
               [ -d "${cd_base}/${cd_arg}" ] && cur_dir="${cd_base}/${cd_arg}"
               ;;
           esac ;;
      esac
    else
      cur_dir="$HOME"
    fi
  elif [ "$prog" = "git" ]; then
    seg_repo=""
    while [ $i -lt $n ]; do
      t="${toks[$i]}"
      case "$t" in
        -C) i=$((i+1)); [ $i -lt $n ] && seg_repo=$(expand_vars "${toks[$i]}"); i=$((i+1)) ;;
        -c|--exec-path|--git-dir|--work-tree|--namespace) i=$((i+2)) ;;
        -*) i=$((i+1)) ;;
        *) break ;;
      esac
    done
    [ $i -ge $n ] && continue
    if [ "${toks[$i]}" = "push" ]; then
      skip=""
      for t in "${toks[@]}"; do
        case "$t" in --dry-run|-n|--delete|-d|--tags) skip=1 ;; esac
      done
      if [ -z "$skip" ] && [ -z "$mode" ]; then
        mode="push"
        repo_override="$seg_repo"
        push_dir="$cur_dir"
      fi
    fi
  elif [ "$prog" = "gh" ]; then
    sub1="" sub2=""
    while [ $i -lt $n ]; do
      t="${toks[$i]}"
      case "$t" in
        -*) i=$((i+1)) ;;
        *) if [ -z "$sub1" ]; then sub1="$t"; elif [ -z "$sub2" ]; then sub2="$t"; break; fi; i=$((i+1)) ;;
      esac
    done
    if [ "$sub1" = "pr" ] && [ "$sub2" = "create" ]; then
      mode="prcreate"   # takes precedence: base-branch review covers any push in the same command
      pr_dir="$cur_dir"
      pr_head=""
      for ((j=0; j<n; j++)); do
        case "${toks[$j]}" in
          --head|-H) [ $((j+1)) -lt $n ] && pr_head=$(expand_vars "${toks[$((j+1))]}") ;;
          --head=*)  pr_head=$(expand_vars "${toks[$j]#--head=}") ;;
        esac
      done
    fi
  fi
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n')

[ -n "$mode" ] || exit 0

# --- repo context ---
# `explicit` marks a directory the COMMAND named. Failing to enter one of those
# must not fall through to the session cwd: that is the wrong-branch review.
target_dir="$cwd"
explicit=""
if [ "$mode" = "push" ] && [ -n "$repo_override" ]; then
  target_dir="$repo_override"; explicit="git -C"
elif [ "$mode" = "push" ] && [ -n "$push_dir" ]; then
  target_dir="$push_dir"; explicit="cd"
elif [ "$mode" = "prcreate" ] && [ -n "$pr_dir" ]; then
  target_dir="$pr_dir"; explicit="cd"
fi
case "$target_dir" in "~") target_dir="$HOME" ;; "~/"*) target_dir="$HOME/${target_dir#\~/}" ;; esac
if [ -n "$target_dir" ] && ! cd "$target_dir" 2>/dev/null; then
  [ -n "$explicit" ] && ask "Codex PR gate: the command targets '${target_dir}' (via ${explicit}) but that directory could not be entered, so the review would run against the session's directory and grade the WRONG branch's diff. Re-run with the shell already in that directory, or proceed without the pre-publish review?"
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
target_dir=$(pwd)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ "$branch" = "HEAD" ] && exit 0

# An explicit --head naming a branch other than this tree's HEAD means the review
# would grade the wrong diff. codex-companion cannot target a ref, so ask.
if [ "$mode" = "prcreate" ] && [ -n "$pr_head" ]; then
  head_branch="${pr_head##*:}"
  if [ -n "$head_branch" ] && [ "$head_branch" != "$branch" ]; then
    ask "Codex PR gate: --head is '${head_branch}' but ${target_dir} is on '${branch}', so the review would grade the wrong branch's diff. Re-run from a checkout of '${head_branch}', or proceed without the pre-publish review?"
  fi
fi

base=""
if [ "$mode" = "push" ]; then
  prinfo=$(gh pr view --json state,number,baseRefName 2>/dev/null) || exit 0
  state=$(jq -r '.state // empty' <<<"$prinfo")
  [ "$state" = "OPEN" ] || exit 0
  prnum=$(jq -r '.number // empty' <<<"$prinfo")
  base=$(jq -r '.baseRefName // empty' <<<"$prinfo")
  context="push new commits to open PR #${prnum} (branch ${branch})"
else
  base=$(printf '%s\n' "$cmd" | grep -oE -- '(--base|-B)[= ][^ ]+' | head -1 | sed -E 's/^(--base|-B)[= ]//')
  context="open a new pull request from branch ${branch}"
fi
if [ -n "$base" ] && git rev-parse --verify -q "origin/${base}" >/dev/null 2>&1; then
  base="origin/${base}"
fi

# --- run the review through the Codex companion (newest installed plugin version) ---
companion=$(ls -1d "$HOME/.claude/plugins/cache/openai-codex/codex"/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
[ -n "$companion" ] || ask "Codex PR gate: codex-companion.mjs not found (openai-codex plugin missing?). Proceed without the pre-publish review?"

if [ -n "${CODEX_PR_GATE_TEST:-}" ]; then
  note "CODEX_PR_GATE_TEST: would run adversarial-review (scope=branch cwd=${target_dir} base=${base:-auto-detect}) before: ${context}"
  exit 0
fi

focus="Pre-publish gate: Claude Code is about to ${context}. Review whether this branch's changes are safe to publish. Prioritize real defects — correctness, security, data loss, broken behavior, second-order failures. Do not return needs-attention for stylistic nits or preferences."

args=(adversarial-review --wait --json --scope branch)
# Always pin --cwd to the tree we actually resolved and cd'd into. Guarding this
# on the payload's $cwd meant an empty payload cwd sent the review off to the
# companion's own default directory.
[ -n "$target_dir" ] && args+=(--cwd "$target_dir")
[ -n "$base" ] && args+=(--base "$base")
args+=("$focus")

out=$(CODEX_COMPANION_SESSION_ID="$session_id" timeout 840 node "$companion" "${args[@]}" 2>/dev/null)
rc=$?
[ $rc -eq 124 ] && ask "Codex PR gate: review timed out after 14 minutes (check /codex:status). Proceed without a completed review?"
verdict=$(jq -r '.result.verdict // empty' <<<"$out" 2>/dev/null)
if [ $rc -ne 0 ] || [ -z "$verdict" ]; then
  ask "Codex PR gate: review failed to produce a verdict (exit ${rc}); is Codex set up (/codex:setup)? Proceed without the pre-publish review?"
fi

summary=$(jq -r '.result.summary // ""' <<<"$out")
if [ "$verdict" = "approve" ]; then
  note "Codex pre-publish review: APPROVE — ${summary}"
  exit 0
fi

findings=$(jq -r '[.result.findings[]? | "- [\(.severity)] \(.title) (\(.file):\(.line_start)) — \(.recommendation)"] | .[0:10] | join("\n")' <<<"$out")
deny "Codex pre-publish review: NEEDS-ATTENTION — refusing to ${context}.
Summary: ${summary}
${findings}
Fix the real issues and retry the command. If Cam explicitly approves shipping as-is, re-run it prefixed with CODEX_PR_GATE_SKIP=1."
