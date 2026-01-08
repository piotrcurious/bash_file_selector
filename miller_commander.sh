#!/usr/bin/env bash
# ==============================================================================
# MILLER COMMANDER - A file manager demonstrating file_selector.sh
#
# This script provides a Miller column interface, using `file_selector.sh`
# as the interactive component for directory navigation and file selection.
# ==============================================================================

set -uo pipefail

# ------- Configuration -------
readonly SELECTOR_SCRIPT="./file_selector.sh"
readonly SELECTION_FILE="$(mktemp --tmpdir miller_selection.XXXXXX)"

# Globals
PANES=()
ACTIVE_PANE_INDEX=0
COL_WIDTH=0
LAST_SELECTION=""
CLIPBOARD_PATH=""
CLIPBOARD_MODE="" # 'copy' or 'cut'
STATUS_MESSAGE=""

# ------- Terminal Setup / Cleanup -------
INITIAL_STTY_SETTINGS=$(stty -g 2>/dev/null || echo "")
cleanup_exit() {
    trap - INT TERM EXIT
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    if [[ -n "$INITIAL_STTY_SETTINGS" ]]; then
        stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true
    fi
    rm -f -- "$SELECTION_FILE" 2>/dev/null || true
    exit "${1:-0}"
}
trap 'cleanup_exit 0' EXIT
trap 'cleanup_exit 1' INT TERM

update_term_size() {
    COL_WIDTH=$(( $(tput cols) / 3 ))
}
trap update_term_size WINCH
update_term_size

# ------- File Operations -------
copy_selection_to_clipboard() {
    if [[ -n "$LAST_SELECTION" && -e "$LAST_SELECTION" ]]; then
        CLIPBOARD_PATH="$LAST_SELECTION"
        CLIPBOARD_MODE="copy"
        STATUS_MESSAGE="Copied '$(basename "$CLIPBOARD_PATH")'"
    else
        STATUS_MESSAGE="No file selected to copy."
    fi
}

paste_from_clipboard() {
    local dest_dir="${PANES[$ACTIVE_PANE_INDEX]}"
    if [[ ! -d "$dest_dir" ]]; then
        STATUS_MESSAGE="Cannot paste into a file."
        return
    fi

    if [[ -z "$CLIPBOARD_PATH" ]]; then
        STATUS_MESSAGE="Clipboard is empty."
        return
    fi

    if cp -r "$CLIPBOARD_PATH" "$dest_dir/"; then
        STATUS_MESSAGE="Pasted '$(basename "$CLIPBOARD_PATH")'"
    else
        STATUS_MESSAGE="Error pasting file."
    fi
}

delete_selection() {
    if [[ -z "$LAST_SELECTION" || ! -e "$LAST_SELECTION" ]]; then
        STATUS_MESSAGE="No file selected to delete."
        return
    fi

    tput rmcup
    stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true

    local ans
    read -rp "Delete '$(basename "$LAST_SELECTION")'? [y/N] " ans

    tput smcup

    if [[ "$ans" =~ ^[yY]$ ]]; then
        if rm -rf "$LAST_SELECTION"; then
            STATUS_MESSAGE="Deleted '$(basename "$LAST_SELECTION")'"
            local parent_dir
            parent_dir=$(dirname "$LAST_SELECTION")
            LAST_SELECTION=""
            for i in "${!PANES[@]}"; do
                if [[ "${PANES[$i]}" == "$parent_dir" ]]; then
                    PANES=("${PANES[@]:0:$((i + 1))}")
                    break
                fi
            done
        else
            STATUS_MESSAGE="Error deleting file."
        fi
    else
        STATUS_MESSAGE="Delete cancelled."
    fi
}

rename_selection() {
    local old_path="$LAST_SELECTION"
    if [[ -z "$old_path" || ! -e "$old_path" ]]; then
        STATUS_MESSAGE="No file or directory selected to rename."
        return
    fi

    tput rmcup
    stty "$INITIAL_STTY_SETTINGS" 2>/dev/null || true

    local old_name
    old_name=$(basename "$old_path")
    local dir_name
    dir_name=$(dirname "$old_path")

    local new_name
    read -rp "Rename '$old_name' to: " new_name

    tput smcup

    if [[ -z "$new_name" || "$new_name" == "$old_name" ]]; then
        STATUS_MESSAGE="Rename cancelled."
        return
    fi

    local new_path="$dir_name/$new_name"

    if [[ -e "$new_path" ]]; then
        STATUS_MESSAGE="Error: '$new_name' already exists."
        return
    fi

    if mv "$old_path" "$new_path"; then
        STATUS_MESSAGE="Renamed to '$new_name'"
        LAST_SELECTION="$new_path"

        for i in "${!PANES[@]}"; do
            if [[ "${PANES[$i]}" == "$old_path" ]]; then
                PANES[$i]="$new_path"
                break
            fi
        done
    else
        STATUS_MESSAGE="Error: Failed to rename."
    fi
}


# ------- Preview Logic -------
draw_preview_pane() {
    local file_path="$1"
    local start_row="$2"
    local start_col="$3"
    local pane_height="$4"
    local pane_width="$5"

    local mime
    mime=$(file --mime-type -b "$file_path" 2>/dev/null || echo "")

    local preview_content=""
    case "$mime" in
        text/*)
            preview_content=$(cat "$file_path" 2>/dev/null)
            ;;
        image/*)
            if command -v identify &>/dev/null; then
                preview_content=$(identify "$file_path" 2>/dev/null)
            else
                preview_content=$(file "$file_path" 2>/dev/null)
            fi
            ;;
        application/pdf)
            if command -v pdftotext &>/dev/null; then
                preview_content=$(pdftotext "$file_path" - 2>/dev/null)
            else
                preview_content="Install pdftotext to preview PDFs."
            fi
            ;;
        audio/*|video/*)
            if command -v ffprobe &>/dev/null; then
                preview_content=$(ffprobe -v error -show_format -show_streams "$file_path" 2>/dev/null)
            else
                preview_content=$(file "$file_path" 2>/dev/null)
            fi
            ;;
        application/zip)
             if command -v unzip &>/dev/null; then
                preview_content=$(unzip -l "$file_path" 2>/dev/null)
             else
                preview_content="Install unzip to preview zip files."
             fi
             ;;
        application/x-tar|application/gzip)
            if command -v tar &>/dev/null; then
                preview_content=$(tar -tf "$file_path" 2>/dev/null)
            else
                preview_content="tar command not available for preview."
            fi
            ;;
        *)
            if command -v hexdump &>/dev/null; then
                preview_content=$(hexdump -C "$file_path" 2>/dev/null)
            else
                preview_content="Binary file. No hex viewer found."
            fi
            ;;
    esac

    local row=$start_row
    while IFS= read -r line; do
        tput cup $row $start_col
        printf "%s" "${line:0:$pane_width}"
        row=$((row + 1))
        if [[ $row -ge $((start_row + pane_height)) ]]; then break; fi
    done <<< "$preview_content"
}


# ------- UI / Drawing -------
draw_panes() {
    tput clear

    local term_height=$(tput lines)
    local header_rows=2
    local footer_rows=1
    local content_height=$(( term_height - header_rows - footer_rows ))

    for i in "${!PANES[@]}"; do
        if [[ $i -ge 3 ]]; then break; fi # Max 3 panes

        local item_path="${PANES[$i]}"
        local col_start=$(( i * COL_WIDTH ))

        # Draw header
        tput cup 0 $col_start
        local header_text
        header_text=$(basename "$item_path")
        if [[ $i -eq $ACTIVE_PANE_INDEX ]]; then
            printf "\033[1m\033[44m%-${COL_WIDTH}s\033[0m" "$header_text"
        else
            printf "\033[4m%-${COL_WIDTH}s\033[0m" "$header_text"
        fi

        # Draw content
        if [[ -d "$item_path" ]]; then
            local row=$header_rows
            while IFS= read -r item; do
                tput cup $row $col_start

                local display_item
                display_item=$(basename "$item")
                if [[ -d "$item" ]]; then display_item+="/"; fi

                printf "%-${COL_WIDTH}s" "${display_item:0:$((COL_WIDTH-1))}"
                row=$((row + 1))
                if [[ $row -ge $term_height ]]; then break; fi
            done < <(find "$item_path" -maxdepth 1 -mindepth 1 | sort | head -n $content_height)
        elif [[ -f "$item_path" ]]; then
            draw_preview_pane "$item_path" "$header_rows" "$col_start" "$content_height" "$COL_WIDTH"
        fi
    done

    tput cup $((term_height - 1)) 0
    printf "\033[7m%*s\033[0m" "$(tput cols)" ""
    tput cup $((term_height - 1)) 1
    if [[ -n "$STATUS_MESSAGE" ]]; then
        printf "\033[7m%s\033[0m" "$STATUS_MESSAGE"
        STATUS_MESSAGE=""
    else
        printf "\033[7m[h/l] Nav | [c] Copy | [v] Paste | [d] Del | [r] Ren | [q] Quit\033[0m"
    fi
}

# ------- Main Loop -------
main() {
    chmod +x "$SELECTOR_SCRIPT"
    tput smcup

    PANES[0]="$(pwd)"

    while true; do
        draw_panes

        IFS= read -rsn3 key || key=""
        case "$key" in
            $'\x1b[D'|h) # Left or h
                if [[ $ACTIVE_PANE_INDEX -gt 0 ]]; then ACTIVE_PANE_INDEX=$((ACTIVE_PANE_INDEX - 1)); fi;;
            $'\x1b[C'|l) # Right or l
                if [[ $ACTIVE_PANE_INDEX -lt $((${#PANES[@]} - 1)) && $ACTIVE_PANE_INDEX -lt 2 ]]; then ACTIVE_PANE_INDEX=$((ACTIVE_PANE_INDEX + 1)); fi;;
            ""|$'\n'|' ') # Enter or Space
                local current_path="${PANES[$ACTIVE_PANE_INDEX]}"
                if [[ ! -d "$current_path" ]]; then continue; fi

                tput rmcup
                bash "$SELECTOR_SCRIPT" "$current_path" "$SELECTION_FILE"
                local exit_code=$?
                tput smcup

                if [[ $exit_code -eq 0 ]]; then
                    LAST_SELECTION=$(<"$SELECTION_FILE")
                    PANES=("${PANES[@]:0:$((ACTIVE_PANE_INDEX + 1))}")
                    if [[ ${#PANES[@]} -lt 3 ]]; then PANES+=("$LAST_SELECTION"); else PANES[2]="$LAST_SELECTION"; fi
                    if [[ -d "$LAST_SELECTION" ]]; then
                         ACTIVE_PANE_INDEX=$((ACTIVE_PANE_INDEX + 1))
                         if [[ $ACTIVE_PANE_INDEX -ge 3 ]]; then ACTIVE_PANE_INDEX=2; fi
                    fi
                fi
                ;;
            c|C) copy_selection_to_clipboard;;
            v|V) paste_from_clipboard;;
            d|D) delete_selection;;
            r|R) rename_selection;;
            q|Q) break;;
        esac
    done
}

main "$@"
