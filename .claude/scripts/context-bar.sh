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

# Get transcript path for the session-label fallback below
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Context: Claude Code's own used_percentage (2026-10-06; input + cache tokens of the last
# API response, the same sum the old transcript scan made). It is null before the first
# response and right after /compact; then show the ~20k baseline estimate (system prompt,
# tools, memory, env block) with a "~".
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty | floor')
pct_prefix=""
if [[ -z "$pct" ]]; then
    pct=$((20000 * 100 / max_context))
    pct_prefix="~"
fi
[[ $pct -gt 100 ]] && pct=100
bar=""
for ((i=0; i<10; i++)); do
    progress=$((pct - i * 10))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_ACCENT}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_ACCENT}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done
ctx="${bar} ${C_GRAY}${pct_prefix}${pct}%"

# Memory pressure (2026-10-06): ~10 sessions on a 16 GB Mac. Kernel level 1 = normal,
# 2 = warn, 4 = critical; shown only above normal.
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
    2) ram="🧠 RAM warn" ;;
    4) ram="🧠 RAM critical" ;;
    *) ram="" ;;
esac

# Layout (2026-10-06): each row is LEFT<TAB>RIGHT, right-aligned to $COLUMNS (Claude Code sets
# it for the script; tput cannot see the terminal) by statusline-align.py, which counts emoji
# as 2 cells and cuts the LEFT half first when a row does not fit.
#   row 1: model effort · dir · branch ±git · PR/CI          alerts · context bar · clock
#   row 2: 📋 Now / plan                                      📥 · 🚩 · 👥 · 🎯 label
sep="${C_GRAY} · "
left1="${C_ACCENT}${model}${effort:+ ${C_GRAY}${effort}}${sep}${dir}"
[[ -n "$branch" ]] && left1+="${sep}${branch}${git_status:+ ${git_status}}"
# PR + CI for a feature branch (no lookup on main/master): cached 2 min per repo+branch
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
    pr_key="pr-$(printf '%s' "$cwd@$branch" | md5 -q)"
    pr=$(cached "$pr_key" 120 pr_ci "$cwd")
    [[ -n "$pr" ]] && left1+="${sep}${pr}"
fi
left1+="${C_RESET}"

C_ALERT='\033[38;5;167m'
right1=""
outage=$(cached claude-status 300 claude_status)
[[ -n "$outage" ]] && right1+="${C_ALERT}${outage}${sep}"
[[ -n "$ram" ]] && right1+="${C_ALERT}${ram}${sep}"
right1+="${ctx}${sep}$(date '+%-I:%M %p')${C_RESET}"

# Session label: explicit $CLAUDE_TAB_LABEL (set by `cct "label"`); else, only when the session
# has no name (the prompt's divider already shows a /rename or registry name), the original
# task from the first user message (the command name if it was a slash command).
session_label="$CLAUDE_TAB_LABEL"
if [[ -z "$session_label" && -z "$(echo "$input" | jq -r '.session_name // empty')" \
      && -n "$transcript_path" && -f "$transcript_path" ]]; then
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
[[ ${#session_label} -gt 40 ]] && session_label="${session_label:0:37}..."

# Day plan from the Clio conductor (2026-10-04): lib/conductor.py writes footer.json on
# every tick; shown only while it is under 90 minutes old, so a stopped conductor drops out.
# The Now title gets up to 80 chars; the aligner cuts it further on a narrow window.
footer_json="$HOME/.clio/state/conductor/footer.json"
if [[ -f "$footer_json" ]]; then
    plan_line=$(jq -r --arg cut "$(date -v-90M +%Y-%m-%dT%H:%M)" '
        def dur(m): if m < 60 then "\(m) min" elif m % 60 == 0 then "\(m / 60 | floor) h"
                    else "\(m / 60 | floor) h \(m % 60) min" end;
        select(.at >= $cut) |
        (if .now then "Now: " + (.now | if length > 80 then .[0:78] + "…" else . end) else "Plan clear" end)
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
    [[ "${inbox_n:-0}" -gt 10 ]] && clio_bits+="${sep}📥 ${inbox_n}"
    if [[ -f "$repo_root/queue/cam-flags.md" ]]; then
        flags_n=$(head -1 "$repo_root/queue/cam-flags.md" | sed -n 's/.*(open: \([0-9]*\)).*/\1/p')
        [[ "${flags_n:-0}" -gt 0 ]] && clio_bits+="${sep}🚩 ${flags_n}"
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
    [[ "$peers_n" -gt 0 ]] && clio_bits+="${sep}👥 ${peers_n}"
fi
right2="${clio_bits}"
[[ -n "$session_label" ]] && right2+="${sep}🎯 ${C_ACCENT}${session_label}"
right2="${right2#"${sep}"}"
[[ -n "$right2" ]] && right2="${C_ACCENT}${right2}${C_RESET}"
left2=""
[[ -n "$plan_line" ]] && left2="${C_GRAY}📋 ${C_ACCENT}${plan_line}${C_RESET}"

# Usable width: $COLUMNS less Claude Code's 2-cell indent and 2-cell right margin (measured: it
# cuts content past COLUMNS - 4 with an ellipsis), less 1 spare cell.
cols=$(( ${COLUMNS:-0} > 5 ? COLUMNS - 5 : 0 ))
PY=/opt/homebrew/bin/python3; [[ -x "$PY" ]] || PY=/usr/bin/python3   # not the pyenv shim: +80 ms a render
{
    printf '%b\t%b\n' "$left1" "$right1"
    [[ -n "$left2" || -n "$right2" ]] && printf '%b\t%b\n' "$left2" "$right2"
} | "$PY" -I "$HOME/.claude/scripts/statusline-align.py" "$cols"
