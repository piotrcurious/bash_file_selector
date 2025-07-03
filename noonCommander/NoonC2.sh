#!/bin/bash

# Configuration
FILES_PER_PAGE=20
INDENT="    "
WRAP_WIDTH=$(tput cols)
SELECTION_FILE=".commander_selection.tmp"

# Initialize
CURRENT_DIR="$(pwd)"
> "$SELECTION_FILE"
CURSOR_POS=0
CURRENT_PAGE=0

# Terminal setup
stty -echo -icanon time 0 min 0
trap 'tput cnorm; stty sane; clear; exit' INT TERM EXIT

index_dir() {
    local dir="$1"
    TMP_INDEX_FILE="/tmp/file_commander_index_$(echo "$dir" | md5sum | awk '{print $1}').tmp"
    find "$dir" -mindepth 1 -maxdepth 1 | sort > "$TMP_INDEX_FILE"
    TOTAL_FILES=$(wc -l < "$TMP_INDEX_FILE")
    TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
}

draw_page() {
    clear
    tput civis
    echo "📁 BASH COMMANDER - $CURRENT_DIR"
    echo "↑ ↓: Move  Enter: Open  ←: Up  [c] Copy  [m] Move  [d] Delete  [r] Rename  [q] Quit"
    echo

    START=$((CURRENT_PAGE * FILES_PER_PAGE + 1))
    END=$((START + FILES_PER_PAGE - 1))

    awk -v s="$START" -v e="$END" -v c="$CURSOR_POS" -v w="$WRAP_WIDTH" -v base="$CURRENT_DIR" '
    NR >= s && NR <= e {
        path = $0;
        fname = substr(path, length(base) + 2);
        prefix = (NR - s == c ? "> " : "  ");
        while (length(fname) > w - 4) {
            print prefix substr(fname,1,w-4);
            fname = substr(fname,w-3);
            prefix = "  '"$INDENT"'";
        }
        print prefix fname;
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

get_selected_path() {
    local line=$((CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1))
    sed -n "${line}p" "$TMP_INDEX_FILE"
}

rename_file() {
    local src="$(get_selected_path)"
    echo -n "Rename '$(basename "$src")' to: "
    tput cnorm; stty sane
    read newname
    mv -- "$src" "$(dirname "$src")/$newname" && echo "Renamed" || echo "Rename failed"
    sleep 1
}

delete_file() {
    local path="$(get_selected_path)"
    echo -n "Delete '$(basename "$path")'? [y/N]: "
    tput cnorm; stty sane
    read ans
    [[ "$ans" == [yY] ]] && rm -rf -- "$path" && echo "Deleted" || echo "Skipped"
    sleep 1
}

copy_file() {
    local src="$(get_selected_path)"
    echo -n "Copy to (path): "
    tput cnorm; stty sane
    read dest
    cp -r -- "$src" "$dest" && echo "Copied" || echo "Copy failed"
    sleep 1
}

move_file() {
    local src="$(get_selected_path)"
    echo -n "Move to (path): "
    tput cnorm; stty sane
    read dest
    mv -- "$src" "$dest" && echo "Moved" || echo "Move failed"
    sleep 1
}

enter_item() {
    local path="$(get_selected_path)"
    if [[ -d "$path" ]]; then
        CURRENT_DIR="$path"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    else
        echo "$path" >> "$SELECTION_FILE"
    fi
}

go_up() {
    local parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        CURRENT_DIR="$parent"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    fi
}

# Main loop
index_dir "$CURRENT_DIR"
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
        enter_item
    elif [[ $key == $'\x7f' ]]; then
        go_up
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

tput cnorm; stty sane; clear
echo "Session ended. Selections: $SELECTION_FILE" 
