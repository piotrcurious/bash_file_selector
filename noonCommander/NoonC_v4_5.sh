#!/usr/bin/env bash
# ==============================================================================
# BASH Commander - Enhanced File Manager
# Version: 3.7 (Interactive clipboard for single + multiple (marked) items)
# - copy/cut (c/x) selects one item or all marked items
# - navigate to destination and press v to paste
# - preserves previous fixes: no subshell leaks in rendering, safe arithmetic
# ==============================================================================

set -uo pipefail

# ------- Configuration -------
EDITOR=leafpad
readonly FILES_PER_PAGE=20
readonly DEST_FAV_FILE="${HOME}/.commander_dest_favs"
readonly MARKS_FILE="$(mktemp --tmpdir commander_marks.XXXXXX)"
readonly CLIPBOARD_FILE="$(mktemp --tmpdir commander_clipboard.XXXXXX)"
readonly FILES_CACHE="$(mktemp --tmpdir commander_files.XXXXXX)"

# Capture initial terminal state
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
    trap - INT TERM EXIT
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    if [[ -n "$INITIAL_STTY_SETTINGS" ]]; then
        stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true
    fi
    rm -f -- "$MARKS_FILE" "$CLIPBOARD_FILE" "$FILES_CACHE" 2>/dev/null || true
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

update_width() {
    WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)"
}
trap 'update_width' WINCH

# Start UI
tput smcup 2>/dev/null || true
update_width

# ------- Utilities -------

show_message() {
    local msg="$1"
    local duration="${2:-1.2}"
    local color="${3:-32}"
    tput cup "$(($(tput lines) - 1))" 0 2>/dev/null || true
    tput el 2>/dev/null || true
    echo -ne "\033[1;${color}m ${msg}\033[0m"
    sleep "$duration"
}

show_error() {
    show_message "$1" "${2:-1.5}" "31"
}

# ------- Core Logic: Indexing -------

index_dir() {
    local dir="$1"
    : > "$FILES_CACHE"
    if find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z 2>/dev/null | tr '\0' '\n' > "$FILES_CACHE"; then
        :
    else
        find "$dir" -maxdepth 1 -mindepth 1 -printf "%y %p\n" 2>/dev/null \
            | sort -k1,1r -k2 \
            | cut -d' ' -f2- > "$FILES_CACHE"
    fi

    TOTAL_FILES=$(wc -l < "$FILES_CACHE" 2>/dev/null || echo 0)
    TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    if (( TOTAL_PAGES < 1 )); then TOTAL_PAGES=1; fi

    if (( CURRENT_PAGE >= TOTAL_PAGES )); then CURRENT_PAGE=$((TOTAL_PAGES - 1)); fi
    if (( CURRENT_PAGE < 0 )); then CURRENT_PAGE=0; fi

    # keep cursor inside available items on the page
    local items_on_page=$(( TOTAL_FILES - CURRENT_PAGE * FILES_PER_PAGE ))
    if (( items_on_page > FILES_PER_PAGE )); then items_on_page=$FILES_PER_PAGE; fi
    if (( items_on_page < 1 )); then CURSOR_POS=0
    elif (( CURSOR_POS >= items_on_page )); then CURSOR_POS=$((items_on_page - 1)); fi
}

get_selected_path() {
    if (( TOTAL_FILES == 0 )); then
        echo ""
        return
    fi
    local index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS + 1 ))
    sed -n "${index}p" "$FILES_CACHE"
}

# ------- Marks System -------

is_marked() {
    local path="$1"
    [[ ! -s "$MARKS_FILE" ]] && return 1
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

mark_all_in_dir() {
    cat "$FILES_CACHE" >> "$MARKS_FILE" 2>/dev/null || true
    if command -v sort >/dev/null 2>&1; then
        sort -u "$MARKS_FILE" -o "$MARKS_FILE" 2>/dev/null || true
    fi
    show_message "Marked all items" 0.7
}

unmark_all() {
    : > "$MARKS_FILE"
    show_message "All marks cleared" 0.7
}

get_marked_count() {
    wc -l < "$MARKS_FILE" 2>/dev/null || echo 0
}

# ------- UI / Drawing -------

draw_page() {
    tput clear
    tput cup 0 0
    printf "\033[1m\033[36m📁 BASH COMMANDER\033[0m - \033[32m%s\033[0m\n" "$CURRENT_DIR"
    printf "\033[2mFiles: %d | Page: %d/%d | Marked: %d\033[0m\n" \
        "$TOTAL_FILES" "$((CURRENT_PAGE + 1))" "$TOTAL_PAGES" "$(get_marked_count)"
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
            if [ "$line_num" -eq "$CURSOR_POS" ]; then
                indicator="\033[1m\033[36m▶ "
            fi
            local mark_char=" "
            if is_marked "$f"; then mark_char="✓"; fi

            local decoration="" suffix=""
            if [[ -L "$f" ]]; then
                decoration="\033[1m\033[35m"; suffix=" → $(readlink "$f" 2>/dev/null || echo '?')"
            elif [[ -d "$f" ]]; then
                decoration="\033[1m\033[34m"; suffix="/"
            elif [[ -x "$f" ]]; then
                decoration="\033[32m"; suffix="*"
            fi

            local max_len=$((WRAP_WIDTH - 25))
            if (( ${#fname} > max_len )); then fname="${fname:0:$((max_len-3))}..."; fi
            printf "%b[%s] %b%s%s\033[0m\n" "$indicator" "$mark_char" "$decoration" "$fname" "$suffix"

            line_num=$((line_num + 1))
        done < <(sed -n "${start},${end}p" "$FILES_CACHE")
    fi

    local rows_used=$(( end - start + 1 ))
    if (( rows_used < 0 )); then rows_used=0; fi
    for (( k=0; k < (FILES_PER_PAGE - rows_used); k++ )); do echo; done

    echo "────────────────────────────────────────────────────────────────────────────────"

    # show clipboard summary (single or multiple)
    if [[ -s "$CLIPBOARD_FILE" ]]; then
        local clip_count
        clip_count=$(wc -l < "$CLIPBOARD_FILE" 2>/dev/null || echo 0)
        if (( clip_count == 1 )); then
            local clip_item
            clip_item=$(head -n 1 "$CLIPBOARD_FILE")
            printf "\033[34m📋 Clipboard [%s]: %s\033[0m\n" "$CLIPBOARD_MODE" "$(basename "$clip_item")"
        else
            printf "\033[34m📋 Clipboard [%s]: %d items\033[0m\n" "$CLIPBOARD_MODE" "$clip_count"
        fi
    fi

    echo -e "\033[33m↑↓←→\033[0m Nav  \033[33mEnter\033[0m Open  \033[33mSpace\033[0m Mark  \033[33mA\033[0m All  \033[33mu\033[0m Clear"
    echo -e "\033[33mC/M/D\033[0m Bulk Op  \033[33mc/x/v\033[0m C/X/V  \033[33md/r\033[0m Del/Ren  \033[33mn\033[0m New  \033[33mi\033[0m Info"
}

# ------- Destination Picker (unchanged) -------

choose_destination() {
    local context_title="${1:-Select Destination}"
    local dest_dir=""

    disable_input_mode

    while true; do
        {
            tput clear
            tput cup 0 0
            echo -e "\033[1;36m📂 $context_title\033[0m"
            echo "────────────────────────────────────────────────────────────────"
            echo -e "\033[1mFavorites:\033[0m"
            local i=1
            if [[ -f "$DEST_FAV_FILE" && -s "$DEST_FAV_FILE" ]]; then
                while IFS= read -r fav; do
                    printf "  \033[33m[%d]\033[0m %s\n" "$i" "$fav"
                    i=$((i + 1))
                done < "$DEST_FAV_FILE"
            else
                echo "  (No favorites yet)"
            fi
            echo
            echo -e "\033[1mOptions:\033[0m"
            echo -e " [b] Browse Manual Path"
            echo -e " [a] Add Current Dir to Favs"
            echo -e " [r] Remove a Favorite"
            echo -e " [q] Cancel Operation"
            echo "────────────────────────────────────────────────────────────────"
            echo -n "Choice (1-9 or key): "
        } >&2

        read -r act || act=""

        case "$act" in
            q|Q) dest_dir=""; break ;;
            a|A)
                if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then
                    echo "$CURRENT_DIR" >> "$DEST_FAV_FILE"
                    echo "✓ Added $CURRENT_DIR" >&2
                fi
                sleep 0.8 ;;
            r|R)
                echo -n "Remove favorite number: " >&2
                read -r num || num=""
                if [[ "$num" =~ ^[0-9]+$ ]]; then sed -i "${num}d" "$DEST_FAV_FILE" 2>/dev/null || true; fi
                sleep 0.5 ;;
            b|B)
                echo -n "Enter path (empty = current): " >&2
                read -r -e userpath || userpath=""
                dest_dir="${userpath:-$CURRENT_DIR}"
                if [[ -d "$dest_dir" ]]; then
                    break
                else
                    echo "✗ Invalid directory: $dest_dir" >&2
                    sleep 1
                fi ;;
            *)
                if [[ "$act" =~ ^[0-9]+$ ]]; then
                    dest_dir=$(sed -n "${act}p" "$DEST_FAV_FILE" 2>/dev/null)
                    if [[ -n "$dest_dir" && -d "$dest_dir" ]]; then
                        break
                    fi
                    echo "✗ Invalid selection" >&2
                    sleep 0.5
                fi ;;
        esac
    done

    enable_input_mode
    echo "$dest_dir"
}

# ------- Actions & Clipboard behavior (NEW: support multiple items) -------

# clipboard_action now copies either the single selected item OR all marked items
clipboard_action() {
    local mode="$1"   # "copy" or "cut"
    local marked_count
    marked_count=$(get_marked_count)

    # prepare clipboard file
    : > "$CLIPBOARD_FILE"

    if (( marked_count > 0 )); then
        # copy marked list into clipboard file (preserve order)
        while IFS= read -r p; do
            printf '%s\n' "$p" >> "$CLIPBOARD_FILE"
        done < "$MARKS_FILE"
        CLIPBOARD_MODE="$mode"
        show_message "Selected ${marked_count} marked items for ${mode}. Navigate to destination and press v to paste" 1.2
        return
    fi

    # no marks: operate on selected item
    local src
    src="$(get_selected_path)" || src=""
    [[ -z "$src" || ! -e "$src" ]] && { show_error "No file selected"; return; }
    printf '%s\n' "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="$mode"
    show_message "Selected '$(basename "$src")' for ${mode}. Navigate to destination and press v to paste" 1.0
}

# paste_action iterates over possibly multiple items in clipboard
paste_action() {
    if [[ ! -s "$CLIPBOARD_FILE" ]]; then
        show_error "Clipboard empty"
        return
    fi

    local any_done=0
    local failures=0
    local items=0
    items=$(wc -l < "$CLIPBOARD_FILE" 2>/dev/null || echo 0)
    if (( items == 0 )); then show_error "Clipboard empty"; return; fi

    # operate atomically per-item; for cut, clear clipboard after success
    local tmp_success=0
    while IFS= read -r src; do
        [[ -z "$src" || ! -e "$src" ]] && { failures=$((failures+1)); continue; }
        local base
        base="$(basename "$src")"
        local dest="$CURRENT_DIR/$base"
        if [[ -e "$dest" ]]; then
            show_error "Exists: $base"
            failures=$((failures+1))
            continue
        fi

        case "$CLIPBOARD_MODE" in
            copy)
                if cp -r -- "$src" "$dest" 2>/dev/null; then any_done=1; else failures=$((failures+1)); fi
                ;;
            cut)
                if mv -- "$src" "$dest" 2>/dev/null; then any_done=1; tmp_success=1; else failures=$((failures+1)); fi
                ;;
            *)
                show_error "Unknown clipboard mode"; failures=$((failures+1)) ;;
        esac
    done < "$CLIPBOARD_FILE"

    if (( any_done )); then
        # if cut succeeded for at least one item, and no remaining items required,
        # we clear clipboard because the items were moved.
        if [[ "$CLIPBOARD_MODE" == "cut" && tmp_success -eq 1 ]]; then
            : > "$CLIPBOARD_FILE"
            CLIPBOARD_MODE=""
        fi
        index_dir "$CURRENT_DIR"
        if (( failures == 0 )); then
            show_message "✓ Pasted $items item(s)" 0.9
        else
            show_message "Partial paste: $((items - failures)) succeeded, $failures failed" 1.2
        fi
    else
        show_error "Paste failed"
    fi
}

# process_marked now simply selects marked items into clipboard (interactive flow)
process_marked() {
    local mode="$1"  # C | M | D
    local count
    count=$(get_marked_count)
    if (( count == 0 )); then show_error "No items marked"; return; fi

    if [[ "$mode" == "D" ]]; then
        disable_input_mode
        read -rp "Delete $count marked items? [y/N] " ans || ans="n"
        enable_input_mode
        if [[ "$ans" =~ ^[yY]$ ]]; then
            while IFS= read -r f; do rm -rf "$f" 2>/dev/null; done < "$MARKS_FILE"
            unmark_all; index_dir "$CURRENT_DIR"; show_message "✓ Bulk delete complete"
        fi
        return
    fi

    # For C/M we follow the interactive model: select and instruct user to navigate & paste
    if [[ "$mode" == "C" ]]; then
        clipboard_action "copy"
    elif [[ "$mode" == "M" ]]; then
        clipboard_action "cut"
    fi
}

# ------- Other actions (unchanged) -------

enter_item() {
    local path
    path="$(get_selected_path)"
    [[ -z "$path" || ! -e "$path" ]] && return
    if [[ -d "$path" ]]; then
        cd "$path" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    else
        disable_input_mode
        if [[ -n "${EDITOR:-}" ]]; then "$EDITOR" "$path"
        elif command -v xdg-open &>/dev/null; then xdg-open "$path" &>/dev/null || true
        else less "$path"; fi
        enable_input_mode
    fi
}

go_up() {
    local parent
    parent="$(dirname "$CURRENT_DIR")"
    if [[ "$parent" != "$CURRENT_DIR" ]]; then
        cd "$parent" 2>/dev/null && { CURRENT_DIR="$PWD"; CURRENT_PAGE=0; CURSOR_POS=0; index_dir "$CURRENT_DIR"; }
    fi
}

preview_file() {
    local file
    file="$(get_selected_path)"
    [[ -z "$file" || ! -f "$file" ]] && return
    disable_input_mode
    tput clear
    tput cup 0 0
    echo -e "\033[1mPreview: $(basename "$file")\033[0m\n────────────────────────────────────────────────────────────────"
    if command -v bat &>/dev/null; then bat --style=plain --paging=always --color=always "$file" || true
    else less "$file" || true; fi
    echo -n "Press any key to continue..."
    read -rsn1 || true
    enable_input_mode
}

rename_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    local fname
    fname="$(basename "$src")"
    echo -e "\n\033[1mRename:\033[0m $fname"
    read -r -e -p "New name: " newname || newname=""
    if [[ -n "$newname" && "$newname" != "$fname" ]]; then
        mv -n "$src" "$(dirname "$src")/$newname" 2>/dev/null && show_message "✓ Renamed" 0.7 || show_error "✗ Failed"
    fi
    enable_input_mode
    index_dir "$CURRENT_DIR"
}

delete_file() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    read -rp "Delete '$(basename "$src")'? [y/N] " ans || ans="n"
    if [[ "$ans" =~ ^[yY]$ ]]; then
        rm -rf "$src" 2>/dev/null && show_message "✓ Deleted" 0.7 || show_error "✗ Failed"
    fi
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

show_info() {
    local src
    src="$(get_selected_path)"
    [[ -z "$src" || ! -e "$src" ]] && return
    disable_input_mode
    tput clear
    tput cup 0 0
    echo -e "\033[1;36mFile Info\033[0m\n────────────────────────────────────────────────────────────────"
    ls -ldh "$src" 2>/dev/null; echo; file "$src" 2>/dev/null; echo; stat "$src" 2>/dev/null
    echo -ne "\nPress any key..."
    read -rsn1 || true
    enable_input_mode
}

show_help() {
    disable_input_mode
    tput clear
    tput cup 0 0
    cat <<'EOF'
BASH COMMANDER HELP
────────────────────────────────────────────────────────────────
Navigation:
  Arrows     : Move cursor / Change directory
  Enter      : Open file or enter directory
  Backspace  : Go to parent directory

Marking:
  Space      : Toggle mark on current item
  A          : Mark ALL items in current directory
  u          : Unmark ALL items

Single Operations:
  c / x      : Copy / Cut current item to internal clipboard (or on marked items)
  v          : Paste clipboard contents into the current directory
  d / r      : Delete / Rename current item
  n          : Create new file or directory

Bulk Operations (interactive):
  Mark items, then press c (copy) or x (cut). Navigate to destination and press v (paste).

System:
  i          : Detailed file info
  p          : Preview file (bat or less)
  q          : Quit Commander
────────────────────────────────────────────────────────────────
EOF
    echo -n "Press any key to return..."
    read -rsn1 || true
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
                if [ "$CURSOR_POS" -gt 0 ]; then
                    CURSOR_POS=$((CURSOR_POS - 1))
                elif [ "$CURRENT_PAGE" -gt 0 ]; then
                    CURRENT_PAGE=$((CURRENT_PAGE - 1))
                    CURSOR_POS=$((FILES_PER_PAGE - 1))
                fi
                ;;
            $'\x1b[B') # Down
                files_on_page=$(( TOTAL_FILES - (CURRENT_PAGE * FILES_PER_PAGE) ))
                if (( files_on_page > FILES_PER_PAGE )); then files_on_page=$FILES_PER_PAGE; fi
                if [ "$CURSOR_POS" -lt $((files_on_page - 1)) ]; then
                    CURSOR_POS=$((CURSOR_POS + 1))
                elif [ "$CURRENT_PAGE" -lt $((TOTAL_PAGES - 1)) ]; then
                    CURRENT_PAGE=$((CURRENT_PAGE + 1))
                    CURSOR_POS=0
                fi
                ;;
            $'\x1b[D') go_up ;;
            $'\x1b[C') enter_item ;;
        esac
        continue
    fi

    if [[ "$key" == "" || "$key" == $'\r' || "$key" == $'\n' ]]; then enter_item; continue; fi
    if [[ "$key" == $'\x7f' || "$key" == $'\x08' ]]; then go_up; continue; fi

    case "$key" in
        q|Q) break ;;
        ' ') sel="$(get_selected_path)"; [[ -n "$sel" ]] && toggle_mark "$sel" ;;
        A)   mark_all_in_dir ;;
        u|U) unmark_all ;;
        c)   clipboard_action "copy" ;;    # now supports marked items
        x)   clipboard_action "cut" ;;     # now supports marked items
        v)   paste_action ;;               # paste multiple or single
        d)   delete_file ;;
        r)   rename_file ;;
        n)   create_new ;;
        i)   show_info ;;
        p)   preview_file ;;
        h|H) show_help ;;
        C)   process_marked "C" ;;         # legacy key: will select marked items into clipboard
        M)   process_marked "M" ;;
        D)   process_marked "D" ;;
    esac
done

cleanup_exit 0
