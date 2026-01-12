#!/usr/bin/env bash
# ==============================================================================
# STATELESS PANE MANAGER UTILITY (file_selector_improved.sh)
# Version: 1.0.0
# Description: Backend logic for directory indexing, navigation, and rendering
# ==============================================================================

set -uo pipefail

# --- Defaults ---
readonly DEFAULT_STEP=1

# --- Global Variables (populated by args) ---
COMMAND=""
PANE_DIR=""
CURSOR_POS=0
SCROLL_OFFSET=0
MARKS_FILE=""
CACHE_FILE=""
DIRECTION=""
STEP=$DEFAULT_STEP
IS_ACTIVE="false"
PANE_HEIGHT=0
PANE_WIDTH=0
LINE_NUM=0

# --- Argument Parsing ---
parse_args() {
    COMMAND="${1:-}"
    [[ -z "$COMMAND" ]] && { echo "Error: No command specified." >&2; exit 1; }
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)        PANE_DIR="$2"; shift 2 ;;
            --cursor)     CURSOR_POS="${2:-0}"; shift 2 ;;
            --scroll)     SCROLL_OFFSET="${2:-0}"; shift 2 ;;
            --marks-file) MARKS_FILE="$2"; shift 2 ;;
            --cache-file) CACHE_FILE="$2"; shift 2 ;;
            --direction)  DIRECTION="$2"; shift 2 ;;
            --step)       STEP="${2:-$DEFAULT_STEP}"; shift 2 ;;
            --is-active)  IS_ACTIVE="$2"; shift 2 ;;
            --height)     PANE_HEIGHT="${2:-0}"; shift 2 ;;
            --width)      PANE_WIDTH="${2:-0}"; shift 2 ;;
            --line)       LINE_NUM="${2:-0}"; shift 2 ;;
            *)            echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done
}

# --- Core Logic ---

# Index directory and save to cache
index_dir() {
    # Ensure PANE_DIR is a directory
    if [[ ! -d "$PANE_DIR" ]]; then
        PANE_DIR=$(dirname "$PANE_DIR")
    fi
    
    # Use realpath to normalize PANE_DIR
    PANE_DIR=$(realpath "$PANE_DIR")

    # Index directory: ".." first, then sorted files
    # We use -printf "%P\n" to get relative names. 
    # Note: filenames with newlines will still be problematic in a line-based cache.
    { 
        echo ".."
        find "$PANE_DIR" -maxdepth 1 -mindepth 1 -printf "%P\n" | sort -f 
    } > "$CACHE_FILE"
    
    # Reset state for new directory
    CURSOR_POS=0
    SCROLL_OFFSET=0
}

# Check if a path is marked
is_marked() {
    local path="$1"
    [[ -f "$MARKS_FILE" ]] && grep -Fxq -- "$path" "$MARKS_FILE" 2>/dev/null
}

# --- Commands ---

cmd_init() {
    index_dir
    local total_items
    total_items=$(wc -l < "$CACHE_FILE")
    
    printf "dir=%s\n" "$PANE_DIR"
    printf "cursor_pos=%d\n" "$CURSOR_POS"
    printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
    printf "total_items=%d\n" "$total_items"
}

cmd_navigate() {
    local total_items
    total_items=$(wc -l < "$CACHE_FILE")
    local old_cursor_pos=$CURSOR_POS
    local lines_to_update=""

    case "$DIRECTION" in
        up)        CURSOR_POS=$((CURSOR_POS - 1)) ;;
        down)      CURSOR_POS=$((CURSOR_POS + 1)) ;;
        page_up)   CURSOR_POS=$((CURSOR_POS - STEP)) ;;
        page_down) CURSOR_POS=$((CURSOR_POS + STEP)) ;;
        home)      CURSOR_POS=0 ;;
        end)       CURSOR_POS=$((total_items - 1)) ;;
        enter)
            local relative_path
            relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
            [[ -z "$relative_path" ]] && return
            
            local selected_path
            selected_path=$(realpath "$PANE_DIR/$relative_path" 2>/dev/null || echo "$PANE_DIR/$relative_path")
            
            if [[ -d "$selected_path" ]]; then
                PANE_DIR="$selected_path"
                index_dir
                total_items=$(wc -l < "$CACHE_FILE")
                printf "dir=%s\n" "$PANE_DIR"
                printf "cursor_pos=%d\n" "$CURSOR_POS"
                printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
                printf "total_items=%d\n" "$total_items"
                printf "lines_to_update=\n" 
                return
            fi
            ;;
        back)
            PANE_DIR=$(realpath "$PANE_DIR/.." 2>/dev/null || echo "$PANE_DIR/..")
            index_dir
            total_items=$(wc -l < "$CACHE_FILE")
            printf "dir=%s\n" "$PANE_DIR"
            printf "cursor_pos=%d\n" "$CURSOR_POS"
            printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
            printf "total_items=%d\n" "$total_items"
            printf "lines_to_update=\n"
            return
            ;;
    esac

    # Clamp Cursor
    [[ $CURSOR_POS -lt 0 ]] && CURSOR_POS=0
    if [[ $CURSOR_POS -ge $total_items ]]; then 
        CURSOR_POS=$((total_items > 0 ? total_items - 1 : 0))
    fi

    # Adjust Scroll Offset
    if [[ $CURSOR_POS -lt $SCROLL_OFFSET ]]; then
        SCROLL_OFFSET=$CURSOR_POS
        lines_to_update="" # Full redraw
    elif [[ $CURSOR_POS -ge $((SCROLL_OFFSET + PANE_HEIGHT)) ]]; then
        SCROLL_OFFSET=$((CURSOR_POS - PANE_HEIGHT + 1))
        lines_to_update="" # Full redraw
    else
        # Optimization for single line movement
        if [[ $((CURSOR_POS - old_cursor_pos)) -eq 1 ]] || [[ $((old_cursor_pos - CURSOR_POS)) -eq 1 ]]; then
             lines_to_update="$old_cursor_pos,$CURSOR_POS"
        elif [[ "$CURSOR_POS" != "$old_cursor_pos" ]]; then
             lines_to_update="" # Full redraw for jumps
        fi
    fi

    printf "dir=%s\n" "$PANE_DIR"
    printf "cursor_pos=%d\n" "$CURSOR_POS"
    printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
    printf "total_items=%d\n" "$total_items"
    printf "lines_to_update=%s\n" "$lines_to_update"
}

cmd_toggle_mark() {
    local relative_path
    relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
    [[ -z "$relative_path" ]] && return

    local selected_path
    selected_path=$(realpath "$PANE_DIR/$relative_path" 2>/dev/null || echo "$PANE_DIR/$relative_path")

    # Atomic update of marks file
    local tmp_marks_file
    tmp_marks_file=$(mktemp)
    
    if is_marked "$selected_path"; then
        grep -Fxv -- "$selected_path" "$MARKS_FILE" > "$tmp_marks_file" 2>/dev/null || true
    else
        if [[ -f "$MARKS_FILE" ]]; then
            cat "$MARKS_FILE" > "$tmp_marks_file"
        fi
        echo "$selected_path" >> "$tmp_marks_file"
    fi
    mv "$tmp_marks_file" "$MARKS_FILE"

    local total_items
    total_items=$(wc -l < "$CACHE_FILE")
    local old_cursor_pos=$CURSOR_POS
    local lines_to_update=""
    
    # Auto-advance cursor
    if [[ $CURSOR_POS -lt $((total_items - 1)) ]]; then 
        CURSOR_POS=$((CURSOR_POS + 1))
        if [[ $CURSOR_POS -ge $((SCROLL_OFFSET + PANE_HEIGHT)) ]]; then
            SCROLL_OFFSET=$((CURSOR_POS - PANE_HEIGHT + 1))
            lines_to_update=""
        else
            lines_to_update="$old_cursor_pos,$CURSOR_POS"
        fi
    else
        lines_to_update="$old_cursor_pos"
    fi

    printf "dir=%s\n" "$PANE_DIR"
    printf "cursor_pos=%d\n" "$CURSOR_POS"
    printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
    printf "total_items=%d\n" "$total_items"
    printf "lines_to_update=%s\n" "$lines_to_update"
}

cmd_get_selection() {
    if [[ -s "$MARKS_FILE" ]]; then
        cat "$MARKS_FILE"
    else
        local relative_path
        relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
        if [[ -n "$relative_path" ]]; then
            realpath "$PANE_DIR/$relative_path" 2>/dev/null || echo "$PANE_DIR/$relative_path"
        fi
    fi
}

# --- Rendering Logic ---

render_line() {
    local line_num="$1"
    local item
    item=$(sed -n "$((line_num + 1))p" "$CACHE_FILE")

    if [[ -z "$item" ]]; then
        echo ""
        return
    fi

    # Use tput for colors if possible, otherwise fallback to ANSI
    local color_reset="\e[0m"
    local color_cursor="\e[7m"
    local color_marked="\e[33m"

    local full_path
    full_path=$(realpath "$PANE_DIR/$item" 2>/dev/null || echo "$PANE_DIR/$item")
    local display_name="$item"

    # Truncate if too long
    local max_len=$((PANE_WIDTH - 4))
    if (( ${#display_name} > max_len )); then
        display_name="${display_name:0:$((max_len - 3))}..."
    fi

    local prefix=""
    local suffix=""

    # Active cursor styling
    if [[ $line_num -eq $CURSOR_POS && "$IS_ACTIVE" == "true" ]]; then
        prefix="$color_cursor"
        suffix="$color_reset"
    fi

    # Marked item styling
    if is_marked "$full_path"; then
        prefix="$prefix$color_marked"
        suffix="$color_reset$suffix"
        display_name="* $display_name"
    else
        display_name="  $display_name"
    fi

    # Directory indicator
    if [[ -d "$full_path" && "$item" != ".." ]]; then
        display_name="$display_name/"
    fi

    # Use printf for safe output
    printf "%b%s%b\n" "$prefix" "$display_name" "$suffix"
}

cmd_get_pane_content() {
    local total_items
    total_items=$(wc -l < "$CACHE_FILE")
    
    for (( i=0; i<PANE_HEIGHT; i++ )); do
        local current_line_num=$((SCROLL_OFFSET + i))
        if [[ $current_line_num -lt $total_items ]]; then
            render_line "$current_line_num"
        else
            echo ""
        fi
    done
}

cmd_get_line() {
    render_line "$LINE_NUM"
}

# --- Execution ---

parse_args "$@"

case "$COMMAND" in
    init)               cmd_init ;;
    navigate)           cmd_navigate ;;
    toggle_mark)        cmd_toggle_mark ;;
    get_selection)      cmd_get_selection ;;
    get_pane_content)   cmd_get_pane_content ;;
    get_line)           cmd_get_line ;;
    *)                  echo "Error: Unknown command '$COMMAND'." >&2; exit 1 ;;
esac
