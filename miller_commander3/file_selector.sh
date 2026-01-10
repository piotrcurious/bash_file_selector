#!/usr/bin/env bash
# ==============================================================================
# STATELESS PANE MANAGER UTILITY (file_selector.sh)
# ==============================================================================

set -uo pipefail

# --- Defaults ---
STEP=1

# --- Argument Parsing ---
COMMAND="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)        PANE_DIR="$2"; shift 2 ;;
        --cursor)     CURSOR_POS="$2"; shift 2 ;;
        --scroll)     SCROLL_OFFSET="$2"; shift 2 ;;
        --marks-file) MARKS_FILE="$2"; shift 2 ;;
        --cache-file) CACHE_FILE="$2"; shift 2 ;;
        --direction)  DIRECTION="$2"; shift 2 ;;
        --step)       STEP="$2"; shift 2 ;; # New argument for Page Up/Down
        --is-active)  IS_ACTIVE="$2"; shift 2 ;;
        --height)     PANE_HEIGHT="$2"; shift 2 ;;
        --width)      PANE_WIDTH="$2"; shift 2 ;;
        --line)       LINE_NUM="$2"; shift 2 ;;
        *)            echo "Unknown option: $1" >&2; exit 1 ;;
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

    # 1. Update Cursor Position based on direction
    case "$DIRECTION" in
        up)
            CURSOR_POS=$((CURSOR_POS - 1))
            ;;
        down)
            CURSOR_POS=$((CURSOR_POS + 1))
            ;;
        page_up)
            CURSOR_POS=$((CURSOR_POS - STEP))
            ;;
        page_down)
            CURSOR_POS=$((CURSOR_POS + STEP))
            ;;
        home)
            CURSOR_POS=0
            ;;
        end)
            CURSOR_POS=$((total_items - 1))
            ;;
        enter)
            local relative_path
            relative_path=$(sed -n "$(( CURSOR_POS + 1 ))p" "$CACHE_FILE")
            # Handle empty directory case
            if [ -z "$relative_path" ]; then return; fi 
            
            local selected_path
            selected_path=$(realpath "$PANE_DIR/$relative_path")
            if [[ -d "$selected_path" ]]; then
                PANE_DIR="$selected_path"
                index_dir
                # Early return because we reset everything (pos/scroll)
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
            PANE_DIR=$(realpath "$PANE_DIR/..")
            index_dir
            # Early return for dir change
            total_items=$(wc -l < "$CACHE_FILE")
            printf "dir=%s\n" "$PANE_DIR"
            printf "cursor_pos=%d\n" "$CURSOR_POS"
            printf "scroll_offset=%d\n" "$SCROLL_OFFSET"
            printf "total_items=%d\n" "$total_items"
            printf "lines_to_update=\n"
            return
            ;;
    esac

    # 2. Clamp Cursor to valid range
    if [[ $CURSOR_POS -lt 0 ]]; then 
        CURSOR_POS=0
    fi
    if [[ $CURSOR_POS -ge $total_items ]]; then 
        if [[ $total_items -gt 0 ]]; then
            CURSOR_POS=$((total_items - 1))
        else
            CURSOR_POS=0
        fi
    fi

    # 3. Adjust Scroll Offset to keep cursor in view
    # If cursor moved above the visible window
    if [[ $CURSOR_POS -lt $SCROLL_OFFSET ]]; then
        SCROLL_OFFSET=$CURSOR_POS
        lines_to_update="" # Force full redraw
    # If cursor moved below the visible window
    elif [[ $CURSOR_POS -ge $((SCROLL_OFFSET + PANE_HEIGHT)) ]]; then
        SCROLL_OFFSET=$((CURSOR_POS - PANE_HEIGHT + 1))
        lines_to_update="" # Force full redraw
    else
        # If we just moved 1 line and stayed in view, we can optimize redraws
        if [[ $((CURSOR_POS - old_cursor_pos)) -eq 1 ]] || [[ $((old_cursor_pos - CURSOR_POS)) -eq 1 ]]; then
             lines_to_update="$old_cursor_pos,$CURSOR_POS"
        else
             # For larger jumps (page up/down) or no movement, just redraw/no-op
             if [[ "$CURSOR_POS" != "$old_cursor_pos" ]]; then
                 lines_to_update="" # Full redraw usually safer for big jumps
             fi
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
    [ -z "$relative_path" ] && return

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
    local old_cursor_pos=$CURSOR_POS
    
    # Auto-advance cursor (MC style)
    if [[ $CURSOR_POS -lt $((total_items - 1)) ]]; then 
        CURSOR_POS=$((CURSOR_POS + 1))
        
        # Check scroll after auto-advance
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
        if [ -n "$relative_path" ]; then
            realpath "$PANE_DIR/$relative_path"
        fi
    fi
}

# --- UI Drawing Logic (Shared) ---
render_line() {
    local line_num="$1"
    local item
    item=$(sed -n "$((line_num + 1))p" "$CACHE_FILE")

    if [ -z "$item" ]; then
        echo ""
        return
    fi

    # Define colors
    local color_reset="\e[0m"
    local color_cursor="\e[7m" # Reverse video
    local color_marked="\e[33m" # Yellow

    local full_path
    full_path=$(realpath "$PANE_DIR/$item")
    local line="$item"

    # Truncate line if it's too long
    local max_len=$((PANE_WIDTH - 4)) # Account for prefix/suffix
    if ((${#line} > max_len)); then
        line="${line:0:$((max_len - 3))}..."
    fi

    local prefix=""
    local suffix=""

    # Style the cursor line
    if [[ $line_num -eq $CURSOR_POS && "$IS_ACTIVE" == "true" ]]; then
        prefix="$color_cursor"
        suffix="$color_reset"
    fi

    # Style marked items
    if is_marked "$full_path"; then
        prefix="$prefix$color_marked"
        suffix="$color_reset$suffix"
        line="* $line"
    else
        line="  $line"
    fi

    # Append '/' to directories
    if [[ -d "$full_path" && "$item" != ".." ]]; then
        line="$line/"
    fi

    echo -e "${prefix}${line}${suffix}"
}

# --- UI Drawing Commands ---
cmd_get_pane_content() {
    local display_counter=0
    local total_items
    total_items=$(wc -l < "$CACHE_FILE")

    while [[ $display_counter -lt $PANE_HEIGHT ]]; do
        local current_line_num=$((SCROLL_OFFSET + display_counter))
        if [[ $current_line_num -lt $total_items ]]; then
            render_line "$current_line_num"
        else
            echo ""
        fi
        display_counter=$((display_counter + 1))
    done
}

cmd_get_line() {
    render_line "$LINE_NUM"
}


# --- Command Execution ---
case "$COMMAND" in
    init)               cmd_init ;;
    navigate)           cmd_navigate ;;
    toggle_mark)        cmd_toggle_mark ;;
    get_selection)      cmd_get_selection ;;
    get_pane_content)   cmd_get_pane_content ;;
    get_line)           cmd_get_line ;;
    *)                  echo "Error: Unknown or missing command." >&2; exit 1 ;;
esac
