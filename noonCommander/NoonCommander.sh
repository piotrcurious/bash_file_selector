#!/bin/bash

# BASH Commander - Enhanced File Manager
# Version: 2.0

# Configuration
FILES_PER_PAGE=20
INDENT="    "
WRAP_WIDTH=$(tput cols)
SELECTION_FILE=".commander_selection.tmp"
CLIPBOARD_FILE=".commander_clipboard.tmp"

# Initialize
CURRENT_DIR="$(pwd)"
> "$SELECTION_FILE"
> "$CLIPBOARD_FILE"
CURSOR_POS=0
CURRENT_PAGE=0
CLIPBOARD_MODE=""  # 'copy' or 'cut'

# Terminal setup
stty -echo -icanon time 0 min 0
trap 'cleanup_exit' INT TERM EXIT

cleanup_exit() {
    tput cnorm
    stty sane
    clear
    exit
}

# Color codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_CYAN="\033[36m"

index_dir() {
    local dir="$1"
    TMP_INDEX_FILE="/tmp/file_commander_index_$(echo "$dir" | md5sum | awk '{print $1}').tmp"
    find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | sort > "$TMP_INDEX_FILE"
    TOTAL_FILES=$(wc -l < "$TMP_INDEX_FILE")
    TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
    [[ $TOTAL_FILES -eq 0 ]] && TOTAL_PAGES=1
}

format_size() {
    local size=$1
    if (( size < 1024 )); then
        echo "${size}B"
    elif (( size < 1048576 )); then
        echo "$((size / 1024))K"
    elif (( size < 1073741824 )); then
        echo "$((size / 1048576))M"
    else
        echo "$((size / 1073741824))G"
    fi
}

draw_page() {
    clear
    tput civis
    
    # Header
    echo -e "${C_BOLD}${C_CYAN}📁 BASH COMMANDER${C_RESET} - ${C_GREEN}$CURRENT_DIR${C_RESET}"
    echo -e "${C_DIM}Files: $TOTAL_FILES | Page: $((CURRENT_PAGE + 1))/$TOTAL_PAGES${C_RESET}"
    
    # Keybindings
    echo -e "${C_YELLOW}↑↓${C_RESET}:Move ${C_YELLOW}Enter${C_RESET}:Open ${C_YELLOW}←${C_RESET}:Up ${C_YELLOW}[p]${C_RESET}:Preview ${C_YELLOW}[e]${C_RESET}:Edit ${C_YELLOW}[c]${C_RESET}:Copy ${C_YELLOW}[x]${C_RESET}:Cut ${C_YELLOW}[v]${C_RESET}:Paste"
    echo -e "${C_YELLOW}[m]${C_RESET}:Move ${C_YELLOW}[d]${C_RESET}:Delete ${C_YELLOW}[r]${C_RESET}:Rename ${C_YELLOW}[n]${C_RESET}:New ${C_YELLOW}[s]${C_RESET}:Search ${C_YELLOW}[i]${C_RESET}:Info ${C_YELLOW}[q]${C_RESET}:Quit"
    echo
    
    # Clipboard status
    if [[ -s "$CLIPBOARD_FILE" ]]; then
        local clip_item=$(cat "$CLIPBOARD_FILE")
        echo -e "${C_BLUE}📋 Clipboard [$CLIPBOARD_MODE]: $(basename "$clip_item")${C_RESET}"
        echo
    fi

    START=$((CURRENT_PAGE * FILES_PER_PAGE + 1))
    END=$((START + FILES_PER_PAGE - 1))

    awk -v s="$START" -v e="$END" -v c="$CURSOR_POS" -v w="$WRAP_WIDTH" -v base="$CURRENT_DIR" '
    NR >= s && NR <= e {
        path = $0;
        fname = substr(path, length(base) + 2);
        prefix = (NR - s == c ? "> " : "  ");
        
        # Show directory indicator
        cmd = "test -d \"" path "\"";
        if (system(cmd) == 0) {
            fname = fname "/";
        }
        
        while (length(fname) > w - 4) {
            print prefix substr(fname,1,w-4);
            fname = substr(fname,w-3);
            prefix = "  '"$INDENT"'";
        }
        print prefix fname;
    }' "$TMP_INDEX_FILE"
    
    # Show empty directory message
    if [[ $TOTAL_FILES -eq 0 ]]; then
        echo -e "  ${C_DIM}(Empty directory)${C_RESET}"
    fi
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

show_message() {
    local msg="$1"
    local duration="${2:-2}"
    tput cnorm
    stty sane
    echo -e "\n${C_GREEN}${msg}${C_RESET}"
    sleep "$duration"
    stty -echo -icanon time 0 min 0
}

show_error() {
    local msg="$1"
    local duration="${2:-2}"
    tput cnorm
    stty sane
    echo -e "\n${C_RED}${msg}${C_RESET}"
    sleep "$duration"
    stty -echo -icanon time 0 min 0
}

preview_file() {
    local file="$(get_selected_path)"
    [[ -z "$file" ]] && return
    
    if [[ -d "$file" ]]; then
        show_error "'$file' is a directory."
        return
    fi
    
    local mime=$(file --mime-type -b "$file" 2>/dev/null)
    tput cnorm
    stty sane
    clear
    echo -e "${C_CYAN}${C_BOLD}Previewing:${C_RESET} $file"
    echo "-----------------------------------"
    
    case "$mime" in
        text/*)
            if command -v bat &>/dev/null; then
                bat --style=plain "$file"
            else
                less "$file"
            fi
            ;;
        image/*)
            if command -v identify &>/dev/null; then
                identify "$file" 2>/dev/null
            else
                file "$file"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        application/pdf)
            if command -v pdftotext &>/dev/null; then
                pdftotext "$file" - | less
            else
                echo "pdftotext not found. Install poppler-utils."
                read -p "Press Enter to continue..."
            fi
            ;;
        audio/*|video/*)
            if command -v ffprobe &>/dev/null; then
                ffprobe "$file" 2>&1 | less
            elif command -v mediainfo &>/dev/null; then
                mediainfo "$file" | less
            else
                file "$file"
                read -p "Press Enter to continue..."
            fi
            ;;
        application/zip|application/x-tar|application/gzip)
            if command -v unzip &>/dev/null && [[ "$mime" == "application/zip" ]]; then
                unzip -l "$file" | less
            elif command -v tar &>/dev/null; then
                tar -tzf "$file" 2>/dev/null | less || tar -tJf "$file" 2>/dev/null | less
            else
                file "$file"
                read -p "Press Enter to continue..."
            fi
            ;;
        *)
            echo "Binary or unknown filetype. Hex preview:"
            if command -v xxd &>/dev/null; then
                xxd "$file" | head -n 100 | less
            else
                hexdump -C "$file" | head -n 100 | less
            fi
            ;;
    esac
    
    stty -echo -icanon time 0 min 0
    index_dir "$CURRENT_DIR"
}

edit_file() {
    local file="$(get_selected_path)"
    [[ -z "$file" ]] && return
    
    if [[ -d "$file" ]]; then
        show_error "'$file' is a directory."
        return
    fi
    
    local mime=$(file --mime-type -b "$file" 2>/dev/null)
    tput cnorm
    stty sane
    clear
    
    # Use EDITOR environment variable or default to nano
    local editor="${EDITOR:-nano}"
    
    case "$mime" in
        text/*)
            "$editor" "$file"
            ;;
        *)
            echo "Binary file detected."
            echo -n "Edit with hex editor? [y/N]: "
            read ans
            if [[ "$ans" == [yY] ]]; then
                if command -v hexedit &>/dev/null; then
                    hexedit "$file"
                elif command -v xxd &>/dev/null; then
                    xxd "$file" > /tmp/hex_edit.tmp
                    "$editor" /tmp/hex_edit.tmp
                    echo -n "Save changes? [y/N]: "
                    read save
                    [[ "$save" == [yY] ]] && xxd -r /tmp/hex_edit.tmp > "$file"
                    rm -f /tmp/hex_edit.tmp
                else
                    echo "No hex editor available."
                    read -p "Press Enter to continue..."
                fi
            fi
            ;;
    esac
    
    stty -echo -icanon time 0 min 0
    index_dir "$CURRENT_DIR"
}

rename_file() {
    local src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    tput cnorm
    stty sane
    echo -ne "\n${C_YELLOW}Rename '$(basename "$src")' to: ${C_RESET}"
    read newname
    
    if [[ -z "$newname" ]]; then
        show_message "Rename cancelled."
        return
    fi
    
    local dest="$(dirname "$src")/$newname"
    if [[ -e "$dest" ]]; then
        show_error "File already exists!"
    elif mv -- "$src" "$dest" 2>/dev/null; then
        show_message "Renamed successfully."
        index_dir "$CURRENT_DIR"
    else
        show_error "Rename failed!"
    fi
}

delete_file() {
    local path="$(get_selected_path)"
    [[ -z "$path" ]] && return
    
    tput cnorm
    stty sane
    echo -ne "\n${C_RED}Delete '$(basename "$path")'? [y/N]: ${C_RESET}"
    read ans
    
    if [[ "$ans" == [yY] ]]; then
        if rm -rf -- "$path" 2>/dev/null; then
            show_message "Deleted successfully."
            index_dir "$CURRENT_DIR"
        else
            show_error "Delete failed!"
        fi
    else
        show_message "Delete cancelled."
    fi
}

copy_file() {
    local src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    tput cnorm
    stty sane
    echo -ne "\n${C_YELLOW}Copy to (path): ${C_RESET}"
    read dest
    
    [[ -z "$dest" ]] && { show_message "Copy cancelled."; return; }
    
    if cp -r -- "$src" "$dest" 2>/dev/null; then
        show_message "Copied successfully."
        index_dir "$CURRENT_DIR"
    else
        show_error "Copy failed!"
    fi
}

move_file() {
    local src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    tput cnorm
    stty sane
    echo -ne "\n${C_YELLOW}Move to (path): ${C_RESET}"
    read dest
    
    [[ -z "$dest" ]] && { show_message "Move cancelled."; return; }
    
    if mv -- "$src" "$dest" 2>/dev/null; then
        show_message "Moved successfully."
        index_dir "$CURRENT_DIR"
    else
        show_error "Move failed!"
    fi
}

clipboard_copy() {
    local src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    echo "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="copy"
    show_message "Copied to clipboard: $(basename "$src")" 1
}

clipboard_cut() {
    local src="$(get_selected_path)"
    [[ -z "$src" ]] && return
    
    echo "$src" > "$CLIPBOARD_FILE"
    CLIPBOARD_MODE="cut"
    show_message "Cut to clipboard: $(basename "$src")" 1
}

clipboard_paste() {
    if [[ ! -s "$CLIPBOARD_FILE" ]]; then
        show_error "Clipboard is empty!"
        return
    fi
    
    local src=$(cat "$CLIPBOARD_FILE")
    local dest="$CURRENT_DIR/$(basename "$src")"
    
    if [[ ! -e "$src" ]]; then
        show_error "Source no longer exists!"
        > "$CLIPBOARD_FILE"
        CLIPBOARD_MODE=""
        return
    fi
    
    if [[ "$CLIPBOARD_MODE" == "copy" ]]; then
        if cp -r -- "$src" "$dest" 2>/dev/null; then
            show_message "Pasted successfully."
            index_dir "$CURRENT_DIR"
        else
            show_error "Paste failed!"
        fi
    elif [[ "$CLIPBOARD_MODE" == "cut" ]]; then
        if mv -- "$src" "$dest" 2>/dev/null; then
            show_message "Pasted successfully."
            > "$CLIPBOARD_FILE"
            CLIPBOARD_MODE=""
            index_dir "$CURRENT_DIR"
        else
            show_error "Paste failed!"
        fi
    fi
}

create_new() {
    tput cnorm
    stty sane
    echo
    echo "Create: [f]ile or [d]irectory?"
    read -rsn1 choice
    
    case "$choice" in
        f)
            echo -ne "\n${C_YELLOW}New file name: ${C_RESET}"
            read fname
            [[ -z "$fname" ]] && { show_message "Cancelled."; return; }
            if touch "$CURRENT_DIR/$fname" 2>/dev/null; then
                show_message "File created: $fname"
                index_dir "$CURRENT_DIR"
            else
                show_error "Failed to create file!"
            fi
            ;;
        d)
            echo -ne "\n${C_YELLOW}New directory name: ${C_RESET}"
            read dname
            [[ -z "$dname" ]] && { show_message "Cancelled."; return; }
            if mkdir -p "$CURRENT_DIR/$dname" 2>/dev/null; then
                show_message "Directory created: $dname"
                index_dir "$CURRENT_DIR"
            else
                show_error "Failed to create directory!"
            fi
            ;;
        *)
            show_message "Cancelled."
            ;;
    esac
}

search_files() {
    tput cnorm
    stty sane
    echo -ne "\n${C_YELLOW}Search for: ${C_RESET}"
    read query
    
    [[ -z "$query" ]] && { show_message "Search cancelled."; return; }
    
    clear
    echo -e "${C_CYAN}Search results for: '$query'${C_RESET}"
    echo "-----------------------------------"
    find "$CURRENT_DIR" -iname "*$query*" 2>/dev/null | less
    
    stty -echo -icanon time 0 min 0
}

show_info() {
    local path="$(get_selected_path)"
    [[ -z "$path" ]] && return
    
    tput cnorm
    stty sane
    clear
    echo -e "${C_CYAN}${C_BOLD}File Information${C_RESET}"
    echo "-----------------------------------"
    echo -e "${C_YELLOW}Path:${C_RESET} $path"
    
    if [[ -d "$path" ]]; then
        local count=$(find "$path" -mindepth 1 2>/dev/null | wc -l)
        echo -e "${C_YELLOW}Type:${C_RESET} Directory"
        echo -e "${C_YELLOW}Items:${C_RESET} $count"
    else
        local size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null)
        local mime=$(file --mime-type -b "$path" 2>/dev/null)
        echo -e "${C_YELLOW}Type:${C_RESET} File"
        echo -e "${C_YELLOW}Size:${C_RESET} $(format_size $size) ($size bytes)"
        echo -e "${C_YELLOW}MIME:${C_RESET} $mime"
    fi
    
    echo
    ls -lh "$path"
    echo
    read -p "Press Enter to continue..."
    
    stty -echo -icanon time 0 min 0
}

enter_item() {
    local path="$(get_selected_path)"
    [[ -z "$path" ]] && return
    
    if [[ -d "$path" ]]; then
        CURRENT_DIR="$path"
        CURRENT_PAGE=0
        CURSOR_POS=0
        index_dir "$CURRENT_DIR"
    else
        echo "$path" >> "$SELECTION_FILE"
        if command -v xdg-open &>/dev/null; then
            xdg-open "$path" &>/dev/null &
        elif command -v open &>/dev/null; then
            open "$path" &>/dev/null &
        fi
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
            $'\x1b[D') go_up ;;
        esac
    elif [[ $key == "" ]]; then
        enter_item
    elif [[ $key == $'\x7f' ]]; then
        go_up
    else
        case "$key" in
            q) break ;;
            p) preview_file ;;
            e) edit_file ;;
            r) rename_file ;;
            d) delete_file ;;
            c) clipboard_copy ;;
            x) clipboard_cut ;;
            v) clipboard_paste ;;
            m) move_file ;;
            n) create_new ;;
            s) search_files ;;
            i) show_info ;;
        esac
    fi
done

tput cnorm
stty sane
clear
echo -e "${C_GREEN}Session ended.${C_RESET}"
[[ -s "$SELECTION_FILE" ]] && echo "Selections saved in: $SELECTION_FILE"
