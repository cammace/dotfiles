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

        # Compact git status (2026-10-05): +/-uncommitted lines ↑ahead ↓behind, nothing when clean and synced
        # Uncommitted lines vs HEAD (2026-10-06): green +added, red -removed; untracked files not counted
        git_status=""
        if [[ "$file_count" -gt 0 ]]; then
            read -r d_add d_del < <(git -C "$cwd" --no-optional-locks diff --numstat HEAD 2>/dev/null | awk '{a+=$1; d+=$2} END{print a+0, d+0}')
            git_status="\033[38;5;71m+${d_add}\033[0m \033[38;5;167m-${d_del}\033[0m"
        fi
        [[ -n "$upstream" && "${ahead:-0}" -gt 0 ]] && git_status+="${git_status:+ }${C_GRAY}↑${ahead}"
        [[ -n "$upstream" && "${behind:-0}" -gt 0 ]] && git_status+="${git_status:+ }${C_GRAY}↓${behind}"
        [[ -z "$upstream" ]] && git_status+="${git_status:+ }${C_GRAY}no upstream"
    fi
fi


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

meter() {   # meter <pct> <cells> <color>  -> full/half blocks, empty cells dim
    local pct=$1 n=$2 c=$3 out="" i step=$((100 / $2)) progress
    for ((i=0; i<n; i++)); do
        progress=$((pct - i * step))
        if (( progress * 10 >= step * 8 )); then out+="${c}█"
        elif (( progress * 10 >= step * 3 )); then out+="${c}▄"
        else out+="${C_BAR_EMPTY}░"; fi
    done
    printf '%s' "${out}${C_RESET}"
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
bar=$(meter "$pct" 8 "$C_BAR")
ctx="${bar} ${C_GRAY}${pct_prefix}${pct}%${C_RESET}"

# Memory pressure (2026-10-06): ~10 sessions on a 16 GB Mac. Kernel level 1 = normal,
# 2 = warn, 4 = critical; shown only above normal, as swap used/total, the used figure colored by
# how full swap is (accent under 60%, gold to 85%, red above).
ram=""
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
    2) ram_lvl="warn" ;;
    4) ram_lvl="critical" ;;
    *) ram_lvl="" ;;
esac
if [[ -n "$ram_lvl" ]]; then
    read -r sw_used sw_total sw_pct < <(sysctl -n vm.swapusage 2>/dev/null | awk '{u=$6; t=$3; sub(/M/,"",u); sub(/M/,"",t); printf "%.1f %.0f %d\n", u/1024, t/1024, (t > 0 ? u*100/t : 0)}')
    C_SW=$(level_color "${sw_pct:-0}")
    [[ "$ram_lvl" == "critical" ]] && C_LBL="$C_ALERT" || C_LBL="$C_WARN"
    # e.g. "🧠 swap 9.0/10G": label colored by kernel pressure, used figure by swap fill
    ram="${C_LBL}🧠 swap ${C_SW}${sw_used}${C_GRAY}/${sw_total}G${C_RESET}"
fi

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

# Layout (2026-10-06, one row): LEFT<TAB>RIGHT, right-aligned to $COLUMNS (Claude Code sets it
# for the script; tput cannot see the terminal) by statusline-align.py, which counts emoji as
# 2 cells and cuts the LEFT half first, so the plan at its end is what shrinks on a narrow tab.
#   model effort · dir · branch +/- ↑↓ · PR/CI · 📋 Now (Clio)    alerts · 🚩 · limits · context · clock
# Every right-side item shows only when it needs action.
pr=""
# PR + CI for a feature branch (no lookup on main/master): cached 2 min per repo+branch
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
    pr_key="pr-$(printf '%s' "$cwd@$branch" | md5 -q)"
    pr=$(cached "$pr_key" 120 pr_ci "$cwd")
fi

# Clio only: the conductor's current task (lib/conductor.py writes footer.json every tick; shown
# while under 90 minutes old) with how many plan items follow it, and open CAM flags.
plan="" flags=""
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$repo_root" && -f "$repo_root/notebook/Inbox.md" ]]; then
    footer_json="$HOME/.clio/state/conductor/footer.json"
    [[ -f "$footer_json" ]] && plan=$(jq -r --arg cut "$(date -v-90M +%Y-%m-%dT%H:%M)" '
        select(.at >= $cut and .now) |
        ((.planned // 0) - (.done // 0) - 1) as $more |
        "📋 " + (.now | if length > 48 then .[0:46] + "…" else . end) + (if $more > 0 then " (+\($more))" else "" end)
    ' "$footer_json" 2>/dev/null)
    if [[ -f "$repo_root/queue/cam-flags.md" ]]; then
        flags_n=$(head -1 "$repo_root/queue/cam-flags.md" | sed -n 's/.*(open: \([0-9]*\)).*/\1/p')
        [[ "${flags_n:-0}" -gt 0 ]] && flags="${C_WARN}🚩 ${flags_n}${C_RESET}"
    fi
fi

# Plan usage: the 5-hour window from 60%, the 7-day from 80%, with the 5-hour reset time.
limits=$(echo "$input" | jq -r '[.rate_limits.five_hour.used_percentage // "", .rate_limits.five_hour.resets_at // "", .rate_limits.seven_day.used_percentage // ""] | @tsv')
IFS=$'\t' read -r l5 l5_reset l7 <<< "$limits"
usage=""
l5=${l5%.*}; l7=${l7%.*}
if [[ -n "$l5" ]] && (( l5 >= 60 )); then
    usage="$(level_color "$l5")5h ${l5}%${l5_reset:+ ${C_GRAY}↻$(date -r "${l5_reset%.*}" '+%-I:%M %p')}${C_RESET}"
fi
[[ -n "$l7" ]] && (( l7 >= 80 )) && usage=$(join "$usage" "$(level_color "$l7")7d ${l7}%${C_RESET}")

left=$(join \
    "${C_ACCENT}${model}${effort:+ ${C_EFF}${effort}}${C_RESET}" \
    "${C_GRAY}${dir}${C_RESET}" \
    "${branch:+${C_GRAY}${branch}${git_status:+ ${git_status}}${C_RESET}}" \
    "${pr:+${C_GRAY}${pr}${C_RESET}}" \
    "${plan:+${C_ACCENT}${plan}${C_RESET}}")

outage=$(cached claude-status 300 claude_status)
right=$(join \
    "${outage:+${C_ALERT}${outage}${C_RESET}}" \
    "$ram" \
    "$cache" \
    "$flags" \
    "$usage" \
    "$ctx" \
    "${C_GRAY}$(date '+%-I:%M %p')${C_RESET}")

# Usable width: $COLUMNS less Claude Code's 2-cell indent and 2-cell right margin (measured: it
# cuts content past COLUMNS - 4 with an ellipsis), less 1 spare cell.
cols=$(( ${COLUMNS:-0} > 5 ? COLUMNS - 5 : 0 ))
PY=/opt/homebrew/bin/python3; [[ -x "$PY" ]] || PY=/usr/bin/python3   # not the pyenv shim: +80 ms a render
printf '%b\t%b\n' "$left" "$right" | "$PY" -I "$HOME/.claude/scripts/statusline-align.py" "$cols"
