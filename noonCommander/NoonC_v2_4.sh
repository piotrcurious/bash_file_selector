#!/usr/bin/env bash
# ==============================================================================
# BASH Commander - Enhanced File Manager
# Version: 2.4 (Refactored & Fixed)
# ==============================================================================

set -u

# ------- Configuration -------
FILES_PER_PAGE=20
DEST_FAV_FILE="${HOME}/.commander_dest_favs"
MARKS_FILE="$(mktemp --tmpdir commander_marks.XXXXXX)"
CLIPBOARD_FILE="$(mktemp --tmpdir commander_clipboard.XXXXXX)"

# Globals
CURRENT_DIR="$(pwd)"
CURSOR_POS=0
CURRENT_PAGE=0
CLIPBOARD_MODE=""  # 'copy' or 'cut'
WRAP_WIDTH=80
TOTAL_FILES=0
TOTAL_PAGES=1
FILES=()           # Master array of files in current dir

# Ensure config exists
mkdir -p "$(dirname "$DEST_FAV_FILE")"
touch "$DEST_FAV_FILE"

# ------- Terminal Setup / Cleanup -------

cleanup_exit() {
    # Restore terminal
    stty sane || true
    tput cnorm || true
    # Remove temp files
    rm -f -- "$MARKS_FILE" "$CLIPBOARD_FILE" >/dev/null 2>&1 || true
    clear
    exit 0
}
trap cleanup_exit INT TERM EXIT

enable_input_mode() {
    # Raw mode: no echo, no canonical input (byte by byte)
    stty -echo -icanon time 0 min 1
    tput civis # hide cursor
}

disable_input_mode() {
    stty sane
    tput cnorm # show cursor
}

update_width() {
    WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)"
}
trap 'update_width' WINCH
update_width

# ------- Utilities -------

format_size() {
    local size=$1
    if (( size < 1024 )); then echo "${size}B"
    elif (( size < 1048576 )); then awk -v s="$size" 'BEGIN{printf "%.1fK", s/1024}'
    elif (( size < 1073741824 )); then awk -v s="$size" 'BEGIN{printf "%.1fM", s/1048576}'
    else awk -v s="$size" 'BEGIN{printf "%.1fG", s/1073741824}'
    fi
}

show_message() {
    local msg="$1"
    local duration="${2:-1.5}"
    disable_input_mode
    # Move cursor to bottom line
    tput cup $(($(tput lines)-1)) 0
    tput el # clear line
    echo -ne "\033[1;32m ${msg}\033[0m"
    sleep "$duration"
    enable_input_mode
}

show_error() {
    local msg="$1"
    local duration="${2:-1.5}"
    disable_input_mode
    tput cup $(($(tput lines)-1)) 0
    tput el
    echo -ne "\033[1;31m ${msg}\033[0m"
    sleep "$duration"
    enable_input_mode
}

# ------- Core Logic: Indexing -------

index_dir() {
    local dir="$1"
    
    # Enable nullglob so empty dirs don't return "*"
    shopt -s nullglob dotglob

    # Read all files into the FILES array safely
    # We use find to separate by null, then sort, then mapfile to array
    FILES=()
    while IFS=  read -r -d $'\0'; do
        FILES+=("$REPLY")
    done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)

    TOTAL_FILES=${#FILES[@]}

    if (( TOTAL_FILES == 0 )); then
        TOTAL_PAGES=1
    else
        TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    fi

    # Bounds checking
    if (( CURRENT_PAGE >= TOTAL_PAGES )); then CURRENT_PAGE=$((TOTAL_PAGES - 1)); fi
    if (( CURRENT_PAGE < 0 )); then CURRENT_PAGE=0; fi
    
    # Ensure cursor is valid for the number of files on this page
    local files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
    if (( files_on_page > FILES_PER_PAGE )); then files_on_page=$FILES_PER_PAGE; fi
    
    if (( CURSOR_POS >= files_on_page )); then 
        if (( files_on_page > 0 )); then
            CURSOR_POS=$((files_on_page - 1))
        else
            CURSOR_POS=0
        fi
    fi
}

get_selected_path() {
    if (( TOTAL_FILES == 0 )); then echo ""; return; fi
    local index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS ))
    if (( index < 0 || index >= TOTAL_FILES )); then echo ""; return; fi
    echo "${FILES[$index]}"
}

# ------- Marks System -------

is_marked() {
    local path="$1"
    grep -Fxq -- "$path" "$MARKS_FILE" 2>/dev/null
}

toggle_mark() {
    local path="$1"
    if is_marked "$path"; then
        # Remove line
        grep -Fxv -- "$path" "$MARKS_FILE" > "${MARKS_FILE}.tmp" 2>/dev/null || true
        mv -f "${MARKS_FILE}.tmp" "$MARKS_FILE"
    else
        # Add line
        printf '%s\n' "$path" >> "$MARKS_FILE"
    fi
}

get_marked_array() {
    local -n out_arr=$1
    out_arr=()
    if [[ -s "$MARKS_FILE" ]]; then
        mapfile -t out_arr < "$MARKS_FILE"
    fi
}

unmark_all() {
    : > "$MARKS_FILE"
    show_message "All marks cleared." 0.7
}

# ------- UI / Drawing -------

draw_page() {
    clear
    
    # Header
    echo -e "\033[1m\033[36m📁 BASH COMMANDER\033[0m - \033[32m$CURRENT_DIR\033[0m"
    echo -e "\033[2mFiles: $TOTAL_FILES | Page: $((CURRENT_PAGE + 1))/$TOTAL_PAGES\033[0m"
    echo -e "\033[2mMarks: $(wc -l < "$MARKS_FILE") selected\033[0m"
    echo "--------------------------------------------------------------------------------"
    
    local start=$(( CURRENT_PAGE * FILES_PER_PAGE ))
    local end=$(( start + FILES_PER_PAGE - 1 ))
    if (( end >= TOTAL_FILES )); then end=$((TOTAL_FILES - 1)); fi

    if (( TOTAL_FILES == 0 )); then
        echo -e "   \033[2m(Empty directory)\033[0m"
    else
        local i
        for (( i=start; i<=end; i++ )); do
            local f="${FILES[$i]}"
            local fname
            fname="$(basename "$f")"
            local indicator="  "
            
            # Cursor logic
            if (( i == start + CURSOR_POS )); then
                indicator="\033[1m\033[36m> "
            fi

            # Mark logic
            local mark_char=" "
            if is_marked "$f"; then mark_char="*"; fi

            # Decoration based on type
            local decoration=""
            if [[ -d "$f" ]]; then
                decoration="\033[1m\033[34m" # Blue bold for dir
                fname="${fname}/"
            elif [[ -x "$f" ]]; then
                decoration="\033[32m" # Green for executable
            fi
            
            # Print the line
            printf "${indicator}[%s] ${decoration}%s\033[0m\n" "$mark_char" "$fname"
        done
    fi

    # Footer / Status
    local rows_used=$(( end - start + 1 ))
    if (( rows_used < 0 )); then rows_used=0; fi
    local remaining_lines=$(( FILES_PER_PAGE - rows_used ))
    
    for (( k=0; k<remaining_lines; k++ )); do echo; done

    echo "--------------------------------------------------------------------------------"
    if [[ -s "$CLIPBOARD_FILE" ]]; then
        local clip_item
        clip_item=$(head -n 1 "$CLIPBOARD_FILE")
        echo -e "\033[34m📋 Clipboard [$CLIPBOARD_MODE]: $(basename "$clip_item")\033[0m"
    fi
    echo -e "\033[33m[Enter]\033[0m Open  \033[33m[Space]\033[0m Mark  \033[33m[c/x/v]\033[0m Copy/Cut/Paste  \033[33m[d]\033[0m Del  \033[33m[r]\033[0m Ren"
    echo -e "\033[33m[C/M]\033[0m Copy/Move Marked  \033[33m[n]\033[0m New  \033[33m[i]\033[0m Info  \033[33m[h]\033[0m Help  \033[33m[q]\033[0m Quit"
}

# ------- Destination Picker -------

choose_destination() {
    disable_input_mode
    local dest_dir=""
    local browse_dir="$CURRENT_DIR"
    
    while true; do
        clear
        echo -e "\033[1mSelect Destination\033[0m"
        echo "Current Browse: $browse_dir"
        echo "--------------------------"
        echo "Favorites:"
        local i=1
        local fav_array=()
        if [[ -f "$DEST_FAV_FILE" ]]; then
             mapfile -t fav_array < "$DEST_FAV_FILE"
        fi

        for fav in "${fav_array[@]}"; do
            echo "  [$i] $fav"
            ((i++))
        done
        echo
        echo "Options:"
        echo "  [b] Browse filesystem here"
        echo "  [a] Add '$CURRENT_DIR' to favorites"
        echo "  [q] Cancel"
        echo "  [1-9] Select favorite"
        echo
        read -rp "Action: " act

        case "$act" in
            q) dest_dir=""; break ;;
            a) 
                if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then
                    echo "$CURRENT_DIR" >> "$DEST_FAV_FILE"
                fi
                ;;
            b)
                # Simple interactive browse
                read -rp "Enter full path or leave empty for current: " userpath
                if [[ -z "$userpath" ]]; then dest_dir="$CURRENT_DIR"; else dest_dir="$userpath"; fi
                if [[ ! -d "$dest_dir" ]]; then 
                     echo "Invalid directory!"; sleep 1; 
                else
                     break
                fi
                ;;
            *)
                if [[ "$act" =~ ^[0-9]+$ ]]; then
                    local idx=$((act - 1))
                    if [[ -n "${fav_array[$idx]:-}" ]]; then
                        dest_dir="${fav_array[$idx]}"
                        break
                    fi
                fi
                ;;
        esac
    done

    enable_input_mode
    echo "$dest_dir"
}

# ------- Actions -------

enter_item() {
    local path
    path="$(get_selected_path)"
    [[ -z "$path" ]] && return

    if [[ -d "$path" ]]; then
        CURRENT_DIR="$path"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    else
        # Try to open file
        disable_input_mode
        if command -v xdg-open &>/dev/null; then
            xdg-open "$path" >/dev/null 2>&1
        elif command -v open &>/dev/null; then
            open "$path" >/dev/null 2>&1
        else
            ${EDITOR:-nano} "$path"
        fi
        enable_input_mode
    fi
}

go_up() {
    local parent
    parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        CURRENT_DIR="$parent"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    fi
}

preview_file() {
    local file
    file="$(get_selected_path)"
    [[ -z "$file" || -d "$file" ]] && return

    disable_input_mode
    clear
    echo "Preview: $file"
    echo "----------------"
    if command -v bat &>/dev/null; then
        bat --style=plain --paging=always --color=always "$file"
    else
        less "$file"
    fi
    enable_input_mode
    draw_page # force redraw
}

rename_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" ]] && return

    disable_input_mode
    # Restore cursor for input
    tput cnorm 
    local fname
    fname="$(basename "$src")"
    
    # Position cursor at bottom
    tput cup $(($(tput lines)-2)) 0
    echo "Rename '$fname' to:"
    tput cup $(($(tput lines)-1)) 0
    read -r -e -i "$fname" newname
    
    if [[ -n "$newname" && "$newname" != "$fname" ]]; then
        mv -n "$src" "$(dirname "$src")/$newname"
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

delete_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" ]] && return

    disable_input_mode
    tput cup $(($(tput lines)-1)) 0
    read -rp "Delete $(basename "$src")? [y/N] " ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
        rm -rf "$src"
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

create_new() {
    disable_input_mode
    tput cup $(($(tput lines)-2)) 0
    echo "Create [f]ile or [d]irectory?"
    read -rn1 choice
    echo
    if [[ "$choice" == "f" ]]; then
        read -rp "Filename: " name
        [[ -n "$name" ]] && touch "$CURRENT_DIR/$name"
    elif [[ "$choice" == "d" ]]; then
        read -rp "Dirname: " name
        [[ -n "$name" ]] && mkdir -p "$CURRENT_DIR/$name"
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

clipboard_action() {
    local action="$1" # copy or cut
    local src
    src="$(get_selected_path)"
    [[ -z "$src" ]] && return

    echo "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="$action"
    show_message "Selected for $action"
}

paste_action() {
    [[ ! -s "$CLIPBOARD_FILE" ]] && { show_error "Clipboard empty"; return; }
    local src
    src="$(cat "$CLIPBOARD_FILE")"
    [[ ! -e "$src" ]] && { show_error "Source missing"; return; }

    local base
    base="$(basename "$src")"
    local dest="$CURRENT_DIR/$base"

    if [[ -e "$dest" ]]; then
        show_error "Destination exists!"
        return
    fi

    if [[ "$CLIPBOARD_MODE" == "copy" ]]; then
        cp -r "$src" "$dest"
        show_message "Copied"
    elif [[ "$CLIPBOARD_MODE" == "cut" ]]; then
        mv "$src" "$dest"
        show_message "Moved"
        : > "$CLIPBOARD_FILE" # clear clipboard
        CLIPBOARD_MODE=""
    fi
    index_dir "$CURRENT_DIR"
}

# ------- Multi-File Operations -------

process_marked() {
    local mode="$1" # C (copy), M (move), D (delete)
    local marked=()
    get_marked_array marked
    
    if (( ${#marked[@]} == 0 )); then
        show_error "No items marked"
        return
    fi

    if [[ "$mode" == "D" ]]; then
        disable_input_mode
        read -rp "Delete ${#marked[@]} items? [y/N] " ans
        enable_input_mode
        if [[ "$ans" =~ ^[yY]$ ]]; then
            for f in "${marked[@]}"; do rm -rf "$f"; done
            unmark_all
            index_dir "$CURRENT_DIR"
        fi
        return
    fi

    # For Copy/Move, get destination
    local dest
    dest="$(choose_destination)"
    [[ -z "$dest" ]] && return

    local count=0
    for src in "${marked[@]}"; do
        local rel_name
        rel_name="$(basename "$src")"
        if [[ "$mode" == "C" ]]; then
            cp -r -- "$src" "$dest/$rel_name" 2>/dev/null && ((count++))
        elif [[ "$mode" == "M" ]]; then
            mv -- "$src" "$dest/$rel_name" 2>/dev/null && ((count++))
        fi
    done

    [[ "$mode" == "M" ]] && unmark_all
    index_dir "$CURRENT_DIR"
    show_message "Processed $count items."
}

show_info() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    disable_input_mode
    clear
    echo -e "\033[1mFile Info\033[0m"
    ls -ldh "$src"
    echo
    file "$src"
    echo
    stat "$src" 2>/dev/null
    echo
    read -rp "Press Enter..."
    enable_input_mode
}

show_help() {
    disable_input_mode
    clear
    cat <<EOF
BASH COMMANDER HELP
-------------------
Arrows : Navigation
Enter  : Open Directory / File
Space  : Toggle Mark
c      : Copy current file to clipboard
x      : Cut current file to clipboard
v      : Paste clipboard to current dir
d      : Delete file
r      : Rename file
n      : New file/directory
i      : Info
p      : Preview (cat/less)
u      : Unmark all

C      : Copy ALL MARKED to...
M      : Move ALL MARKED to...
D      : Delete ALL MARKED
q      : Quit

Favorites are stored in $DEST_FAV_FILE
EOF
    read -rp "Press Enter..."
    enable_input_mode
}

# ------- Main Loop -------

enable_input_mode
index_dir "$CURRENT_DIR"

while true; do
    draw_page
    
    # Read 1 byte
    IFS= read -rsn1 key
    
    # Handle Escape Sequences (Arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.01 rest || rest=""
        key+="$rest"
        case "$key" in
            $'\x1b[A') # Up
                if (( CURSOR_POS > 0 )); then ((CURSOR_POS--));
                elif (( CURRENT_PAGE > 0 )); then ((CURRENT_PAGE--)); CURSOR_POS=$((FILES_PER_PAGE-1)); fi
                ;;
            $'\x1b[B') # Down
                files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                if (( files_on_page > FILES_PER_PAGE )); then files_on_page=$FILES_PER_PAGE; fi
                if (( CURSOR_POS < files_on_page - 1 )); then ((CURSOR_POS++));
                elif (( CURRENT_PAGE < TOTAL_PAGES - 1 )); then ((CURRENT_PAGE++)); CURSOR_POS=0; fi
                ;;
            $'\x1b[D') go_up ;;    # Left
            $'\x1b[C') enter_item ;; # Right
        esac
        continue
    fi

    # Handle standard keys
    # Note: Enter often comes as carriage return \r in raw mode, or newline
    if [[ "$key" == "" || "$key" == $'\r' || "$key" == $'\n' ]]; then
        enter_item
        continue
    fi

    case "$key" in
        q) break ;;
        ' ') 
            sel="$(get_selected_path)"
            [[ -n "$sel" ]] && toggle_mark "$sel"
            ;;
        u) unmark_all ;;
        c) clipboard_action "copy" ;;
        x) clipboard_action "cut" ;;
        v) paste_action ;;
        d) delete_file ;;
        r) rename_file ;;
        n) create_new ;;
        i) show_info ;;
        p) preview_file ;;
        h) show_help ;;
        C) process_marked "C" ;;
        M) process_marked "M" ;;
        D) process_marked "D" ;;
        g) CURRENT_PAGE=0; CURSOR_POS=0 ;;
    esac
done

cleanup_exit
