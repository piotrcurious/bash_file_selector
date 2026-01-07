#!/usr/bin/env bash
# ==============================================================================
# BASH Commander - Enhanced File Manager
# Version: 3.1 (Terminal State & Buffer Fixed)
# ==============================================================================

set -uo pipefail

# ------- Configuration -------
readonly FILES_PER_PAGE=20
readonly DEST_FAV_FILE="${HOME}/.commander_dest_favs"
readonly MARKS_FILE="$(mktemp --tmpdir commander_marks.XXXXXX)"
readonly CLIPBOARD_FILE="$(mktemp --tmpdir commander_clipboard.XXXXXX)"
readonly FILES_CACHE="$(mktemp --tmpdir commander_files.XXXXXX)"

# Capture initial terminal state to restore later (Fixes Backspace/^H issues)
readonly INITIAL_STTY_SETTINGS=$(stty -g 2>/dev/null || echo "")

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
    # Restore original terminal settings
    if [[ -n "$INITIAL_STTY_SETTINGS" ]]; then
        stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true
    fi
    
    # Restore cursor, show scrollback buffer, and clean up files
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    rm -f -- "$MARKS_FILE" "$CLIPBOARD_FILE" "$FILES_CACHE" 2>/dev/null || true
    
    # Clear and exit
    exit "${1:-0}"
}

# Trap signals for clean exit
trap 'cleanup_exit' INT TERM EXIT

enable_input_mode() {
    # -echo: don't print typed chars, -icanon: read char-by-char
    stty -echo -icanon time 0 min 1 2>/dev/null || true
    tput civis 2>/dev/null || true
}

disable_input_mode() {
    # Return to the state the user had before launching
    if [[ -n "$INITIAL_STTY_SETTINGS" ]]; then
        stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
    tput cnorm 2>/dev/null || true
}

update_width() {
    WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)"
}
trap 'update_width' WINCH

# Init Terminal
tput smcup 2>/dev/null || true # Use alternate screen buffer
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
    : > "$FILES_CACHE"

    if ! find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null |
         sort -z 2>/dev/null |
         tr '\0' '\n' > "$FILES_CACHE"; then
        show_error "Cannot read directory"
        return 1
    fi

    TOTAL_FILES=$(wc -l < "$FILES_CACHE" 2>/dev/null || echo 0)

    if (( TOTAL_FILES == 0 )); then
        TOTAL_PAGES=1
    else
        TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    fi

    (( CURRENT_PAGE >= TOTAL_PAGES )) && CURRENT_PAGE=$((TOTAL_PAGES - 1))
    (( CURRENT_PAGE < 0 )) && CURRENT_PAGE=0

    local files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
    (( files_on_page > FILES_PER_PAGE )) && files_on_page=$FILES_PER_PAGE

    if (( CURSOR_POS >= files_on_page )); then
        CURSOR_POS=$(( files_on_page > 0 ? files_on_page - 1 : 0 ))
    fi
    (( CURSOR_POS < 0 )) && CURSOR_POS=0
}

get_selected_path() {
    (( TOTAL_FILES == 0 )) && { echo ""; return; }
    local index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    (( index < 1 || index > TOTAL_FILES )) && { echo ""; return; }
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
        sed -n "${start},${end}p" "$FILES_CACHE" | {
            local line_num=0
            while IFS= read -r f; do
                local fname="$(basename "$f")"
                local indicator="  "
                (( line_num == CURSOR_POS )) && indicator="\033[1m\033[36m▶ "
                local mark_char=" "
                is_marked "$f" && mark_char="✓"

                local decoration="" suffix=""
                if [[ -L "$f" ]]; then
                    decoration="\033[1m\033[35m"
                    suffix=" → $(readlink "$f" 2>/dev/null || echo '?')"
                elif [[ -d "$f" ]]; then
                    decoration="\033[1m\033[34m"
                    suffix="/"
                elif [[ -x "$f" ]]; then
                    decoration="\033[32m"
                    suffix="*"
                fi

                local max_len=$((WRAP_WIDTH - 20))
                (( ${#fname} > max_len )) && fname="${fname:0:$((max_len-3))}..."
                printf "%b[%s] %b%s%s\033[0m\n" "$indicator" "$mark_char" "$decoration" "$fname" "$suffix"
                ((line_num++))
            done
        }
    fi

    local rows_used=$(( end - start + 1 ))
    (( rows_used < 0 )) && rows_used=0
    for (( k=0; k<(FILES_PER_PAGE - rows_used); k++ )); do echo; done

    echo "────────────────────────────────────────────────────────────────────────────────"
    if [[ -s "$CLIPBOARD_FILE" ]]; then
        local clip_item=$(head -n 1 "$CLIPBOARD_FILE")
        printf "\033[34m📋 Clipboard [%s]: %s\033[0m\n" "$CLIPBOARD_MODE" "$(basename "$clip_item")"
    fi
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
        echo -e "\033[1mOptions:\033[0m [b] Browse | [a] Add Curr | [r] Rem Fav | [q] Cancel | [1-9] Select Fav"
        read -rp "Choice: " act || act=""
        case "$act" in
            q|Q) dest_dir=""; break ;;
            a|A)
                if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then
                    echo "$CURRENT_DIR" >> "$DEST_FAV_FILE"
                    echo "✓ Added"
                fi
                sleep 0.5 ;;
            r|R)
                read -rp "Remove favorite number: " num || num=""
                [[ "$num" =~ ^[0-9]+$ ]] && sed -i "${num}d" "$DEST_FAV_FILE" 2>/dev/null
                sleep 0.5 ;;
            b|B)
                read -e -rp "Enter path (empty = current): " userpath || userpath=""
                dest_dir="${userpath:-$CURRENT_DIR}"
                [[ -d "$dest_dir" ]] && break || { echo "✗ Invalid dir"; sleep 1; } ;;
            *)
                if [[ "$act" =~ ^[0-9]+$ ]]; then
                    dest_dir=$(sed -n "${act}p" "$DEST_FAV_FILE" 2>/dev/null)
                    [[ -n "$dest_dir" && -d "$dest_dir" ]] && break
                fi ;;
        esac
    done
    enable_input_mode
    echo "$dest_dir"
}

# ------- Actions -------

enter_item() {
    local path="$(get_selected_path)"
    [[ -z "$path" || ! -e "$path" ]] && return
    if [[ -d "$path" ]]; then
        cd "$path" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    else
        disable_input_mode
        if [[ -n "${EDITOR:-}" ]]; then "$EDITOR" "$path";
        elif command -v xdg-open &>/dev/null; then xdg-open "$path" &>/dev/null || true;
        else less "$path"; fi
        enable_input_mode
    fi
}

go_up() {
    local parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        cd "$parent" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    fi
}

preview_file() {
    local file="$(get_selected_path)"
    [[ -z "$file" || ! -f "$file" ]] && return
    disable_input_mode
    clear
    echo -e "\033[1mPreview: $(basename "$file")\033[0m\n────────────────────────────────────────────────────────────────"
    if command -v bat &>/dev/null; then bat --style=plain --paging=always --color=always "$file" || true;
    else less "$file" || true; fi
    read -rsp "Press any key to continue..." -n1 || true
    enable_input_mode
}

rename_file() {
    local src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    local fname="$(basename "$src")"
    echo -e "\n\033[1mRename:\033[0m $fname"
    read -r -e -i "$fname" -p "New name: " newname || newname=""
    if [[ -n "$newname" && "$newname" != "$fname" ]]; then
        mv -n "$src" "$(dirname "$src")/$newname" 2>/dev/null && show_message "✓ Renamed" 0.7 || show_error "✗ Failed"
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

delete_file() {
    local src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    read -rp "Delete '$(basename "$src")'? [y/N] " ans || ans="n"
    [[ "$ans" =~ ^[yY]$ ]] && { rm -rf "$src" 2>/dev/null && show_message "✓ Deleted" 0.7 || show_error "✗ Failed"; }
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

create_new() {
    disable_input_mode
    read -rp "Create [f]ile or [d]irectory? " choice || choice=""
    read -rp "Name: " name || name=""
    if [[ -n "$name" ]]; then
        case "$choice" in
            f|F) touch "$CURRENT_DIR/$name" 2>/dev/null && show_message "✓ Created" 0.7 || show_error "✗ Failed" ;;
            d|D) mkdir -p "$CURRENT_DIR/$name" 2>/dev/null && show_message "✓ Created" 0.7 || show_error "✗ Failed" ;;
        esac
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

clipboard_action() {
    local src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    echo "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="$1"
    show_message "✓ Selected for $1" 0.7
}

paste_action() {
    [[ ! -s "$CLIPBOARD_FILE" ]] && { show_error "Clipboard empty"; return; }
    local src=$(cat "$CLIPBOARD_FILE")
    local dest="$CURRENT_DIR/$(basename "$src")"
    [[ -e "$dest" ]] && { show_error "Exists!"; return; }
    case "$CLIPBOARD_MODE" in
        copy) cp -r "$src" "$dest" 2>/dev/null && show_message "✓ Copied" || show_error "✗ Failed" ;;
        cut) mv "$src" "$dest" 2>/dev/null && { show_message "✓ Moved"; : > "$CLIPBOARD_FILE"; CLIPBOARD_MODE=""; } || show_error "✗ Failed" ;;
    esac
    index_dir "$CURRENT_DIR"
}

process_marked() {
    local mode="$1"
    local count=$(get_marked_count)
    (( count == 0 )) && { show_error "No items marked"; return; }
    if [[ "$mode" == "D" ]]; then
        disable_input_mode
        read -rp "Delete $count items? [y/N] " ans
        enable_input_mode
        if [[ "$ans" =~ ^[yY]$ ]]; then
            while IFS= read -r f; do rm -rf "$f" 2>/dev/null; done < "$MARKS_FILE"
            unmark_all; index_dir "$CURRENT_DIR"; show_message "✓ Done"
        fi
        return
    fi
    local dest="$(choose_destination)"
    [[ -z "$dest" || ! -d "$dest" ]] && return
    while IFS= read -r src; do
        [[ ! -e "$src" ]] && continue
        case "$mode" in
            C) cp -r -- "$src" "$dest/" 2>/dev/null ;;
            M) mv -- "$src" "$dest/" 2>/dev/null ;;
        esac
    done < "$MARKS_FILE"
    [[ "$mode" == "M" ]] && unmark_all
    index_dir "$CURRENT_DIR"; show_message "✓ Bulk operation complete"
}

show_info() {
    local src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    clear
    echo -e "\033[1m\033[36mFile Info\033[0m\n────────────────────────────────────────────────────────────────"
    ls -ldh "$src" 2>/dev/null; echo; file "$src" 2>/dev/null; echo; stat "$src" 2>/dev/null
    read -rsp "\nPress any key..." -n1 || true
    enable_input_mode
}

show_help() {
    disable_input_mode
    clear
    cat <<'EOF'
BASH COMMANDER HELP
Navigation: Arrows, Enter (Open), Back/Left (Up)
Marks: Space (Toggle), u (Clear All)
Single: c (Copy), x (Cut), v (Paste), d (Delete), r (Rename), n (New)
Bulk: C (Copy Marked), M (Move Marked), D (Delete Marked)
Other: i (Info), p (Preview), h (Help), q (Quit)
EOF
    read -rsp "Press any key..." -n1 || true
    enable_input_mode
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
                if (( CURSOR_POS > 0 )); then ((CURSOR_POS--))
                elif (( CURRENT_PAGE > 0 )); then ((CURRENT_PAGE--)); CURSOR_POS=$((FILES_PER_PAGE - 1)); fi ;;
            $'\x1b[B') # Down
                files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                (( files_on_page > FILES_PER_PAGE )) && files_on_page=$FILES_PER_PAGE
                if (( CURSOR_POS < files_on_page - 1 )); then ((CURSOR_POS++))
                elif (( CURRENT_PAGE < TOTAL_PAGES - 1 )); then ((CURRENT_PAGE++)); CURSOR_POS=0; fi ;;
            $'\x1b[D') go_up ;;
            $'\x1b[C') enter_item ;;
        esac
        continue
    fi

    [[ "$key" == "" || "$key" == $'\r' || "$key" == $'\n' ]] && { enter_item; continue; }
    case "$key" in
        q|Q) break ;;
        ' ') sel="$(get_selected_path)"; [[ -n "$sel" ]] && toggle_mark "$sel" ;;
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
