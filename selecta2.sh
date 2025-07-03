#!/bin/bash

# CONFIGURATION
FILES_PER_PAGE=20
TMP_INDEX_FILE="/tmp/file_selector_index_$(pwd | md5sum | awk '{print $1}').tmp"
SELECTION_FILE="./.file_selector_selection.tmp"
WRAP_WIDTH=$(tput cols)
INDENT="    "

# Create hashed index file
find . -maxdepth 1 -type f -printf '%P\n' | nl -w6 -nln > "$TMP_INDEX_FILE"

TOTAL_FILES=$(wc -l < "$TMP_INDEX_FILE")
TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
CURRENT_PAGE=0
CURSOR_POS=0

# Ensure selection file exists
> "$SELECTION_FILE"

# Terminal setup
stty -echo -icanon time 0 min 0
trap 'tput cnorm; stty sane; clear; exit' INT TERM EXIT

draw_page() {
    clear
    tput civis
    echo "File Selector - Page $((CURRENT_PAGE+1))/$TOTAL_PAGES"
    echo "Use ↑ ↓ to navigate, [Enter] to select, [q] to quit"

    START_LINE=$(( CURRENT_PAGE * FILES_PER_PAGE + 1 ))
    END_LINE=$(( START_LINE + FILES_PER_PAGE - 1 ))
    awk -v s="$START_LINE" -v e="$END_LINE" -v c="$CURSOR_POS" -v w="$WRAP_WIDTH" '
    NR>=s && NR<=e {
        fname = substr($0, index($0,$2));
        display = fname;
        gsub(/[^[:print:]]/, "?", display);
        prefix = (NR-s == c ? "> " : "  ");
        while (length(display) > w - 4) {
            print prefix substr(display,1,w-4);
            display = substr(display,w-3);
            prefix = "  '"$INDENT"'";
        }
        print prefix display;
    }' "$TMP_INDEX_FILE"
}

move_cursor_up() {
    if (( CURSOR_POS > 0 )); then
        ((CURSOR_POS--))
    elif (( CURRENT_PAGE > 0 )); then
        ((CURRENT_PAGE--))
        CURSOR_POS=$((FILES_PER_PAGE - 1))
    fi
}

move_cursor_down() {
    if (( CURSOR_POS < FILES_PER_PAGE - 1 && CURSOR_POS + CURRENT_PAGE * FILES_PER_PAGE < TOTAL_FILES - 1 )); then
        ((CURSOR_POS++))
    elif (( CURRENT_PAGE < TOTAL_PAGES - 1 )); then
        ((CURRENT_PAGE++))
        CURSOR_POS=0
    fi
}

select_file() {
    TARGET_LINE=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    FILE=$(awk -v l="$TARGET_LINE" 'NR==l {print substr($0, index($0,$2))}' "$TMP_INDEX_FILE")
    echo "$FILE" >> "$SELECTION_FILE"
}

# Key reading loop
while true; do
    draw_page
    read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.01 rest
        key+=$rest
        case "$key" in
            $'\x1b[A') move_cursor_up ;;
            $'\x1b[B') move_cursor_down ;;
        esac
    elif [[ $key == "" ]]; then
        select_file
    elif [[ $key == "q" ]]; then
        break
    fi
done

# Cleanup and exit
tput cnorm
clear
echo "Selected files saved to: $SELECTION_FILE"
