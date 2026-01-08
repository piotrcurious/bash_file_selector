#!/usr/bin/env bash
# ==============================================================================
# FILE SELECTOR - A reusable file selection script
#
# Usage:
#   ./file_selector.sh <start_dir> <output_file>
#
# Returns the selected file path in the specified output file.
# ==============================================================================

set -uo pipefail

# ------- Configuration -------
readonly FILES_PER_PAGE=20
readonly FILES_CACHE="$(mktemp --tmpdir selector_files.XXXXXX)"

# Capture initial terminal state
readonly INITIAL_STTY_SETTINGS=$(stty -g 2>/dev/null || echo "")

# Globals
CURRENT_DIR="${1:-.}"
OUTPUT_FILE="${2:-/dev/stdout}"
CURSOR_POS=0
CURRENT_PAGE=0
TOTAL_FILES=0
TOTAL_PAGES=1

# ------- Terminal Setup / Cleanup -------
cleanup_exit() {
    trap - INT TERM EXIT
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    if [[ -n "$INITIAL_STTY_SETTINGS" ]]; then
        stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true
    fi
    rm -f -- "$FILES_CACHE" 2>/dev/null || true
    exit "${1:-0}"
}

trap 'cleanup_exit 1' INT TERM
trap 'cleanup_exit 0' EXIT

enable_input_mode() {
    stty -echo -icanon time 0 min 1 2>/dev/null || true
    tput civis 2>/dev/null || true
}

disable_input_mode() {
    stty echo icanon 2>/dev/null || true
    tput cnorm 2>/dev/null || true
}

# Start UI
tput smcup 2>/dev/null || true

# ------- Core Logic: Indexing -------
index_dir() {
    local dir="$1"
    : > "$FILES_CACHE"
    find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z 2>/dev/null | tr '\0' '\n' > "$FILES_CACHE"
    TOTAL_FILES=$(wc -l < "$FILES_CACHE" 2>/dev/null || echo 0)
    TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    if (( TOTAL_PAGES < 1 )); then TOTAL_PAGES=1; fi
    if (( CURRENT_PAGE >= TOTAL_PAGES )); then CURRENT_PAGE=$((TOTAL_PAGES - 1)); fi
    if (( CURRENT_PAGE < 0 )); then CURRENT_PAGE=0; fi
}

get_selected_path() {
    if (( TOTAL_FILES == 0 )); then echo ""; return; fi
    local index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    sed -n "${index}p" "$FILES_CACHE"
}

# ------- UI / Drawing -------
draw_page() {
    tput clear
    tput cup 0 0
    printf "\033[1m\033[36mSELECT FILE\033[0m - \033[32m%s\033[0m\n" "$CURRENT_DIR"
    printf "\033[2mFiles: %d | Page: %d/%d\033[0m\n" "$TOTAL_FILES" "$((CURRENT_PAGE + 1))" "$TOTAL_PAGES"
    echo "────────────────────────────────────────────────────────────────────────────────"

    local start=$(( CURRENT_PAGE * FILES_PER_PAGE + 1 ))
    local end=$(( start + FILES_PER_PAGE - 1 ))
    if (( end > TOTAL_FILES )); then end=$TOTAL_FILES; fi

    if (( TOTAL_FILES == 0 )); then
        echo -e "   \033[2m(Empty directory)\033[0m"
    else
        local line_num=0
        while IFS= read -r f; do
            local fname="$(basename "$f")"
            local indicator="  "
            if [ "$line_num" -eq "$CURSOR_POS" ]; then indicator="\033[1m\033[36m▶ "; fi

            local decoration="" suffix=""
            if [[ -L "$f" ]]; then decoration="\033[1m\033[35m"; suffix=" → $(readlink "$f" 2>/dev/null || echo '?')"
            elif [[ -d "$f" ]]; then decoration="\033[1m\033[34m"; suffix="/"
            elif [[ -x "$f" ]]; then decoration="\033[32m"; suffix="*"
            fi

            printf "%b%b%s%s\033[0m\n" "$indicator" "$decoration" "$fname" "$suffix"
            line_num=$((line_num + 1))
        done < <(sed -n "${start},${end}p" "$FILES_CACHE")
    fi
}

# ------- Actions -------
enter_item() {
    local path="$(get_selected_path)"
    if [[ -z "$path" ]]; then return; fi
    if [[ -d "$path" ]]; then
        cd "$path" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    else
        echo "$path" > "$OUTPUT_FILE"
        cleanup_exit 0
    fi
}

go_up() {
    local parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        cd "$parent" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    fi
}

# ------- Main Loop -------
enable_input_mode
index_dir "$CURRENT_DIR"

while true; do
    draw_page
    if ! IFS= read -rsn1 key; then key=""; fi

    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.01 rest || rest=""
        key+="$rest"
        case "$key" in
            $'\x1b[A') # Up
                if [ "$CURSOR_POS" -gt 0 ]; then CURSOR_POS=$((CURSOR_POS - 1));
                elif [ "$CURRENT_PAGE" -gt 0 ]; then CURRENT_PAGE=$((CURRENT_PAGE - 1)); CURSOR_POS=$((FILES_PER_PAGE - 1)); fi;;
            $'\x1b[B') # Down
                files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                if (( files_on_page > FILES_PER_PAGE )); then files_on_page=$FILES_PER_PAGE; fi
                if [ "$CURSOR_POS" -lt $((files_on_page - 1)) ]; then CURSOR_POS=$((CURSOR_POS + 1));
                elif [ "$CURRENT_PAGE" -lt $((TOTAL_PAGES - 1)) ]; then CURRENT_PAGE=$((CURRENT_PAGE + 1)); CURSOR_POS=0; fi;;
            $'\x1b[D') go_up ;;
            $'\x1b[C') enter_item ;;
        esac
        continue
    fi

    if [[ "$key" == "" || "$key" == $'\r' || "$key" == $'\n' ]]; then enter_item; continue; fi
    if [[ "$key" == $'\x7f' || "$key" == $'\x08' ]]; then go_up; continue; fi

    case "$key" in
        q|Q) cleanup_exit 1 ;;
    esac
done
