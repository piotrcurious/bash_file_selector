 #!/bin/bash

# CONFIGURATION
FILES_PER_PAGE=20
TMP_INDEX_FILE="/tmp/file_commander_index_$(pwd | md5sum | awk '{print $1}').tmp"
SELECTION_FILE="./.commander_selection.tmp"
WRAP_WIDTH=$(tput cols)
INDENT="    "

# Create file index
find . -maxdepth 1 -type f -printf '%P\n' | nl -w6 -nln > "$TMP_INDEX_FILE"

TOTAL_FILES=$(wc -l < "$TMP_INDEX_FILE")
TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
CURRENT_PAGE=0
CURSOR_POS=0

> "$SELECTION_FILE"

stty -echo -icanon time 0 min 0
trap 'tput cnorm; stty sane; clear; exit' INT TERM EXIT

draw_page() {
    clear
    tput civis
    echo "📁 BASH COMMANDER - $(pwd)"
    echo "Navigate: ↑ ↓ | Enter: Select | [c] Copy | [m] Move | [d] Delete | [r] Rename | [q] Quit"
    echo

    START_LINE=$(( CURRENT_PAGE * FILES_PER_PAGE + 1 ))
    END_LINE=$(( START_LINE + FILES_PER_PAGE - 1 ))

    awk -v s="$START_LINE" -v e="$END_LINE" -v c="$CURSOR_POS" -v w="$WRAP_WIDTH" '
    NR >= s && NR <= e {
        fname = substr($0, index($0, $2));
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

get_current_file() {
    local TARGET_LINE=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    awk -v l="$TARGET_LINE" 'NR==l {print substr($0, index($0,$2))}' "$TMP_INDEX_FILE"
}

select_file() {
    get_current_file >> "$SELECTION_FILE"
}

rename_file() {
    local file=$(get_current_file)
    echo -n "Rename '$file' to: "
    tput cnorm
    stty sane
    read newname
    mv -- "$file" "$newname" 2>/dev/null && echo "Renamed to $newname" || echo "Rename failed"
    sleep 1
}

delete_file() {
    local file=$(get_current_file)
    echo -n "Delete '$file'? [y/N]: "
    tput cnorm
    stty sane
    read ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] && rm -f -- "$file" && echo "Deleted" || echo "Skipped"
    sleep 1
}

copy_file() {
    local file=$(get_current_file)
    echo -n "Copy '$file' to: "
    tput cnorm
    stty sane
    read dest
    cp -- "$file" "$dest" 2>/dev/null && echo "Copied" || echo "Copy failed"
    sleep 1
}

move_file() {
    local file=$(get_current_file)
    echo -n "Move '$file' to: "
    tput cnorm
    stty sane
    read dest
    mv -- "$file" "$dest" 2>/dev/null && echo "Moved" || echo "Move failed"
    sleep 1
}

# Main loop
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
    elif [[ $key == "r" ]]; then
        rename_file
    elif [[ $key == "d" ]]; then
        delete_file
    elif [[ $key == "c" ]]; then
        copy_file
    elif [[ $key == "m" ]]; then
        move_file
    fi
done

tput cnorm
clear
echo "Session ended. Selected files saved in: $SELECTION_FILE"
