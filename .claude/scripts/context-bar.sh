#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;242m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
effort=$(echo "$input" | jq -r '.effort.level // empty')   # live, follows /effort (2026-10-06)

# Slow lookups (gh, status.claude.com) never run inline: the footer reads a cache file and,
# when it is older than its TTL, refreshes it in a detached background job. ~10 tabs share
# one cache per key, and a .lock file keeps them from refreshing it all at once.
CACHE_DIR="$HOME/.cache/context-bar"
mkdir -p "$CACHE_DIR" 2>/dev/null
cached() {   # cached <key> <ttl-seconds> <command...>  -> prints the cached output (may be stale)
    local key="$1" ttl="$2"; shift 2
    local f="$CACHE_DIR/$key" lock="$CACHE_DIR/$key.lock" now age
    now=$(date +%s)
    age=$(( now - $(stat -f %m "$f" 2>/dev/null || echo 0) ))
    if (( age > ttl )) && ! [[ -f "$lock" && $(( now - $(stat -f %m "$lock" 2>/dev/null || echo 0) )) -lt 60 ]]; then
        touch "$lock"
        ( "$@" > "$f.tmp" 2>/dev/null; mv -f "$f.tmp" "$f"; rm -f "$lock" ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null
    fi
    cat "$f" 2>/dev/null
}
pr_ci() {    # "#N ✓" / "#N ✗2" / "#N ●" for the branch's open PR; empty when none
    cd "$1" && gh pr view --json number,state,isDraft,statusCheckRollup --jq '
        select(.state == "OPEN") |
        [.statusCheckRollup[] | (.conclusion // .state // "") | ascii_upcase] as $c |
        ($c | map(select(. == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT" or . == "ACTION_REQUIRED")) | length) as $bad |
        ($c | map(select(. == "" or . == "PENDING" or . == "EXPECTED" or . == "IN_PROGRESS" or . == "QUEUED")) | length) as $wait |
        "#\(.number)" + (if .isDraft then " draft" else "" end)
        + (if $bad > 0 then " ✗\($bad)" elif $wait > 0 then " ●" elif ($c | length) > 0 then " ✓" else "" end)'
}
claude_status() {   # status.claude.com: prints nothing while operational
    curl -s --max-time 3 https://status.claude.com/api/v2/status.json \
        | jq -r 'select(.status.indicator != "none") | "🔴 Claude: \(.status.description)"'
}
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uno 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Compact git status (2026-10-05): ±uncommitted ↑ahead ↓behind, nothing when clean and synced
        git_status=""
        [[ "$file_count" -gt 0 ]] && git_status="±${file_count}"
        [[ -n "$upstream" && "${ahead:-0}" -gt 0 ]] && git_status+="${git_status:+ }↑${ahead}"
        [[ -n "$upstream" && "${behind:-0}" -gt 0 ]] && git_status+="${git_status:+ }↓${behind}"
        [[ -z "$upstream" ]] && git_status+="${git_status:+ }no upstream"
    fi
fi

# Get transcript path for context calculation and last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Get context window size from JSON (accurate), but calculate tokens from transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory)
# See: github.com/anthropics/claude-code/issues/13652
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))
if [[ $max_k -ge 1000 ]]; then
    max_display="$((max_k / 1000))M"
else
    max_display="${max_k}k"
fi

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}${pct_prefix}${pct}%"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}%"
fi

# Build output: Model | Dir | Branch (uncommitted) | Context
output="${C_ACCENT}${model}${effort:+ ${C_GRAY}${effort}}${C_GRAY} · ${dir}"
[[ -n "$branch" ]] && output+=" · ${branch}${git_status:+ ${git_status}}"
# PR + CI for a feature branch (no lookup on main/master): cached 2 min per repo+branch
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
    pr_key="pr-$(printf '%s' "$cwd@$branch" | md5 -q)"
    pr=$(cached "$pr_key" 120 pr_ci "$cwd")
    [[ -n "$pr" ]] && output+=" · ${pr}"
fi
output+=" · ${ctx}${C_RESET}"
outage=$(cached claude-status 300 claude_status)
[[ -n "$outage" ]] && output+=" ${C_ACCENT}·${C_RESET} \033[38;5;167m${outage}${C_RESET}"


# Session label: explicit $CLAUDE_TAB_LABEL (set by `cct "label"`), else the session
# name Claude Code carries (`/rename`, `--name`, or the Clio session-registry hook's
# first-prompt slug - 2026-09-12), else best-effort original task from the first
# user message (command name if it was a slash command).
session_label="$CLAUDE_TAB_LABEL"
[[ -z "$session_label" ]] && session_label=$(echo "$input" | jq -r '.session_name // empty')
if [[ -z "$session_label" && -n "$transcript_path" && -f "$transcript_path" ]]; then
    first_msg=$(jq -rs '
        def is_unhelpful: startswith("[Request interrupted") or startswith("[Request cancelled") or . == "";
        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or (type == "array" and any(.[]; .type == "text")))] |
        map(.message.content |
            if type == "string" then . else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("(?s)<system-reminder>.*?</system-reminder>"; "") |
            gsub("(?s)<command-[a-z-]+>.*?</command-[a-z-]+>"; "") |
            gsub("\n"; " ") | gsub("\\s\\s+"; " ") | sub("^ +"; "")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)
    if [[ "$first_msg" =~ ^#?[[:space:]]*/([a-zA-Z][a-zA-Z0-9-]*) ]]; then
        session_label="/${BASH_REMATCH[1]}"
    else
        session_label="$first_msg"
    fi
fi
if [[ -n "$session_label" ]]; then
    [[ ${#session_label} -gt 40 ]] && session_label="${session_label:0:37}..."
    output+="${C_GRAY} · 🎯 ${C_ACCENT}${session_label}${C_RESET}"
fi
printf '%b\n' "$output"

# Day plan from the Clio conductor (2026-10-04): lib/conductor.py writes footer.json on
# every tick; shown only while it is under 90 minutes old, so a stopped conductor drops out.
footer_json="$HOME/.clio/state/conductor/footer.json"
if [[ -f "$footer_json" ]]; then
    plan_line=$(jq -r --arg cut "$(date -v-90M +%Y-%m-%dT%H:%M)" '
        def dur(m): if m < 60 then "\(m) min" elif m % 60 == 0 then "\(m / 60 | floor) h"
                    else "\(m / 60 | floor) h \(m % 60) min" end;
        select(.at >= $cut) |
        (if .now then "Now: " + (.now | if length > 40 then .[0:38] + "…" else . end) else "Plan clear" end)
        + " \(.done)/\(.planned)"
        + (if (.left_min // 0) > 0 then " · \(dur(.left_min))" else "" end)
    ' "$footer_json" 2>/dev/null)
fi

# Clio counts (2026-10-05, replacing the clio-state-band mod): only in the Clio repo, and only
# a count worth acting on - Inbox over 10 (the triage rule), open CAM flags, live peer sessions.
clio_bits=""
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$repo_root" && -f "$repo_root/notebook/Inbox.md" ]]; then
    inbox_n=$(awk 'f && /^- /{c++} /^---$/{f=1} END{print c+0}' "$repo_root/notebook/Inbox.md" 2>/dev/null)
    [[ "${inbox_n:-0}" -gt 10 ]] && clio_bits+=" · 📥 ${inbox_n}"
    if [[ -f "$repo_root/queue/cam-flags.md" ]]; then
        flags_n=$(head -1 "$repo_root/queue/cam-flags.md" | sed -n 's/.*(open: \([0-9]*\)).*/\1/p')
        [[ "${flags_n:-0}" -gt 0 ]] && clio_bits+=" · 🚩 ${flags_n}"
    fi
    own_sid=$(echo "$input" | jq -r '.session_id // empty')
    peers_n=0
    for f in "$HOME"/.clio/state/sessions/*.json; do
        [[ -e "$f" ]] || continue
        IFS=$'\t' read -r p_sid p_pid p_cwd < <(jq -r '[.session_id // "", .pid // "", .cwd // ""] | @tsv' "$f" 2>/dev/null)
        [[ -z "$p_pid" || "$p_sid" == "$own_sid" || "$p_cwd" != "$repo_root" ]] && continue
        reg="$HOME/.claude/sessions/${p_pid}.json"
        [[ -f "$reg" ]] && [[ $(jq -r --arg s "$p_sid" 'if .sessionId == $s and .kind == "interactive" then 1 else 0 end' "$reg" 2>/dev/null) == 1 ]] \
            && peers_n=$((peers_n + 1))
    done
    [[ "$peers_n" -gt 0 ]] && clio_bits+=" · 👥 ${peers_n}"
fi
if [[ -n "$plan_line" || -n "$clio_bits" ]]; then
    line2="${plan_line:-}${clio_bits}"
    line2="${line2# · }"
    printf '%b\n' "${C_GRAY}📋 ${C_ACCENT}${line2}${C_RESET}"
fi
