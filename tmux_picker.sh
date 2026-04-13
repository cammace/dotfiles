#!/bin/bash

# ╭────────────────────────────────────────────────────────╮
# │ tmux_picker.sh — polished TUI session manager          │
# │ Works on Termius (iPhone) and iTerm2 (Mac)             │
# ╰────────────────────────────────────────────────────────╯

# ==========================================================
# Section 1: Environment Detection
# ==========================================================

IN_TMUX=false
[[ -n "$TMUX" ]] && IN_TMUX=true

COLS=$(tput cols 2>/dev/null) || COLS=80
LINES=$(tput lines 2>/dev/null) || LINES=24
WIDE_MODE=false
(( COLS >= 80 )) && WIDE_MODE=true

BOLD=$(tput bold 2>/dev/null) || BOLD=''
RESET=$(tput sgr0 2>/dev/null) || RESET=$'\033[0m'
DIM=$'\033[2m'

# Truecolor vs 256-color detection
if [[ "$COLORTERM" == "truecolor" || "$COLORTERM" == "24bit" ]]; then
    TC=true
    # Nord palette — foreground colors
    C_BORDER=$'\033[38;2;76;86;106m'       # Nord3 muted
    C_TEXT=$'\033[38;2;216;222;233m'        # Nord4 snow
    C_ACCENT=$'\033[38;2;136;192;208m'     # Nord8 frost
    C_BLUE=$'\033[38;2;129;161;193m'       # Nord9
    C_RED=$'\033[38;2;191;97;106m'         # Nord11
    C_YELLOW=$'\033[38;2;235;203;139m'     # Nord13
    C_GREEN=$'\033[38;2;163;190;140m'      # Nord14
    C_PURPLE=$'\033[38;2;180;142;173m'     # Nord15
    C_DIM=$'\033[38;2;76;86;106m'          # Nord3
    # Background for highlight
    BG_HIGHLIGHT=$'\033[48;2;59;66;82m'
    BG_KILL=$'\033[48;2;76;46;50m'
else
    TC=false
    C_BORDER=$'\033[38;5;60m'
    C_TEXT=$'\033[38;5;188m'
    C_ACCENT=$'\033[38;5;110m'
    C_BLUE=$'\033[38;5;67m'
    C_RED=$'\033[38;5;131m'
    C_YELLOW=$'\033[38;5;179m'
    C_GREEN=$'\033[38;5;108m'
    C_PURPLE=$'\033[38;5;139m'
    C_DIM=$'\033[38;5;60m'
    BG_HIGHLIGHT=$'\033[48;5;238m'
    BG_KILL=$'\033[48;5;52m'
fi

# Unicode vs ASCII icon detection
if locale charmap 2>/dev/null | grep -qi utf; then
    HAS_UNICODE=true
else
    # Fallback check
    case "$LANG$LC_ALL$LC_CTYPE" in
        *UTF-8*|*utf-8*|*utf8*) HAS_UNICODE=true ;;
        *) HAS_UNICODE=false ;;
    esac
fi

if $HAS_UNICODE; then
    ICON_ATTACHED="●"
    ICON_DETACHED="○"
    ICON_CURSOR="›"
    ICON_KILL="✗"
    ICON_CHECK="✓"
    ICON_CLAUDE="●"
    BOX_TL="╭" BOX_TR="╮" BOX_BL="╰" BOX_BR="╯"
    BOX_H="─" BOX_V="│" BOX_ML="├" BOX_MR="┤"
else
    ICON_ATTACHED="*"
    ICON_DETACHED="-"
    ICON_CURSOR=">"
    ICON_KILL="x"
    ICON_CHECK="+"
    ICON_CLAUDE="*"
    BOX_TL="+" BOX_TR="+" BOX_BL="+" BOX_BR="+"
    BOX_H="-" BOX_V="|" BOX_ML="+" BOX_MR="+"
fi

# ==========================================================
# Section 2: State Variables
# ==========================================================

CURSOR_POS=0           # 0 = Claude row, 1+ = sessions
MODE="normal"          # normal | kill
SORT_MODE="activity"   # activity | name
STATUS_MSG=""
STATUS_EXPIRE=0

# Session data arrays
SESSION_NAMES=()
SESSION_WINDOWS=()
SESSION_STATUSES=()
SESSION_ACTIVITIES=()
SESSION_CMDS=()
SESSION_PATHS=()
SESSION_KEYS=()
SESSION_COUNT=0
TOTAL_COUNT=0          # including Claude row

# Kill mode selections (indexed array, KILL_SELECTED[idx]=1)
KILL_SELECTED=()

# Window preview cache (parallel arrays for bash 3.2 compat)
WCACHE_NAMES=()
WCACHE_VALUES=()

# ==========================================================
# Section 3: Utilities
# ==========================================================

human_age() {
    local diff=$1
    if (( diff < 60 )); then echo "${diff}s"
    elif (( diff < 3600 )); then echo "$(( diff / 60 ))m"
    elif (( diff < 86400 )); then echo "$(( diff / 3600 ))h"
    else echo "$(( diff / 86400 ))d"
    fi
}

truncate_path() {
    local path="${1/#$HOME/\~}"
    local max=$2
    if [[ ${#path} -gt $max ]]; then
        echo "..${path: -$(( max - 2 ))}"
    else
        echo "$path"
    fi
}

# Fit string to exact width (pad or truncate)
fit_string() {
    local str="$1" width=$2
    local visible_len=${#str}
    if (( visible_len > width )); then
        echo "${str:0:$width}"
    else
        printf "%-${width}s" "$str"
    fi
}

# Calculate visible length (strips ANSI escapes, pure-bash, no subshell)
_ESC=$'\033'
visible_len() {
    local str="$1" prefix after rest
    while [[ "$str" == *${_ESC}\[* ]]; do
        prefix="${str%%${_ESC}\[*}"
        rest="${str#*${_ESC}\[}"
        after="${rest#*m}"
        str="${prefix}${after}"
    done
    REPLY=${#str}
}

set_status() {
    STATUS_MSG="$1"
    STATUS_EXPIRE=$(( $(date +%s) + 3 ))
}

# ==========================================================
# Section 4: Tmux Interface
# ==========================================================

attach_or_switch() {
    local target="$1"
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
    if $IN_TMUX; then
        exec tmux switch-client -t "$target"
    else
        exec tmux attach-session -t "$target"
    fi
}

new_session() {
    local name="$1"
    if $IN_TMUX; then
        if [[ -n "$name" ]]; then
            if ! tmux new-session -d -s "$name" 2>/dev/null; then
                set_status "Session '$name' already exists"
                return 1
            fi
            tput cnorm 2>/dev/null
            tput rmcup 2>/dev/null
            exec tmux switch-client -t "$name"
        else
            local created
            created=$(tmux new-session -d -P -F '#{session_name}')
            tput cnorm 2>/dev/null
            tput rmcup 2>/dev/null
            exec tmux switch-client -t "$created"
        fi
    else
        tput cnorm 2>/dev/null
        tput rmcup 2>/dev/null
        if [[ -n "$name" ]]; then
            exec tmux new-session -s "$name"
        else
            exec tmux new-session
        fi
    fi
}

kill_sessions() {
    local killed=0
    local names=()
    local i
    for (( i=0; i<SESSION_COUNT; i++ )); do
        if [[ "${KILL_SELECTED[$i]}" == "1" ]]; then
            local target="${SESSION_KEYS[$i]}"
            tmux kill-session -t "$target" 2>/dev/null && (( killed++ ))
            names+=("$target")
        fi
    done
    KILL_SELECTED=()
    if (( killed > 0 )); then
        if (( killed == 1 )); then
            set_status "Killed '${names[0]}'"
        else
            set_status "Killed $killed sessions"
        fi
    fi
    refresh_data
}

rename_session() {
    local idx=$(( CURSOR_POS - 1 ))
    if (( idx < 0 || idx >= SESSION_COUNT )); then
        return
    fi
    local old_name="${SESSION_KEYS[$idx]}"

    # Show inline rename prompt
    tput cnorm 2>/dev/null
    local prompt_row=$(( CURSOR_POS + 3 ))
    $WIDE_MODE && (( prompt_row += 1 ))
    tput cup "$prompt_row" 2 2>/dev/null
    printf "${C_ACCENT}rename:${RESET} "
    local new_name=""
    while true; do
        read -rsn1 ch
        case "$ch" in
            $'\x7f'|$'\b')  # Backspace
                if [[ -n "$new_name" ]]; then
                    new_name="${new_name%?}"
                    printf "\b \b"
                fi
                ;;
            ""|$'\n')  # Enter
                break
                ;;
            $'\x1b')  # Escape — cancel
                tput civis 2>/dev/null
                return
                ;;
            *)
                new_name+="$ch"
                printf "%s" "$ch"
                ;;
        esac
    done
    tput civis 2>/dev/null

    if [[ -z "$new_name" ]]; then
        return
    fi

    # Check for duplicate
    if tmux has-session -t "$new_name" 2>/dev/null; then
        set_status "Session '$new_name' already exists"
        return
    fi

    tmux rename-session -t "$old_name" "$new_name" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        set_status "Renamed '$old_name' -> '$new_name'"
    else
        set_status "Rename failed"
    fi
    refresh_data
}

claude_session_exists() {
    tmux has-session -t claude 2>/dev/null
}

attach_claude() {
    if claude_session_exists; then
        attach_or_switch "claude"
    else
        tput cnorm 2>/dev/null
        tput rmcup 2>/dev/null
        if $IN_TMUX; then
            tmux new-session -d -s claude 'claude'
            exec tmux switch-client -t claude
        else
            exec tmux new-session -A -s claude 'claude'
        fi
    fi
}

get_session_windows() {
    local session="$1"
    # Check cache (parallel arrays for bash 3.2 compat)
    local i
    for (( i=0; i<${#WCACHE_NAMES[@]}; i++ )); do
        if [[ "${WCACHE_NAMES[$i]}" == "$session" ]]; then
            echo "${WCACHE_VALUES[$i]}"
            return
        fi
    done
    local result
    result=$(tmux list-windows -t "$session" -F '#{window_index}:#{window_name}' 2>/dev/null | tr '\n' ' ')
    result="${result% }"
    WCACHE_NAMES+=("$session")
    WCACHE_VALUES+=("$result")
    echo "$result"
}

# ==========================================================
# Section 5: Data
# ==========================================================

build_session_list() {
    SESSION_NAMES=()
    SESSION_WINDOWS=()
    SESSION_STATUSES=()
    SESSION_ACTIVITIES=()
    SESSION_CMDS=()
    SESSION_PATHS=()
    SESSION_KEYS=()
    WCACHE_NAMES=()
    WCACHE_VALUES=()

    local now
    now=$(date +%s)
    local sort_cmd

    if [[ "$SORT_MODE" == "name" ]]; then
        sort_cmd="sort -t'|' -k1"
    else
        sort_cmd="sort -t'|' -k4 -rn"
    fi

    while IFS='|' read -r name windows status activity pane_cmd pane_path; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "claude" ]] && continue

        SESSION_NAMES+=("$name")
        SESSION_WINDOWS+=("$windows")
        SESSION_STATUSES+=("$status")
        SESSION_ACTIVITIES+=("$activity")
        SESSION_CMDS+=("$pane_cmd")
        SESSION_PATHS+=("$pane_path")
        SESSION_KEYS+=("$name")
    done < <(tmux ls -F '#{session_name}|#{session_windows}|#{?session_attached,attached,detached}|#{session_activity}|#{pane_current_command}|#{pane_current_path}' 2>/dev/null | eval "$sort_cmd")

    SESSION_COUNT=${#SESSION_NAMES[@]}
    TOTAL_COUNT=$(( SESSION_COUNT + 1 ))  # +1 for Claude row
}

refresh_data() {
    build_session_list
    # Clamp cursor
    if (( CURSOR_POS >= TOTAL_COUNT )); then
        CURSOR_POS=$(( TOTAL_COUNT - 1 ))
    fi
    (( CURSOR_POS < 0 )) && CURSOR_POS=0
}

# ==========================================================
# Section 6: Rendering
# ==========================================================

# Pad a line to full terminal width and print
print_padded() {
    local content="$1"
    visible_len "$content"
    local padding=$(( COLS - REPLY ))
    (( padding < 0 )) && padding=0
    printf "%b%*s\n" "$content" "$padding" ""
}

# Print a line with optional background highlight
print_row() {
    local content="$1"
    local bg="$2"
    if [[ -n "$bg" ]]; then
        visible_len "$content"
        local padding=$(( COLS - REPLY ))
        (( padding < 0 )) && padding=0
        printf "%b%b%*s%b\n" "$bg" "$content" "$padding" "" "$RESET"
    else
        print_padded "$content"
    fi
}

render_header() {
    local label="SESSIONS"
    local count_label
    if (( SESSION_COUNT == 0 )); then
        count_label="no sessions"
    elif (( SESSION_COUNT == 1 )); then
        count_label="1 session"
    else
        count_label="${SESSION_COUNT} sessions"
    fi

    if $WIDE_MODE; then
        # Box top border
        local inner=$(( COLS - 4 ))
        (( inner < 20 )) && inner=20
        local label_len=${#label}
        local count_len=${#count_label}
        local fill=$(( inner - label_len - count_len - 4 ))
        (( fill < 1 )) && fill=1
        local border_fill=""
        for (( i=0; i<fill; i++ )); do border_fill+="$BOX_H"; done

        print_padded "  ${C_BORDER}${BOX_TL}${BOX_H} ${C_ACCENT}${BOLD}${label}${RESET}${C_BORDER} ${border_fill} ${C_DIM}${count_label} ${C_BORDER}${BOX_H}${BOX_TR}${RESET}"
        print_padded "  ${C_BORDER}${BOX_V}$(printf "%*s" "$inner" "")${BOX_V}${RESET}"
    else
        # Narrow divider
        local fill=$(( COLS - ${#label} - ${#count_label} - 8 ))
        (( fill < 2 )) && fill=2
        local divider=""
        for (( i=0; i<fill; i++ )); do divider+="$BOX_H"; done
        print_padded "  ${C_BORDER}${BOX_H}${BOX_H} ${C_ACCENT}${BOLD}${label}${RESET} ${C_BORDER}${divider} ${C_DIM}${count_label}${RESET}"
    fi
}

render_claude_row() {
    local is_selected=$(( CURSOR_POS == 0 ))
    local bg=""
    local cursor=" "

    if [[ "$MODE" == "kill" ]]; then
        # Claude row not killable, just dim it
        if $WIDE_MODE; then
            print_padded "  ${C_BORDER}${BOX_V}${RESET}  ${C_DIM}c  ${ICON_CLAUDE} Claude Code${RESET}$(printf "%*s" $(( COLS - 24 )) "")${C_BORDER}${BOX_V}${RESET}"
        else
            print_padded "  ${C_DIM}c  ${ICON_CLAUDE} Claude Code${RESET}"
        fi
        return
    fi

    if (( is_selected )); then
        bg="$BG_HIGHLIGHT"
        cursor="${C_ACCENT}${ICON_CURSOR}${RESET}"
    fi

    local exists_label
    if claude_session_exists; then
        exists_label="${C_GREEN}attached${RESET}"
    else
        exists_label="${C_DIM}new${RESET}"
    fi

    if $WIDE_MODE; then
        local inner=$(( COLS - 4 ))
        local row_content="  ${C_ACCENT}${BOLD}c${RESET}  ${C_PURPLE}${ICON_CLAUDE} Claude Code${RESET}"
        # Right-align the status
        visible_len "$row_content"; local left_vis=$REPLY
        visible_len "$exists_label"; local right_vis=$REPLY
        local mid_pad=$(( inner - left_vis - right_vis + 2 ))
        (( mid_pad < 1 )) && mid_pad=1

        local full_row="  ${C_BORDER}${BOX_V}${RESET} ${cursor}${row_content}$(printf "%*s" "$mid_pad" "")${exists_label} ${C_BORDER}${BOX_V}${RESET}"
        print_row "$full_row" "$bg"
    else
        local row_content="  ${cursor} ${C_ACCENT}${BOLD}c${RESET}  ${C_PURPLE}${ICON_CLAUDE} Claude Code${RESET}     ${exists_label}"
        print_row "$row_content" "$bg"
    fi
}

render_session_row() {
    local idx=$1  # index into SESSION_* arrays
    local list_pos=$(( idx + 1 ))  # position in unified list (0=claude)
    local num=$(( idx + 1 ))
    local is_selected=$(( CURSOR_POS == list_pos ))
    local bg=""
    local cursor="  "
    local now
    now=$(date +%s)

    if [[ "$MODE" == "kill" ]]; then
        if [[ "${KILL_SELECTED[$idx]}" == "1" ]]; then
            bg="$BG_KILL"
            cursor=" ${C_RED}${ICON_KILL}${RESET}"
        fi
        if (( is_selected )); then
            bg="${BG_KILL:-$BG_HIGHLIGHT}"
            [[ "${KILL_SELECTED[$idx]}" != "1" ]] && bg="$BG_HIGHLIGHT"
            cursor=" ${C_ACCENT}${ICON_CURSOR}${RESET}"
            [[ "${KILL_SELECTED[$idx]}" == "1" ]] && cursor=" ${C_RED}${ICON_KILL}${RESET}"
        fi
    elif (( is_selected )); then
        bg="$BG_HIGHLIGHT"
        cursor=" ${C_ACCENT}${ICON_CURSOR}${RESET}"
    fi

    local name="${SESSION_NAMES[$idx]}"
    local windows="${SESSION_WINDOWS[$idx]}"
    local status="${SESSION_STATUSES[$idx]}"
    local activity="${SESSION_ACTIVITIES[$idx]}"
    local cmd="${SESSION_CMDS[$idx]}"
    local path="${SESSION_PATHS[$idx]}"

    local age_str=""
    if [[ -n "$activity" ]]; then
        age_str=$(human_age $(( now - activity )))
    fi

    local status_icon
    if [[ "$status" == "attached" ]]; then
        status_icon="${C_GREEN}${ICON_ATTACHED}${RESET}"
    else
        status_icon="${C_DIM}${ICON_DETACHED}${RESET}"
    fi

    # Command display (skip shells)
    local cmd_str=""
    if [[ -n "$cmd" && "$cmd" != "zsh" && "$cmd" != "bash" && "$cmd" != "fish" ]]; then
        cmd_str="$cmd"
    fi

    if $WIDE_MODE; then
        local inner=$(( COLS - 4 ))
        local short_path
        short_path=$(truncate_path "$path" 25)

        # Build: num cursor name    windows cmd path    age status
        local left="  ${C_ACCENT}${BOLD}${num}${RESET} ${cursor} ${C_TEXT}${name}${RESET}"
        local mid="${C_DIM}${windows}w${RESET}"
        if [[ -n "$cmd_str" ]]; then
            mid+="  ${C_PURPLE}${cmd_str}${RESET}"
        fi
        mid+="  ${C_DIM}${short_path}${RESET}"
        local right="${C_DIM}${age_str}${RESET}  ${status_icon}"

        visible_len "$left"; local left_vis=$REPLY
        visible_len "$mid"; local mid_vis=$REPLY
        visible_len "$right"; local right_vis=$REPLY

        # Calculate padding
        local name_pad=$(( 20 - ${#name} ))
        (( name_pad < 1 )) && name_pad=1
        local end_pad=$(( inner - left_vis - name_pad - mid_vis - right_vis + 1 ))
        (( end_pad < 1 )) && end_pad=1

        local full_row="  ${C_BORDER}${BOX_V}${RESET}${left}$(printf "%*s" "$name_pad" "")${mid}$(printf "%*s" "$end_pad" "")${right} ${C_BORDER}${BOX_V}${RESET}"
        print_row "$full_row" "$bg"
    else
        # Narrow mode: num cursor name  windows cmd  age status
        local left="${cursor}${C_ACCENT}${BOLD}${num}${RESET} ${C_TEXT}${name}${RESET}"
        local right=""
        if [[ -n "$cmd_str" ]]; then
            right+="${C_DIM}${windows}w ${C_PURPLE}${cmd_str}${RESET}"
        else
            right+="${C_DIM}${windows}w${RESET}"
        fi
        right+="  ${C_DIM}${age_str}${RESET} ${status_icon}"

        visible_len "$left"; local left_vis=$REPLY
        visible_len "$right"; local right_vis=$REPLY
        local mid_pad=$(( COLS - left_vis - right_vis - 2 ))
        (( mid_pad < 1 )) && mid_pad=1

        local full_row="  ${left}$(printf "%*s" "$mid_pad" "")${right}"
        print_row "$full_row" "$bg"
    fi
}

render_separator() {
    if $WIDE_MODE; then
        local inner=$(( COLS - 4 ))
        local line=""
        for (( i=0; i<inner; i++ )); do line+="$BOX_H"; done
        print_padded "  ${C_BORDER}${BOX_ML}${line}${BOX_MR}${RESET}"
    fi
}

render_preview() {
    local session_idx=$(( CURSOR_POS - 1 ))
    local session_name=""

    if (( CURSOR_POS == 0 )); then
        if claude_session_exists; then
            session_name="claude"
        else
            return
        fi
    elif (( session_idx >= 0 && session_idx < SESSION_COUNT )); then
        session_name="${SESSION_KEYS[$session_idx]}"
    else
        return
    fi

    local wins
    wins=$(get_session_windows "$session_name")
    [[ -z "$wins" ]] && return

    local preview_line="${C_TEXT}${session_name}${RESET}: ${C_DIM}${wins}${RESET}"

    if $WIDE_MODE; then
        local inner=$(( COLS - 4 ))
        visible_len "$preview_line"; local vis=$REPLY
        local pad=$(( inner - vis - 2 ))
        (( pad < 0 )) && pad=0
        print_padded "  ${C_BORDER}${BOX_V}${RESET}  ${preview_line}$(printf "%*s" "$pad" "")${C_BORDER}${BOX_V}${RESET}"
    else
        print_padded ""
        print_padded "  ${preview_line}"
    fi
}

render_footer() {
    if $WIDE_MODE; then
        # Bottom border
        local inner=$(( COLS - 4 ))
        local line=""
        for (( i=0; i<inner; i++ )); do line+="$BOX_H"; done
        print_padded "  ${C_BORDER}${BOX_BL}${line}${BOX_BR}${RESET}"
    fi

    if [[ "$MODE" == "kill" ]]; then
        local sel_count=0
        local i
        for (( i=0; i<SESSION_COUNT; i++ )); do
            [[ "${KILL_SELECTED[$i]}" == "1" ]] && (( sel_count++ ))
        done

        if $WIDE_MODE; then
            print_padded "  ${C_DIM}${ICON_CURSOR}${ICON_CURSOR}${RESET}/${C_TEXT}jk${RESET} navigate  ${C_TEXT}space${RESET} toggle  ${C_TEXT}enter${RESET} ${C_RED}kill${RESET} (${sel_count})  ${C_TEXT}a${RESET} all  ${C_TEXT}q${RESET} back"
        else
            print_padded "  ${C_DIM}${ICON_CURSOR}${ICON_CURSOR}${RESET} nav  ${C_TEXT}space${RESET} toggle  ${C_TEXT}a${RESET} all"
            print_padded "  ${C_TEXT}enter${RESET} ${C_RED}kill${RESET} (${sel_count})  ${C_TEXT}q${RESET} back"
        fi
    else
        local sort_label
        [[ "$SORT_MODE" == "activity" ]] && sort_label="recent" || sort_label="a-z"

        if $WIDE_MODE; then
            print_padded "  ${C_DIM}${ICON_CURSOR}${ICON_CURSOR}${RESET}/${C_TEXT}jk${RESET} navigate  ${C_TEXT}enter${RESET} attach  ${C_TEXT}n${RESET} new  ${C_TEXT}r${RESET} rename  ${C_TEXT}d${RESET} kill  ${C_TEXT}s${RESET} sort:${sort_label}  ${C_TEXT}q${RESET} quit"
        else
            print_padded "  ${C_DIM}${ICON_CURSOR}${ICON_CURSOR}${RESET} nav  ${C_TEXT}enter${RESET} attach  ${C_TEXT}n${RESET} new"
            print_padded "  ${C_TEXT}r${RESET} rename  ${C_TEXT}d${RESET} kill  ${C_TEXT}s${RESET} ${sort_label}  ${C_TEXT}q${RESET} quit"
        fi
    fi

    # Status message
    local now
    now=$(date +%s)
    if [[ -n "$STATUS_MSG" && "$now" -lt "$STATUS_EXPIRE" ]]; then
        print_padded ""
        print_padded "  ${C_YELLOW}${STATUS_MSG}${RESET}"
    fi
}

draw_screen() {
    # Update terminal dimensions
    COLS=$(tput cols 2>/dev/null) || COLS=80
    LINES=$(tput lines 2>/dev/null) || LINES=24
    WIDE_MODE=false
    (( COLS >= 80 )) && WIDE_MODE=true

    # Move to top-left (flicker-free)
    tput cup 0 0 2>/dev/null

    print_padded ""
    render_header
    print_padded ""

    render_claude_row

    if (( SESSION_COUNT > 0 )); then
        print_padded ""
        for (( i=0; i<SESSION_COUNT; i++ )); do
            render_session_row "$i"
        done
    fi

    print_padded ""

    if [[ "$MODE" != "kill" ]]; then
        render_separator
        render_preview
    fi

    render_footer

    # Clear any remaining lines from previous draw
    tput ed 2>/dev/null
}

# ==========================================================
# Section 7: Input
# ==========================================================

read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null

    # Handle escape sequences (arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        local seq
        IFS= read -rsn1 -t 0.05 seq 2>/dev/null
        if [[ -z "$seq" ]]; then
            KEY_RESULT="escape"
            return
        fi
        if [[ "$seq" == "[" ]]; then
            local seq2
            IFS= read -rsn1 -t 0.05 seq2 2>/dev/null
            case "$seq2" in
                A) KEY_RESULT="up"; return ;;
                B) KEY_RESULT="down"; return ;;
                C) KEY_RESULT="right"; return ;;
                D) KEY_RESULT="left"; return ;;
            esac
        fi
        KEY_RESULT="escape"
        return
    fi

    case "$key" in
        "") KEY_RESULT="enter" ;;
        " ") KEY_RESULT="space" ;;
        $'\x7f'|$'\b') KEY_RESULT="backspace" ;;
        *) KEY_RESULT="$key" ;;
    esac
}

handle_normal_mode() {
    local key="$1"

    case "$key" in
        up|k)
            (( CURSOR_POS-- ))
            (( CURSOR_POS < 0 )) && CURSOR_POS=$(( TOTAL_COUNT - 1 ))
            ;;
        down|j)
            (( CURSOR_POS++ ))
            (( CURSOR_POS >= TOTAL_COUNT )) && CURSOR_POS=0
            ;;
        enter)
            if (( CURSOR_POS == 0 )); then
                attach_claude
            else
                local idx=$(( CURSOR_POS - 1 ))
                if (( idx >= 0 && idx < SESSION_COUNT )); then
                    attach_or_switch "${SESSION_KEYS[$idx]}"
                fi
            fi
            ;;
        c|C)
            attach_claude
            ;;
        [1-9])
            local idx=$(( key - 1 ))
            if (( idx < SESSION_COUNT )); then
                attach_or_switch "${SESSION_KEYS[$idx]}"
            fi
            ;;
        n|N)
            # Inline new session prompt
            tput cnorm 2>/dev/null
            local prompt_y=$(( TOTAL_COUNT + 5 ))
            tput cup "$prompt_y" 2 2>/dev/null
            printf "${C_ACCENT}new session name ${C_DIM}(enter=default):${RESET} "

            local session_name=""
            while true; do
                IFS= read -rsn1 ch
                case "$ch" in
                    $'\x7f'|$'\b')
                        if [[ -n "$session_name" ]]; then
                            session_name="${session_name%?}"
                            printf "\b \b"
                        fi
                        ;;
                    ""|$'\n')
                        break
                        ;;
                    $'\x1b')
                        tput civis 2>/dev/null
                        return
                        ;;
                    *)
                        session_name+="$ch"
                        printf "%s" "$ch"
                        ;;
                esac
            done
            tput civis 2>/dev/null
            new_session "$session_name"
            ;;
        r)
            if (( CURSOR_POS == 0 )); then
                set_status "Cannot rename Claude session"
            elif (( SESSION_COUNT > 0 )); then
                rename_session
            fi
            ;;
        d|D)
            if (( SESSION_COUNT > 0 )); then
                MODE="kill"
                KILL_SELECTED=()
                # Move cursor to first session if on Claude row
                (( CURSOR_POS == 0 )) && CURSOR_POS=1
            fi
            ;;
        s)
            if [[ "$SORT_MODE" == "activity" ]]; then
                SORT_MODE="name"
                set_status "Sort: alphabetical"
            else
                SORT_MODE="activity"
                set_status "Sort: recent activity"
            fi
            refresh_data
            ;;
        l)
            # Last session = first in activity-sorted list
            if (( SESSION_COUNT > 0 )); then
                if [[ "$SORT_MODE" == "activity" ]]; then
                    attach_or_switch "${SESSION_KEYS[0]}"
                else
                    # Need to find most recent
                    local last
                    last=$(tmux ls -F '#{session_activity}|#{session_name}' 2>/dev/null | grep -v '|claude$' | sort -t'|' -k1 -rn | head -1 | cut -d'|' -f2)
                    [[ -n "$last" ]] && attach_or_switch "$last"
                fi
            fi
            ;;
        q|escape)
            tput cnorm 2>/dev/null
            tput rmcup 2>/dev/null
            exit 0
            ;;
    esac
}

handle_kill_mode() {
    local key="$1"

    case "$key" in
        up|k)
            (( CURSOR_POS-- ))
            (( CURSOR_POS < 1 )) && CURSOR_POS=$TOTAL_COUNT  # wrap, skip Claude
            (( CURSOR_POS >= TOTAL_COUNT )) && CURSOR_POS=$(( TOTAL_COUNT - 1 ))
            # Skip Claude row
            (( CURSOR_POS == 0 )) && CURSOR_POS=$(( TOTAL_COUNT - 1 ))
            ;;
        down|j)
            (( CURSOR_POS++ ))
            (( CURSOR_POS >= TOTAL_COUNT )) && CURSOR_POS=1  # wrap, skip Claude
            # Skip Claude row
            (( CURSOR_POS == 0 )) && CURSOR_POS=1
            ;;
        space)
            local idx=$(( CURSOR_POS - 1 ))
            if (( idx >= 0 && idx < SESSION_COUNT )); then
                if [[ "${KILL_SELECTED[$idx]}" == "1" ]]; then
                    unset 'KILL_SELECTED[$idx]'
                else
                    KILL_SELECTED[$idx]="1"
                fi
            fi
            ;;
        enter)
            local has_selection=false
            local i
            for (( i=0; i<SESSION_COUNT; i++ )); do
                [[ "${KILL_SELECTED[$i]}" == "1" ]] && has_selection=true && break
            done
            if $has_selection; then
                kill_sessions
                MODE="normal"
                (( SESSION_COUNT == 0 )) && CURSOR_POS=0
            fi
            ;;
        a)
            # Toggle all
            local all_selected=true
            for (( i=0; i<SESSION_COUNT; i++ )); do
                if [[ "${KILL_SELECTED[$i]}" != "1" ]]; then
                    all_selected=false
                    break
                fi
            done
            if $all_selected; then
                KILL_SELECTED=()
            else
                for (( i=0; i<SESSION_COUNT; i++ )); do
                    KILL_SELECTED[$i]="1"
                done
            fi
            ;;
        [1-9])
            local idx=$(( key - 1 ))
            if (( idx < SESSION_COUNT )); then
                if [[ "${KILL_SELECTED[$idx]}" == "1" ]]; then
                    unset 'KILL_SELECTED[$idx]'
                else
                    KILL_SELECTED[$idx]="1"
                fi
            fi
            ;;
        q|escape)
            MODE="normal"
            KILL_SELECTED=()
            ;;
    esac
}

# ==========================================================
# Section 8: Main Loop
# ==========================================================

if ! command -v tmux &>/dev/null; then
    echo "tmux not found"
    exit 1
fi

# Enter alternate screen buffer for clean exit
tput smcup 2>/dev/null

build_session_list

# Hide cursor
tput civis 2>/dev/null

# Cleanup on exit
cleanup() {
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
}
trap cleanup INT TERM EXIT

# Redraw on terminal resize
trap 'draw_screen' WINCH

while true; do
    draw_screen
    read_key
    if [[ "$MODE" == "kill" ]]; then
        handle_kill_mode "$KEY_RESULT"
    else
        handle_normal_mode "$KEY_RESULT"
    fi
done
