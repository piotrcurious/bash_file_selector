#!/usr/bin/env bash
# ==============================================================================
# BASH Commander - Enhanced File Manager
# Version: 3.0 (Improved & Optimized)
# ==============================================================================

set -euo pipefail

# ------- Configuration -------
readonly FILES_PER_PAGE=20
readonly DEST_FAV_FILE="${HOME}/.commander_dest_favs"
readonly MARKS_FILE="$(mktemp --tmpdir commander_marks.XXXXXX)"
readonly CLIPBOARD_FILE="$(mktemp --tmpdir commander_clipboard.XXXXXX)"
readonly FILES_CACHE="$(mktemp --tmpdir commander_files.XXXXXX)"

# Globals
CURRENT_DIR="$(pwd)"
CURSOR_POS=0
CURRENT_PAGE=0
CLIPBOARD_MODE=""
WRAP_WIDTH=80
TOTAL_FILES=0
TOTAL_PAGES=1

# Ensure config exists
mkdir -p "$(dirname "$DEST_FAV_FILE")"
touch "$DEST_FAV_FILE"

# ------- Terminal Setup / Cleanup -------

cleanup_exit() {
    stty sane 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    rm -f -- "$MARKS_FILE" "$CLIPBOARD_FILE" "$FILES_CACHE" 2>/dev/null || true
    clear
    exit "${1:-0}"
}
trap 'cleanup_exit' INT TERM EXIT

enable_input_mode() {
    stty -echo -icanon time 0 min 1 2>/dev/null
    tput civis 2>/dev/null || true
}

disable_input_mode() {
    stty sane 2>/dev/null
    tput cnorm 2>/dev/null || true
}

update_width() {
    WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)"
}
trap 'update_width' WINCH
update_width

# ------- Utilities -------

show_message() {
    local msg="$1"
    local duration="${2:-1.5}"
    local color="${3:-32}" # default green
    disable_input_mode
    tput cup $(($(tput lines)-1)) 0 2>/dev/null || true
    tput el 2>/dev/null || true
    echo -ne "\033[1;${color}m ${msg}\033[0m"
    sleep "$duration"
    enable_input_mode
}

show_error() {
    show_message "$1" "${2:-1.5}" "31"
}

# ------- Core Logic: Indexing -------

index_dir() {
    local dir="$1"
    
    # Write files to cache file instead of array (memory efficient)
    : > "$FILES_CACHE"
    
    # Use find with null delimiter for safe handling
    if ! find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | 
         sort -z | 
         tr '\0' '\n' > "$FILES_CACHE"; then
        show_error "Cannot read directory"
        return 1
    fi
    
    TOTAL_FILES=$(wc -l < "$FILES_CACHE")
    
    if (( TOTAL_FILES == 0 )); then
        TOTAL_PAGES=1
    else
        TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    fi

    # Bounds checking
    (( CURRENT_PAGE >= TOTAL_PAGES )) && CURRENT_PAGE=$((TOTAL_PAGES - 1))
    (( CURRENT_PAGE < 0 )) && CURRENT_PAGE=0
    
    # Ensure cursor is valid for the number of files on this page
    local files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
    (( files_on_page > FILES_PER_PAGE )) && files_on_page=$FILES_PER_PAGE
    
    if (( CURSOR_POS >= files_on_page )); then 
        CURSOR_POS=$(( files_on_page > 0 ? files_on_page - 1 : 0 ))
    fi
    (( CURSOR_POS < 0 )) && CURSOR_POS=0
}

get_selected_path() {
    (( TOTAL_FILES == 0 )) && return
    local index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    (( index < 1 || index > TOTAL_FILES )) && return
    sed -n "${index}p" "$FILES_CACHE"
}

# ------- Marks System -------

is_marked() {
    local path="$1"
    grep -Fxq -- "$path" "$MARKS_FILE" 2>/dev/null
}

toggle_mark() {
    local path="$1"
    local tmp="${MARKS_FILE}.tmp"
    
    if is_marked "$path"; then
        grep -Fxv -- "$path" "$MARKS_FILE" > "$tmp" 2>/dev/null || true
    else
        { cat "$MARKS_FILE" 2>/dev/null || true; printf '%s\n' "$path"; } > "$tmp"
    fi
    mv -f "$tmp" "$MARKS_FILE"
}

get_marked_count() {
    wc -l < "$MARKS_FILE" 2>/dev/null || echo 0
}

unmark_all() {
    : > "$MARKS_FILE"
    show_message "All marks cleared" 0.7
}

# ------- UI / Drawing -------

draw_page() {
    clear
    
    # Header
    printf "\033[1m\033[36m📁 BASH COMMANDER\033[0m - \033[32m%s\033[0m\n" "$CURRENT_DIR"
    printf "\033[2mFiles: %d | Page: %d/%d | Marked: %d\033[0m\n" \
        "$TOTAL_FILES" "$((CURRENT_PAGE + 1))" "$TOTAL_PAGES" "$(get_marked_count)"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    local start=$(( CURRENT_PAGE * FILES_PER_PAGE + 1 ))
    local end=$(( start + FILES_PER_PAGE - 1 ))
    (( end > TOTAL_FILES )) && end=$TOTAL_FILES

    if (( TOTAL_FILES == 0 )); then
        echo -e "   \033[2m(Empty directory)\033[0m"
    else
        # Stream through the relevant portion of the cache file
        sed -n "${start},${end}p" "$FILES_CACHE" | {
            local line_num=0
            while IFS= read -r f; do
                local fname
                fname="$(basename "$f")"
                local indicator="  "
                
                # Cursor logic
                if (( line_num == CURSOR_POS )); then
                    indicator="\033[1m\033[36m▶ "
                fi

                # Mark logic
                local mark_char=" "
                is_marked "$f" && mark_char="✓"

                # Decoration based on type
                local decoration="" suffix=""
                if [[ -L "$f" ]]; then
                    decoration="\033[1m\033[35m" # Magenta for symlinks
                    suffix=" → $(readlink "$f" 2>/dev/null || echo '?')"
                elif [[ -d "$f" ]]; then
                    decoration="\033[1m\033[34m" # Blue for dir
                    suffix="/"
                elif [[ -x "$f" ]]; then
                    decoration="\033[32m" # Green for executable
                    suffix="*"
                fi
                
                # Truncate long names
                local max_len=$((WRAP_WIDTH - 20))
                if (( ${#fname} > max_len )); then
                    fname="${fname:0:$((max_len-3))}..."
                fi
                
                printf "%b[%s] %b%s%s\033[0m\n" "$indicator" "$mark_char" "$decoration" "$fname" "$suffix"
                ((line_num++))
            done
        }
    fi

    # Padding
    local rows_used=$(( end - start + 1 ))
    (( rows_used < 0 )) && rows_used=0
    local remaining=$((FILES_PER_PAGE - rows_used))
    for (( k=0; k<remaining; k++ )); do echo; done

    echo "────────────────────────────────────────────────────────────────────────────────"
    
    # Clipboard status
    if [[ -s "$CLIPBOARD_FILE" ]]; then
        local clip_item
        clip_item=$(head -n 1 "$CLIPBOARD_FILE")
        printf "\033[34m📋 Clipboard [%s]: %s\033[0m\n" "$CLIPBOARD_MODE" "$(basename "$clip_item")"
    fi
    
    # Keybindings
    echo -e "\033[33m↑↓←→\033[0m Nav  \033[33mEnter\033[0m Open  \033[33mSpace\033[0m Mark  \033[33mc/x/v\033[0m Copy/Cut/Paste  \033[33md\033[0m Del  \033[33mr\033[0m Ren"
    echo -e "\033[33mC/M/D\033[0m Bulk Op  \033[33mn\033[0m New  \033[33mi\033[0m Info  \033[33mp\033[0m Preview  \033[33mh\033[0m Help  \033[33mq\033[0m Quit"
}

# ------- Destination Picker -------

choose_destination() {
    disable_input_mode
    local dest_dir=""
    
    while true; do
        clear
        echo -e "\033[1m\033[36m📂 Select Destination\033[0m"
        echo "────────────────────────────────────────────────────────────────"
        echo -e "\033[1mFavorites:\033[0m"
        
        local i=1
        if [[ -f "$DEST_FAV_FILE" && -s "$DEST_FAV_FILE" ]]; then
            while IFS= read -r fav; do
                printf "  \033[33m[%d]\033[0m %s\n" "$i" "$fav"
                ((i++))
            done < "$DEST_FAV_FILE"
        else
            echo "  (No favorites yet)"
        fi
        
        echo
        echo -e "\033[1mOptions:\033[0m"
        echo "  [b] Browse / Enter custom path"
        echo "  [a] Add current directory to favorites"
        echo "  [r] Remove a favorite"
        echo "  [q] Cancel"
        echo "  [1-9] Select favorite number"
        echo
        read -rp "Choice: " act

        case "$act" in
            q|Q) dest_dir=""; break ;;
            a|A) 
                if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then
                    echo "$CURRENT_DIR" >> "$DEST_FAV_FILE"
                    echo "✓ Added to favorites"
                    sleep 0.5
                else
                    echo "Already in favorites"
                    sleep 0.5
                fi
                ;;
            r|R)
                read -rp "Remove favorite number: " num
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    sed -i "${num}d" "$DEST_FAV_FILE" 2>/dev/null && echo "✓ Removed" || echo "✗ Invalid"
                    sleep 0.5
                fi
                ;;
            b|B)
                read -e -rp "Enter path (empty = current): " userpath
                dest_dir="${userpath:-$CURRENT_DIR}"
                if [[ ! -d "$dest_dir" ]]; then 
                    echo "✗ Invalid directory!"
                    sleep 1
                else
                    break
                fi
                ;;
            *)
                if [[ "$act" =~ ^[0-9]+$ ]]; then
                    dest_dir=$(sed -n "${act}p" "$DEST_FAV_FILE" 2>/dev/null)
                    [[ -n "$dest_dir" && -d "$dest_dir" ]] && break
                    echo "✗ Invalid selection"
                    sleep 0.5
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
    [[ -z "$path" || ! -e "$path" ]] && return

    if [[ -d "$path" ]]; then
        cd "$path" 2>/dev/null || { show_error "Cannot access directory"; return; }
        CURRENT_DIR="$PWD"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    else
        disable_input_mode
        if [[ -n "${EDITOR:-}" ]]; then
            "$EDITOR" "$path"
        elif command -v xdg-open &>/dev/null; then
            xdg-open "$path" &>/dev/null
        elif command -v open &>/dev/null; then
            open "$path" &>/dev/null
        else
            less "$path"
        fi
        enable_input_mode
    fi
}

go_up() {
    local parent
    parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        cd "$parent" 2>/dev/null || return
        CURRENT_DIR="$PWD"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    fi
}

preview_file() {
    local file
    file="$(get_selected_path)"
    [[ -z "$file" || ! -f "$file" ]] && return

    disable_input_mode
    clear
    echo -e "\033[1mPreview: $(basename "$file")\033[0m"
    echo "────────────────────────────────────────────────────────────────"
    
    if command -v bat &>/dev/null; then
        bat --style=plain --paging=always --color=always "$file"
    elif command -v less &>/dev/null; then
        less "$file"
    else
        cat "$file"
    fi
    
    read -rsp "Press any key to continue..." -n1
    enable_input_mode
}

rename_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return

    disable_input_mode
    tput cnorm 2>/dev/null || true
    
    local fname
    fname="$(basename "$src")"
    
    echo -e "\n\033[1mRename:\033[0m $fname"
    read -r -e -i "$fname" -p "New name: " newname
    
    if [[ -n "$newname" && "$newname" != "$fname" ]]; then
        local dest="$(dirname "$src")/$newname"
        if [[ -e "$dest" ]]; then
            echo "✗ Destination already exists!"
            sleep 1
        elif mv -n "$src" "$dest" 2>/dev/null; then
            show_message "✓ Renamed" 0.7
        else
            show_error "✗ Rename failed"
        fi
    fi
    
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

delete_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return

    disable_input_mode
    local fname
    fname="$(basename "$src")"
    
    read -rp "Delete '$fname'? [y/N] " ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
        if rm -rf "$src" 2>/dev/null; then
            show_message "✓ Deleted" 0.7
        else
            show_error "✗ Delete failed"
        fi
    fi
    
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

create_new() {
    disable_input_mode
    echo
    read -rp "Create [f]ile or [d]irectory? " choice
    
    case "$choice" in
        f|F)
            read -rp "Filename: " name
            if [[ -n "$name" ]]; then
                if touch "$CURRENT_DIR/$name" 2>/dev/null; then
                    show_message "✓ File created" 0.7
                else
                    show_error "✗ Failed to create file"
                fi
            fi
            ;;
        d|D)
            read -rp "Directory name: " name
            if [[ -n "$name" ]]; then
                if mkdir -p "$CURRENT_DIR/$name" 2>/dev/null; then
                    show_message "✓ Directory created" 0.7
                else
                    show_error "✗ Failed to create directory"
                fi
            fi
            ;;
    esac
    
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

clipboard_action() {
    local action="$1"
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return

    echo "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="$action"
    show_message "✓ Selected for $action" 0.7
}

paste_action() {
    [[ ! -s "$CLIPBOARD_FILE" ]] && { show_error "Clipboard empty"; return; }
    
    local src
    src="$(cat "$CLIPBOARD_FILE")"
    [[ ! -e "$src" ]] && { show_error "Source no longer exists"; return; }

    local base
    base="$(basename "$src")"
    local dest="$CURRENT_DIR/$base"

    if [[ -e "$dest" ]]; then
        show_error "Destination already exists!"
        return
    fi

    case "$CLIPBOARD_MODE" in
        copy)
            if cp -r "$src" "$dest" 2>/dev/null; then
                show_message "✓ Copied"
            else
                show_error "✗ Copy failed"
            fi
            ;;
        cut)
            if mv "$src" "$dest" 2>/dev/null; then
                show_message "✓ Moved"
                : > "$CLIPBOARD_FILE"
                CLIPBOARD_MODE=""
            else
                show_error "✗ Move failed"
            fi
            ;;
    esac
    
    index_dir "$CURRENT_DIR"
}

# ------- Multi-File Operations -------

process_marked() {
    local mode="$1"
    local count
    count=$(get_marked_count)
    
    (( count == 0 )) && { show_error "No items marked"; return; }

    if [[ "$mode" == "D" ]]; then
        disable_input_mode
        read -rp "Delete $count marked items? [y/N] " ans
        enable_input_mode
        
        if [[ "$ans" =~ ^[yY]$ ]]; then
            local deleted=0
            while IFS= read -r f; do
                rm -rf "$f" 2>/dev/null && ((deleted++))
            done < "$MARKS_FILE"
            unmark_all
            index_dir "$CURRENT_DIR"
            show_message "✓ Deleted $deleted items"
        fi
        return
    fi

    local dest
    dest="$(choose_destination)"
    [[ -z "$dest" || ! -d "$dest" ]] && return

    local success=0 failed=0
    while IFS= read -r src; do
        [[ ! -e "$src" ]] && { ((failed++)); continue; }
        
        local rel_name
        rel_name="$(basename "$src")"
        local target="$dest/$rel_name"
        
        [[ -e "$target" ]] && { ((failed++)); continue; }
        
        case "$mode" in
            C) cp -r -- "$src" "$target" 2>/dev/null && ((success++)) || ((failed++)) ;;
            M) mv -- "$src" "$target" 2>/dev/null && ((success++)) || ((failed++)) ;;
        esac
    done < "$MARKS_FILE"

    [[ "$mode" == "M" ]] && unmark_all
    index_dir "$CURRENT_DIR"
    
    local msg="✓ $success succeeded"
    (( failed > 0 )) && msg="$msg, $failed failed"
    show_message "$msg"
}

show_info() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    
    disable_input_mode
    clear
    echo -e "\033[1m\033[36mFile Information\033[0m"
    echo "────────────────────────────────────────────────────────────────"
    ls -ldh "$src" 2>/dev/null
    echo
    file "$src" 2>/dev/null
    echo
    stat "$src" 2>/dev/null
    echo "────────────────────────────────────────────────────────────────"
    read -rsp "Press any key to continue..." -n1
    enable_input_mode
}

show_help() {
    disable_input_mode
    clear
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                          BASH COMMANDER HELP                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

NAVIGATION
  ↑/↓     : Move cursor up/down
  ←       : Go to parent directory
  →/Enter : Open directory or file
  g       : Go to first item on page

FILE OPERATIONS
  Space   : Toggle mark on current file
  u       : Unmark all files
  c       : Copy current file to clipboard
  x       : Cut current file to clipboard
  v       : Paste clipboard contents
  d       : Delete current file
  r       : Rename current file
  n       : Create new file or directory

BULK OPERATIONS (on marked files)
  C       : Copy all marked files to destination
  M       : Move all marked files to destination
  D       : Delete all marked files

INFORMATION & PREVIEW
  i       : Show detailed file information
  p       : Preview file contents

OTHER
  h       : Show this help
  q       : Quit

NOTES
  • Favorites are stored in: ~/.commander_dest_favs
  • Marked files persist until cleared or moved
  • Symlinks are shown in magenta with → target
  • Use temporary files for memory efficiency

EOF
    read -rsp "Press any key to continue..." -n1
    enable_input_mode
}

# ------- Main Loop -------

enable_input_mode
index_dir "$CURRENT_DIR"

while true; do
    draw_page
    
    IFS= read -rsn1 key
    
    # Handle Escape Sequences (Arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.01 rest || rest=""
        key+="$rest"
        case "$key" in
            $'\x1b[A') # Up
                if (( CURSOR_POS > 0 )); then
                    ((CURSOR_POS--))
                elif (( CURRENT_PAGE > 0 )); then
                    ((CURRENT_PAGE--))
                    CURSOR_POS=$((FILES_PER_PAGE - 1))
                    local files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                    (( files_on_page < FILES_PER_PAGE )) && CURSOR_POS=$((files_on_page - 1))
                fi
                ;;
            $'\x1b[B') # Down
                local files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                (( files_on_page > FILES_PER_PAGE )) && files_on_page=$FILES_PER_PAGE
                if (( CURSOR_POS < files_on_page - 1 )); then
                    ((CURSOR_POS++))
                elif (( CURRENT_PAGE < TOTAL_PAGES - 1 )); then
                    ((CURRENT_PAGE++))
                    CURSOR_POS=0
                fi
                ;;
            $'\x1b[D') go_up ;;
            $'\x1b[C') enter_item ;;
        esac
        continue
    fi

    # Handle standard keys
    [[ "$key" == "" || "$key" == $'\r' || "$key" == $'\n' ]] && { enter_item; continue; }

    case "$key" in
        q|Q) break ;;
        ' ') 
            sel="$(get_selected_path)"
            [[ -n "$sel" ]] && toggle_mark "$sel"
            ;;
        u|U) unmark_all ;;
        c) clipboard_action "copy" ;;
        x) clipboard_action "cut" ;;
        v) paste_action ;;
        d) delete_file ;;
        r) rename_file ;;
        n) create_new ;;
        i) show_info ;;
        p) preview_file ;;
        h|H) show_help ;;
        C) process_marked "C" ;;
        M) process_marked "M" ;;
        D) process_marked "D" ;;
        g|G) CURRENT_PAGE=0; CURSOR_POS=0 ;;
    esac
done

cleanup_exit 0
