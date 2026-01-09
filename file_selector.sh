#!/usr/bin/env bash
# ==============================================================================
# STATELESS PANE MANAGER UTILITY (file_selector.sh)
# ==============================================================================

set -uo pipefail

# --- Argument Parsing ---
COMMAND="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)          PANE_DIR="$2"; shift 2 ;;
        --cursor)       CURSOR_POS="$2"; shift 2 ;;
        --scroll)       SCROLL_OFFSET="$2"; shift 2 ;;
        --marks-file)   MARKS_FILE="$2"; shift 2 ;;
        --cache-file)   CACHE_FILE="$2"; shift 2 ;;
        --direction)    DIRECTION="$2"; shift 2 ;;
        --is-active)    IS_ACTIVE="$2"; shift 2 ;;
        --height)       PANE_HEIGHT="$2"; shift 2 ;;
        *)              echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Core Logic ---
index_dir() {
    if [[ ! -d "$PANE_DIR" ]]; then PANE_DIR=$(dirname "$PANE_DIR"); fi
    { echo ".."; find "$PANE_DIR" -maxdepth 1 -mindepth 1 -printf "%P\n"; } | sort -f > "$CACHE_FILE"
    : > "$MARKS_FILE"
    CURSOR_POS=0
    SCROLL_OFFSET=0
}

is_marked() {
    grep -Fxq -- "$1" "$MARKS_FILE" 2>/dev/null
}

# --- Commands ---
cmd_init() {
    index_dir
    local total_items=$(wc -l < "$CACHE_FILE")
    echo "dir='$PANE_DIR'; cursor_pos=$CURSOR_POS; scroll_offset=$SCROLL_OFFSET; total_items=$total_items"
}

cmd_navigate() {
    local total_items
    total_items=$(wc -l < "$CACHE_FILE")

    case "$DIRECTION" in
        up)
            if [[ $CURSOR_POS -gt 0 ]]; then CURSOR_POS=$((CURSOR_POS - 1)); fi ;;
        down)
            if [[ $CURSOR_POS -lt $((total_items - 1)) ]]; then CURSOR_POS=$((CURSOR_POS + 1)); fi ;;
        enter)
            local relative_path
            relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
            local selected_path
            selected_path=$(realpath "$PANE_DIR/$relative_path")
            if [[ -d "$selected_path" ]]; then
                PANE_DIR="$selected_path"
                index_dir
            fi
            ;;
        back)
            PANE_DIR=$(realpath "$PANE_DIR/..")
            index_dir
            ;;
    esac
    total_items=$(wc -l < "$CACHE_FILE")
    echo "dir='$PANE_DIR'; cursor_pos=$CURSOR_POS; scroll_offset=$SCROLL_OFFSET; total_items=$total_items"
}

cmd_toggle_mark() {
    local relative_path
    relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
    local selected_path
    selected_path=$(realpath "$PANE_DIR/$relative_path")

    local tmp_marks_file="${MARKS_FILE}.tmp"
    if is_marked "$selected_path"; then
        grep -Fxv -- "$selected_path" "$MARKS_FILE" > "$tmp_marks_file"
    else
        { cat "$MARKS_FILE"; echo "$selected_path"; } > "$tmp_marks_file"
    fi
    mv "$tmp_marks_file" "$MARKS_FILE"

    local total_items
    total_items=$(wc -l < "$CACHE_FILE")
    if [[ $CURSOR_POS -lt $((total_items - 1)) ]]; then CURSOR_POS=$((CURSOR_POS + 1)); fi

    echo "dir='$PANE_DIR'; cursor_pos=$CURSOR_POS; scroll_offset=$SCROLL_OFFSET; total_items=$total_items"
}

cmd_get_selection() {
    if [[ -s "$MARKS_FILE" ]]; then
        cat "$MARKS_FILE"
    else
        local relative_path
        relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
        realpath "$PANE_DIR/$relative_path"
    fi
}

# --- UI Drawing Command ---
cmd_get_pane_content() {
    # Define colors
    local color_reset="\e[0m"
    local color_cursor="\e[7m" # Reverse video
    local color_marked="\e[33m" # Yellow

    local line_counter=0
    local display_counter=0

    # Read the cache file line by line
    while IFS= read -r item || [[ -n "$item" ]]; do
        if [[ $line_counter -ge $SCROLL_OFFSET && $display_counter -lt $PANE_HEIGHT ]]; then
            local full_path
            full_path=$(realpath "$PANE_DIR/$item")
            local line="$item"

            # Truncate line if it's too long (leaving space for markers)
            # This is a basic implementation. A real one would be more robust.

            local prefix=""
            local suffix=""

            # Style the cursor line
            if [[ $line_counter -eq $CURSOR_POS && "$IS_ACTIVE" == "true" ]]; then
                prefix="$color_cursor"
                suffix="$color_reset"
            fi

            # Style marked items
            if is_marked "$full_path"; then
                prefix="$prefix$color_marked"
                suffix="$color_reset$suffix"
                line="* $line" # Add a visual marker
            else
                line="  $line"
            fi

            # Append '/' to directories
            if [[ -d "$full_path" && "$item" != ".." ]]; then
                line="$line/"
            fi

            echo -e "${prefix}${line}${suffix}"
            display_counter=$((display_counter + 1))
        fi
        line_counter=$((line_counter + 1))
    done < "$CACHE_FILE"

    # Fill remaining lines of the pane with empty lines
    while [[ $display_counter -lt $PANE_HEIGHT ]]; do
        echo ""
        display_counter=$((display_counter + 1))
    done
}


# --- Command Execution ---
case "$COMMAND" in
    init)               cmd_init ;;
    navigate)           cmd_navigate ;;
    toggle_mark)        cmd_toggle_mark ;;
    get_selection)      cmd_get_selection ;;
    get_pane_content)   cmd_get_pane_content ;;
    *)                  echo "Error: Unknown or missing command." >&2; exit 1 ;;
esac
