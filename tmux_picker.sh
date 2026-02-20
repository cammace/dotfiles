#!/bin/bash

# --- Nord Color Palette (256-color approximations + true color) ---
BOLD=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)

# Nord colors via ANSI escapes for true color support
N0='\033[38;2;46;52;64m'      # nord0  - dark bg
N3='\033[38;2;76;86;106m'     # nord3  - comments/dim
N4='\033[38;2;216;222;233m'   # nord4  - text
N8='\033[38;2;136;192;208m'   # nord8  - frost/teal
N9='\033[38;2;129;161;193m'   # nord9  - blue
N11='\033[38;2;191;97;106m'   # nord11 - red
N13='\033[38;2;235;203;139m'  # nord13 - yellow
N14='\033[38;2;163;190;140m'  # nord14 - green
N15='\033[38;2;180;142;173m'  # nord15 - purple

BG_N9='\033[48;2;129;161;193m'   # nord9 bg
BG_N3='\033[48;2;76;86;106m'     # nord3 bg
FG_N0='\033[38;2;46;52;64m'      # nord0 fg (dark text on light bg)

# --- Functions ---
human_age() {
    local diff=$1
    if (( diff < 60 )); then
        echo "${diff}s"
    elif (( diff < 3600 )); then
        echo "$(( diff / 60 ))m"
    elif (( diff < 86400 )); then
        echo "$(( diff / 3600 ))h"
    else
        echo "$(( diff / 86400 ))d"
    fi
}

build_session_list() {
    DISPLAY_NAMES=()
    DISPLAY_ICONS=()
    DISPLAY_DETAILS=()
    SESSION_KEYS=()

    # Claude shortcut always first
    DISPLAY_NAMES+=("Claude Code")
    DISPLAY_ICONS+=("🤖")
    DISPLAY_DETAILS+=("auto-attach or create")
    SESSION_KEYS+=("__claude__")

    local now
    now=$(date +%s)

    # Existing tmux sessions (skip 'claude' to avoid duplicate)
    while IFS='|' read -r name windows status activity; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "claude" ]] && continue
        local age_str=""
        if [[ -n "$activity" ]]; then
            local diff=$(( now - activity ))
            age_str=" · $(human_age $diff) ago"
        fi
        local status_icon="○"
        [[ "$status" == "attached" ]] && status_icon="●"
        DISPLAY_NAMES+=("$name")
        DISPLAY_ICONS+=("$status_icon")
        DISPLAY_DETAILS+=("${windows} window$([ "$windows" != "1" ] && echo "s") · ${status}${age_str}")
        SESSION_KEYS+=("$name")
    done < <(tmux ls -F '#{session_name}|#{session_windows}|#{?session_attached,attached,detached}|#{session_activity}' 2>/dev/null)

    ITEM_COUNT=${#DISPLAY_NAMES[@]}
}

draw_menu() {
    _sel=$1
    local cols
    cols=$(tput cols)

    clear

    # Header
    echo ""
    echo -e "  ${N8}${BOLD}╭─────────────────────────────╮${RESET}"
    echo -e "  ${N8}${BOLD}│     SESSION PICKER          │${RESET}"
    echo -e "  ${N8}${BOLD}╰─────────────────────────────╯${RESET}"
    echo ""
    echo -e "  ${N3}↑↓${N4} navigate  ${N3}⏎${N4} select  ${N3}d${N4} kill  ${N3}q${N4} quit${RESET}"
    echo ""

    # Sessions
    for i in "${!DISPLAY_NAMES[@]}"; do
        local icon="${DISPLAY_ICONS[$i]}"
        local name="${DISPLAY_NAMES[$i]}"
        local detail="${DISPLAY_DETAILS[$i]}"

        if [ "$i" -eq "$_sel" ]; then
            # Selected item - highlighted bar
            echo -e "  ${BG_N9}${FG_N0}${BOLD}  ❯ ${icon} ${name}  ${RESET}  ${N3}${detail}${RESET}"
        elif [[ "${SESSION_KEYS[$i]}" == "__claude__" ]]; then
            echo -e "    ${N15}${icon} ${BOLD}${name}${RESET}  ${N3}${detail}${RESET}"
        else
            echo -e "    ${N4}${icon} ${name}${RESET}  ${N3}${detail}${RESET}"
        fi
    done

    # Separator
    echo ""

    # New Session option
    if [ "$_sel" -eq "$ITEM_COUNT" ]; then
        echo -e "  ${BG_N9}${FG_N0}${BOLD}  ❯ ＋ New Session  ${RESET}"
    else
        echo -e "    ${N14}＋ New Session${RESET}"
    fi

    echo ""
}

# --- Main Logic ---
build_session_list

INDEX=0

tput civis
trap "tput cnorm; exit" INT TERM

while true; do
    draw_menu "$INDEX"

    # Read 1 byte; if escape, read 2 more for arrow sequence
    read -rsn1 key
    case "$key" in
        $'\x1b')
            read -rsn2 arrow
            case "$arrow" in
                '[A') ((INDEX--)); [ $INDEX -lt 0 ] && INDEX=$ITEM_COUNT ;;
                '[B') ((INDEX++)); [ $INDEX -gt $ITEM_COUNT ] && INDEX=0 ;;
            esac
            ;;
        "") # Enter
            break
            ;;
        "d"|"D")
            # Only allow killing non-Claude sessions
            if [ "$INDEX" -gt 0 ] && [ "$INDEX" -lt "$ITEM_COUNT" ]; then
                _target="${SESSION_KEYS[$INDEX]}"
                echo -e "  ${N11}${BOLD}Kill session '${_target}'?${RESET} ${N3}(y/N)${RESET}"
                read -rsn1 _confirm
                if [[ "$_confirm" == "y" || "$_confirm" == "Y" ]]; then
                    tmux kill-session -t "$_target" 2>/dev/null
                    build_session_list
                    [ $INDEX -ge $ITEM_COUNT ] && INDEX=$((ITEM_COUNT - 1))
                    [ $INDEX -lt 0 ] && INDEX=0
                fi
            fi
            ;;
        "q"|"Q")
            tput cnorm
            exit 0
            ;;
    esac
done

tput cnorm

# --- Execute Selection ---
if [ "$INDEX" -eq "$ITEM_COUNT" ]; then
    # Prompt for session name
    echo ""
    echo -ne "  ${N8}Session name ${N3}(enter for default):${RESET} "
    read -r session_name
    if [[ -n "$session_name" ]]; then
        exec tmux new-session -s "$session_name"
    else
        exec tmux new-session
    fi
elif [[ "${SESSION_KEYS[$INDEX]}" == "__claude__" ]]; then
    exec tmux new-session -A -s claude 'claude'
else
    exec tmux attach-session -t "${SESSION_KEYS[$INDEX]}"
fi
