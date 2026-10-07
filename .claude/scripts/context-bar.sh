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
printf "%s" "$input" > "$HOME/.cache/context-bar/last-input.json" 2>/dev/null   # debug: last payload

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

# Shared colors (2026-10-06): every divider is the same dim " · "; each segment sets its own color.
C_DIM='\033[38;5;240m'
C_ALERT='\033[38;5;167m'
C_WARN='\033[38;5;178m'
sep="${C_DIM} · ${C_RESET}"
join() {   # join <segment>...  -> segments joined by $sep, empty ones skipped
    local out="" s
    for s in "$@"; do [[ -n "$s" ]] && out+="${out:+$sep}$s"; done
    printf '%s' "$out"
}
level_color() {   # level_color <pct>  -> accent under 60, gold to 85, red above
    if (( $1 >= 85 )); then printf '%s' "$C_ALERT"; elif (( $1 >= 60 )); then printf '%s' "$C_WARN"; else printf '%s' "$C_ACCENT"; fi
}
dur() {   # dur <minutes>  -> "45 min" / "4 h 25 min"
    local m=$1
    if (( m < 60 )); then printf '%d min' "$m"; elif (( m % 60 == 0 )); then printf '%d h' $((m / 60)); else printf '%d h %d min' $((m / 60)) $((m % 60)); fi
}

# Context: Claude Code's own used_percentage (2026-10-06; input + cache tokens of the last
# API response, the same sum the old transcript scan made). It is null before the first
# response and right after /compact; then show the ~20k baseline estimate (system prompt,
# tools, memory, env block) with a "~". The bar turns gold at 60%, red at 85%.
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty | floor')
pct_prefix=""
if [[ -z "$pct" ]]; then
    pct=$((20000 * 100 / max_context))
    pct_prefix="~"
fi
[[ $pct -gt 100 ]] && pct=100
C_BAR=$(level_color "$pct")
bar=""
for ((i=0; i<10; i++)); do
    progress=$((pct - i * 10))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_BAR}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_BAR}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done
ctx="${bar} ${C_GRAY}${pct_prefix}${pct}%${C_RESET}"

# Memory pressure (2026-10-06): ~10 sessions on a 16 GB Mac. Kernel level 1 = normal,
# 2 = warn, 4 = critical; shown only above normal.
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
    2) ram="${C_ALERT}🧠 RAM warn${C_RESET}" ;;
    4) ram="${C_ALERT}🧠 RAM critical${C_RESET}" ;;
    *) ram="" ;;
esac

# Prompt cache (2026-10-06): shown only in its last 15 minutes, then "cache cold" once it has
# expired - the next prompt re-sends the whole context uncached.
cache=""
IFS=$'\t' read -r c_exp c_req < <(echo "$input" | jq -r '[.prompt_cache.expires_at // "", .prompt_cache.requests // 0] | @tsv')
if [[ -n "$c_exp" && "${c_req:-0}" -gt 0 ]]; then
    c_left=$(( (${c_exp%.*} - $(date +%s)) / 60 ))
    if (( c_left < 0 )); then cache="${C_ALERT}cache cold${C_RESET}"
    elif (( c_left <= 15 )); then cache="${C_WARN}cache ${c_left} min${C_RESET}"; fi
fi

# Effort, color-coded (2026-10-06): low gray, medium accent, high gold, xhigh orange, max red.
case "$effort" in
    low)    C_EFF="$C_GRAY" ;;
    medium) C_EFF="$C_ACCENT" ;;
    high)   C_EFF="$C_WARN" ;;
    xhigh)  C_EFF='\033[38;5;208m' ;;
    max)    C_EFF="$C_ALERT" ;;
    *)      C_EFF="$C_GRAY" ;;
esac

# Layout (2026-10-06): each row is LEFT<TAB>RIGHT, right-aligned to $COLUMNS (Claude Code sets
# it for the script; tput cannot see the terminal) by statusline-align.py, which counts emoji
# as 2 cells and cuts the LEFT half first when a row does not fit.
#   row 1: model effort · dir · branch ±git · PR/CI          alerts · context bar · clock
#   row 2: Clio: 📋 Now / plan   else: 🎯 label · session    📥 · 🚩 · 👥 · 5h % · 7d %
pr=""
# PR + CI for a feature branch (no lookup on main/master): cached 2 min per repo+branch
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
    pr_key="pr-$(printf '%s' "$cwd@$branch" | md5 -q)"
    pr=$(cached "$pr_key" 120 pr_ci "$cwd")
fi
left1=$(join \
    "${C_ACCENT}${model}${effort:+ ${C_EFF}${effort}}${C_RESET}" \
    "${C_GRAY}${dir}${C_RESET}" \
    "${branch:+${C_GRAY}${branch}${git_status:+ ${C_WARN}${git_status}}${C_RESET}}" \
    "${pr:+${C_GRAY}${pr}${C_RESET}}")

outage=$(cached claude-status 300 claude_status)
right1=$(join \
    "${outage:+${C_ALERT}${outage}${C_RESET}}" \
    "$cache" \
    "$ram" \
    "$ctx" \
    "${C_GRAY}$(date '+%-I:%M %p')${C_RESET}")

# Session label: explicit $CLAUDE_TAB_LABEL (set by `cct "label"`); else, only when the session
# has no name (the prompt's divider already shows a /rename or registry name), the original
# task from the first user message (the command name if it was a slash command).
session_name=$(echo "$input" | jq -r '.session_name // empty')
session_label="$CLAUDE_TAB_LABEL"
if [[ -z "$session_label" && -z "$session_name" \
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

# Session stats (2026-10-06): wall time since the session started and lines changed this session, from the payload.
IFS=$'\t' read -r s_ms s_add s_del < <(echo "$input" | jq -r '[.cost.total_duration_ms // 0, .cost.total_lines_added // 0, .cost.total_lines_removed // 0] | @tsv')
s_min=$(( ${s_ms:-0} / 60000 ))
session_stats="${C_GRAY}session $(dur "$s_min")${C_RESET}"
(( ${s_add:-0} + ${s_del:-0} > 0 )) && session_stats+=" \033[38;5;71m+${s_add}${C_RESET} ${C_ALERT}-${s_del}${C_RESET}"

# Plan usage (2026-10-06): the 5-hour and 7-day rate-limit windows from the payload, colored
# by level; the 5-hour one names its reset time once it passes 60%.
limits=$(echo "$input" | jq -r '[.rate_limits.five_hour.used_percentage // "", .rate_limits.five_hour.resets_at // "", .rate_limits.seven_day.used_percentage // ""] | @tsv')
IFS=$'\t' read -r l5 l5_reset l7 <<< "$limits"
usage_bits=()
if [[ -n "$l5" ]]; then
    l5=${l5%.*}
    seg="$(level_color "$l5")5h ${l5}%"
    (( l5 >= 60 )) && [[ -n "$l5_reset" ]] && seg+=" ${C_GRAY}↻$(date -r "${l5_reset%.*}" '+%-I:%M %p')"
    usage_bits+=("${seg}${C_RESET}")
fi
[[ -n "$l7" ]] && { l7=${l7%.*}; usage_bits+=("$(level_color "$l7")7d ${l7}%${C_RESET}"); }

# Clio rows (2026-10-05): only in the Clio repo. Left: the conductor's day plan (lib/conductor.py
# writes footer.json every tick; shown while under 90 minutes old). Right: counts worth acting
# on - Inbox over 10 (the triage rule), open CAM flags, live peer sessions.
clio_bits=()
plan_line=""
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$repo_root" && -f "$repo_root/notebook/Inbox.md" ]]; then
    footer_json="$HOME/.clio/state/conductor/footer.json"
    if [[ -f "$footer_json" ]]; then
        plan_line=$(jq -r --arg cut "$(date -v-90M +%Y-%m-%dT%H:%M)" '
            def dur(m): if m < 60 then "\(m) min" elif m % 60 == 0 then "\(m / 60 | floor) h"
                        else "\(m / 60 | floor) h \(m % 60) min" end;
            select(.at >= $cut) |
            [(if .now then "Now: " + (.now | if length > 70 then .[0:68] + "…" else . end) else "Plan clear" end),
             "\(.done)/\(.planned) done",
             (if (.left_min // 0) > 0 then "\(dur(.left_min)) left" else empty end)] | join("\t")
        ' "$footer_json" 2>/dev/null)
    fi
    inbox_n=$(awk 'f && /^- /{c++} /^---$/{f=1} END{print c+0}' "$repo_root/notebook/Inbox.md" 2>/dev/null)
    [[ "${inbox_n:-0}" -gt 10 ]] && clio_bits+=("${C_ACCENT}📥 ${inbox_n}${C_RESET}")
    if [[ -f "$repo_root/queue/cam-flags.md" ]]; then
        flags_n=$(head -1 "$repo_root/queue/cam-flags.md" | sed -n 's/.*(open: \([0-9]*\)).*/\1/p')
        [[ "${flags_n:-0}" -gt 0 ]] && clio_bits+=("${C_ACCENT}🚩 ${flags_n}${C_RESET}")
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
    [[ "$peers_n" -gt 0 ]] && clio_bits+=("${C_ACCENT}👥 ${peers_n}${C_RESET}")
fi

# Row 2 left: the day plan in Clio; elsewhere (or with no live plan) the session's own label and stats.
if [[ -n "$plan_line" ]]; then
    IFS=$'\t' read -r -a plan_parts <<< "$plan_line"
    plan_segs=("${C_ACCENT}${plan_parts[0]}${C_RESET}")
    for p in "${plan_parts[@]:1}"; do plan_segs+=("${C_GRAY}${p}${C_RESET}"); done
    left2="${C_GRAY}📋 $(join "${plan_segs[@]}" "$session_stats")"
else
    left2=$(join "${session_label:+${C_GRAY}🎯 ${C_ACCENT}${session_label}${C_RESET}}" "$session_stats")
fi
right2=$(join "${clio_bits[@]}" "${usage_bits[@]}")

# Usable width: $COLUMNS less Claude Code's 2-cell indent and 2-cell right margin (measured: it
# cuts content past COLUMNS - 4 with an ellipsis), less 1 spare cell.
cols=$(( ${COLUMNS:-0} > 5 ? COLUMNS - 5 : 0 ))
PY=/opt/homebrew/bin/python3; [[ -x "$PY" ]] || PY=/usr/bin/python3   # not the pyenv shim: +80 ms a render
{
    printf '%b\t%b\n' "$left1" "$right1"
    [[ -n "$left2" || -n "$right2" ]] && printf '%b\t%b\n' "$left2" "$right2"
} | "$PY" -I "$HOME/.claude/scripts/statusline-align.py" "$cols"
