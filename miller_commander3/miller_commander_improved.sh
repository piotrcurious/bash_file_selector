#!/usr/bin/env bash
# ==============================================================================
# BASH MILLER COMMANDER - Dual-Pane File Manager
# Version: 1.0.0
# Description: Terminal-based file manager with advanced navigation and
#              instant resize support
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONSTANTS AND CONFIGURATION
# ==============================================================================

readonly VERSION="1.0.0"
readonly SCRIPT_NAME="Bash Miller Commander"
readonly FOOTER_HEIGHT=2
readonly INPUT_TIMEOUT=0.2
readonly ESCAPE_SEQ_TIMEOUT=0.005

# Script paths
readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
readonly PANE_MANAGER_SCRIPT="$SCRIPT_DIR/file_selector.sh"

# Debug mode (set DEBUG=1 to enable)
readonly DEBUG=${DEBUG:-0}
readonly LOG_FILE="$HOME/.miller_commander.log"

# External commands with fallbacks
readonly FILE_VIEWER="${PAGER:-less}"
readonly FILE_EDITOR="${EDITOR:-nano}"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

declare -A PANE_0 PANE_1
ACTIVE_PANE_NAME="PANE_0"
STATUS_MESSAGE=""
NEEDS_REDRAW=0
OLD_STTY=""
TEMP_DIR=""

# Cached dimensions (updated on resize)
CACHED_TERM_HEIGHT=0
CACHED_TERM_WIDTH=0
CACHED_HALF_WIDTH=0
CACHED_PANE_HEIGHT=0

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Log debug messages to file
# Arguments:
#   $@ - Message to log
debug_log() {
    if [[ $DEBUG -eq 1 ]]; then
        printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
    fi
}

# Log error messages
# Arguments:
#   $@ - Error message
error_log() {
    printf "[ERROR] %s\n" "$*" >> "$LOG_FILE"
}

# Validate directory name for safety
# Arguments:
#   $1 - Directory name to validate
# Returns:
#   0 if valid, 1 if invalid
validate_dirname() {
    local name="$1"
    
    # Check for empty name
    if [[ -z "$name" ]]; then
        return 1
    fi
    
    # Check for invalid characters (/, null byte, leading -)
    if [[ "$name" =~ [/\0] ]] || [[ "$name" =~ ^\. ]] || [[ "$name" =~ ^- ]]; then
        return 1
    fi
    
    return 0
}

# Cache terminal dimensions
# Side effects:
#   Updates CACHED_* global variables
cache_dimensions() {
    CACHED_TERM_HEIGHT=$(tput lines)
    CACHED_TERM_WIDTH=$(tput cols)
    CACHED_HALF_WIDTH=$(( (CACHED_TERM_WIDTH - 1) / 2 ))
    CACHED_PANE_HEIGHT=$((CACHED_TERM_HEIGHT - FOOTER_HEIGHT))
    debug_log "Dimensions cached: ${CACHED_TERM_WIDTH}x${CACHED_TERM_HEIGHT}"
}

# ==============================================================================
# INITIALIZATION AND CLEANUP
# ==============================================================================

# Check dependencies at startup
check_dependencies() {
    if [[ ! -x "$PANE_MANAGER_SCRIPT" ]]; then
        echo "Error: The pane manager script '$PANE_MANAGER_SCRIPT' is not executable or not found." >&2
        exit 1
    fi
}

# Signal handler for window resize
# Side effects:
#   Sets NEEDS_REDRAW flag (safe in Bash signal context)
handle_resize() {
    NEEDS_REDRAW=1
}

# Cleanup function called on exit
# Side effects:
#   Restores terminal state, removes temporary files
cleanup() {
    debug_log "Cleanup initiated"
    
    # Restore terminal state
    if [[ -n "$OLD_STTY" ]]; then
        stty "$OLD_STTY" 2>/dev/null || true
    fi
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    
    # Clean temp directory
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    debug_log "Cleanup completed"
}

# Initialize terminal and traps
init_terminal() {
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    debug_log "Temp directory created: $TEMP_DIR"
    
    # Save terminal state
    OLD_STTY=$(stty -g)
    
    # Set up traps
    trap cleanup EXIT INT TERM HUP
    trap handle_resize SIGWINCH
    
    # Enter alternate screen, hide cursor, disable echo/canonical mode
    tput smcup
    tput civis
    stty -echo -icanon -ixon 2>/dev/null || true
    
    debug_log "Terminal initialized"
}

# ==============================================================================
# PANE MANAGEMENT FUNCTIONS
# ==============================================================================

# Update pane state from key=value input
# Arguments:
#   $1 - Name of pane associative array (PANE_0 or PANE_1)
#   $2 - State string with key=value pairs separated by newlines
# Side effects:
#   Modifies the pane associative array
update_pane_state() {
    local -n pane_ref=$1
    local input_state="$2"
    
    pane_ref[lines_to_update]=""
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local key=${line%%=*}
        local value=${line#*=}
        pane_ref["$key"]="$value"
    done <<< "$input_state"
    
    debug_log "Updated state for $1"
}

# Initialize a pane with given parameters
# Arguments:
#   $1 - Name of pane associative array
#   $2 - Starting directory
#   $3 - Pane height
#   $4 - Pane width
# Returns:
#   0 on success, 1 on failure
# Side effects:
#   Creates temporary files, updates pane state
init_pane() {
    local -n pane_ref=$1
    local start_dir="$2"
    local pane_height="$3"
    local pane_width="$4"

    # Create temp files in our temp directory
    pane_ref[marks_file]="$TEMP_DIR/${1}_marks"
    pane_ref[cache_file]="$TEMP_DIR/${1}_cache"
    pane_ref[render_file]="$TEMP_DIR/${1}_render"
    
    touch "${pane_ref[marks_file]}" "${pane_ref[cache_file]}" "${pane_ref[render_file]}"

    local new_state
    if ! new_state=$("$PANE_MANAGER_SCRIPT" init \
        --dir "$start_dir" \
        --marks-file "${pane_ref[marks_file]}" \
        --cache-file "${pane_ref[cache_file]}" \
        --height "$pane_height" \
        --width "$pane_width" 2>&1); then
        error_log "Failed to initialize $1: $new_state"
        return 1
    fi

    update_pane_state "$1" "$new_state"
    debug_log "Initialized $1 at $start_dir"
    return 0
}

# Get the currently selected file path in active pane
# Returns:
#   Prints file path to stdout, empty string if none
get_active_file_path() {
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local selection
    
    if ! selection=$("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}" 2>&1); then
        error_log "Failed to get selection: $selection"
        echo ""
        return 1
    fi
    
    if [[ -n "$selection" ]]; then
        echo "$selection" | head -n1
    else
        echo ""
    fi
}

# Refresh both panes with current dimensions
# Side effects:
#   Re-initializes both panes
refresh_panes() {
    local inactive_pane_name
    inactive_pane_name=$(get_inactive_pane_name)
    
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local -n inactive_pane_ref=$inactive_pane_name

    init_pane "$ACTIVE_PANE_NAME" "${active_pane_ref[dir]}" "$CACHED_PANE_HEIGHT" "$CACHED_HALF_WIDTH"
    init_pane "$inactive_pane_name" "${inactive_pane_ref[dir]}" "$CACHED_PANE_HEIGHT" "$CACHED_HALF_WIDTH"
    
    debug_log "Panes refreshed"
}

# Get the name of the inactive pane
# Returns:
#   Prints pane name to stdout
get_inactive_pane_name() {
    if [[ "$ACTIVE_PANE_NAME" == "PANE_0" ]]; then
        echo "PANE_1"
    else
        echo "PANE_0"
    fi
}

# ==============================================================================
# UI RENDERING FUNCTIONS
# ==============================================================================

# AWK script for compositing two panes side by side
# Handles ANSI escape sequences correctly
readonly AWK_COMPOSITOR='BEGIN {
  # Parse arguments: left_file, right_file, left_width, right_width, height
  L = ARGV[1]; R = ARGV[2]; LW = ARGV[3]+0; RW = ARGV[4]+0; H = ARGV[5]+0;
  for(i=0;i<6;i++) ARGV[i]="";
  
  # Read left pane lines
  lcount = 0; 
  while ((getline line < L) > 0) { 
    lcount++; 
    Larr[lcount] = line 
  } 
  close(L)
  
  # Read right pane lines
  rcount = 0; 
  while ((getline line < R) > 0) { 
    rcount++; 
    Rarr[rcount] = line 
  } 
  close(R)
  
  # ANSI escape sequence regex
  ansi_re = "\033\\[[0-9;:?]*[A-Za-z]"
  
  # Composite lines
  for (i = 1; i <= H; i++) {
    l = (i <= lcount ? Larr[i] : "")
    r = (i <= rcount ? Rarr[i] : "")
    Lout = fmt(l, LW, ansi_re)
    Rout = fmt(r, RW, ansi_re)
    printf("%s│%s\n", Lout, Rout)
  }
  exit
}

# Strip ANSI escape sequences for length calculation
function strip_ansi(s, t) { 
  t = s; 
  gsub(/\033\[[0-9;:?]*[A-Za-z]/, "", t); 
  return t 
}

# Get visible length (without ANSI codes)
function vislen(s) { 
  return length(strip_ansi(s)) 
}

# Format string to exact width, preserving ANSI codes
function fmt(s, w, ansi_re, v, out, rem, need, count) {
  v = vislen(s)
  
  # Exact match
  if (v == w) return s
  
  # Too short - pad with spaces
  if (v < w) {
    need = w - v; 
    out = s; 
    for (j = 0; j < need; j++) out = out " "; 
    return out
  }
  
  # Too long - truncate while preserving ANSI codes
  out = ""; 
  rem = s; 
  count = 0
  while (length(rem) > 0 && count < w) {
    if (match(rem, ansi_re)) {
      if (RSTART == 1) { 
        # ANSI code at start - include it (doesn't count toward width)
        out = out substr(rem, 1, RLENGTH); 
        rem = substr(rem, RLENGTH+1); 
        continue 
      } else { 
        # Regular character before ANSI code
        out = out substr(rem, 1, 1); 
        rem = substr(rem, 2); 
        count++; 
        continue 
      }
    } else { 
      # No more ANSI codes - add remaining characters up to width
      need = w - count; 
      out = out substr(rem, 1, need); 
      break 
    }
  }
  return out
}
'

# Render pane content to file with proper height padding
# Arguments:
#   $1 - Pane content string
#   $2 - Output file path
#   $3 - Width (unused but kept for compatibility)
#   $4 - Height
render_pane_to_file() {
    local pane_content="$1"
    local out_file="$2"
    local width="$3"  # Unused but kept for API compatibility
    local height="$4"
    
    printf "%s" "$pane_content" > "$out_file"
    
    local current_lines
    current_lines=$(wc -l < "$out_file" 2>/dev/null || echo 0)
    
    # Pad with empty lines to reach desired height
    while [[ "$current_lines" -lt "$height" ]]; do
        printf "\n" >> "$out_file"
        current_lines=$((current_lines+1))
    done
}

# Draw the complete UI
# Side effects:
#   Clears screen and renders both panes with footer
draw_ui() {
    tput clear
    
    # Set default directories if not set
    : "${PANE_0[dir]:=$(pwd)}"
    : "${PANE_1[dir]:=$HOME}"

    # Get pane contents
    local pane0_content pane1_content
    
    pane0_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_0[dir]}" \
        --cursor "${PANE_0[cursor_pos]}" \
        --scroll "${PANE_0[scroll_offset]}" \
        --marks-file "${PANE_0[marks_file]}" \
        --cache-file "${PANE_0[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "true" || echo "false")" \
        --height "$CACHED_PANE_HEIGHT" \
        --width "$CACHED_HALF_WIDTH" 2>/dev/null || true)

    pane1_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_1[dir]}" \
        --cursor "${PANE_1[cursor_pos]}" \
        --scroll "${PANE_1[scroll_offset]}" \
        --marks-file "${PANE_1[marks_file]}" \
        --cache-file "${PANE_1[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_1" ] && echo "true" || echo "false")" \
        --height "$CACHED_PANE_HEIGHT" \
        --width "$CACHED_HALF_WIDTH" 2>/dev/null || true)

    # Render to temp files
    render_pane_to_file "$pane0_content" "${PANE_0[render_file]}" "$CACHED_HALF_WIDTH" "$CACHED_PANE_HEIGHT"
    render_pane_to_file "$pane1_content" "${PANE_1[render_file]}" "$CACHED_HALF_WIDTH" "$CACHED_PANE_HEIGHT"

    # Composite panes using AWK
    awk -v LW="$CACHED_HALF_WIDTH" -v RW="$CACHED_HALF_WIDTH" -v H="$CACHED_PANE_HEIGHT" \
        -f <(printf '%s\n' "$AWK_COMPOSITOR") \
        "${PANE_0[render_file]}" "${PANE_1[render_file]}" \
        "$CACHED_HALF_WIDTH" "$CACHED_HALF_WIDTH" "$CACHED_PANE_HEIGHT"

    # Draw footer
    tput cup $((CACHED_TERM_HEIGHT - 2)) 0
    tput el
    printf " %s\n" "$STATUS_MESSAGE"
    tput el
    printf " F1 Help  F2 View  F3 Edit  F4 MkDir  F5 Copy  F6 Move  F7 Delete  F10 Quit"
    
    debug_log "UI drawn"
}

# Update a single line in a pane (for efficient partial updates)
# Arguments:
#   $1 - Pane name
#   $2 - Line number
#   $3 - Column offset
update_line() {
    local pane_name="$1"
    local line_num="$2"
    local col_offset="$3"
    local -n pane_ref=$pane_name

    local line_content
    line_content=$("$PANE_MANAGER_SCRIPT" get_line \
        --dir "${pane_ref[dir]}" \
        --cursor "${pane_ref[cursor_pos]}" \
        --scroll "${pane_ref[scroll_offset]}" \
        --marks-file "${pane_ref[marks_file]}" \
        --cache-file "${pane_ref[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "$pane_name" ] && echo "true" || echo "false")" \
        --height "$CACHED_PANE_HEIGHT" \
        --width "$CACHED_HALF_WIDTH" \
        --line "$line_num" 2>/dev/null || true)

    local render_file="$TEMP_DIR/line_update_$$"
    render_pane_to_file "$line_content" "$render_file" "$CACHED_HALF_WIDTH" "1"

    local display_line
    display_line=$(awk -v LW="$CACHED_HALF_WIDTH" -v RW="0" -v H="1" \
        -f <(printf '%s\n' "$AWK_COMPOSITOR") "$render_file" "/dev/null" "$CACHED_HALF_WIDTH" "0" "1")

    tput cup "$((line_num - pane_ref[scroll_offset]))" "$col_offset"
    printf "%s" "${display_line%│}"
    
    rm -f "$render_file"
}

# ==============================================================================
# USER INTERACTION FUNCTIONS
# ==============================================================================

# Suspend UI and run external command
# Arguments:
#   $1 - Command to run
#   $@ - Arguments to command
# Side effects:
#   Temporarily exits alternate screen, runs command, restores UI
suspend_and_run() {
    local cmd="$1"
    shift
    
    debug_log "Suspending UI to run: $cmd $*"
    
    # Exit alternate screen and restore terminal
    tput rmcup
    tput cnorm
    stty "$OLD_STTY"

    # Run command
    "$cmd" "$@" || true

    # Re-enter alternate screen
    tput smcup
    tput civis
    stty -echo -icanon -ixon 2>/dev/null || true
    
    # Refresh UI
    refresh_panes
    draw_ui
    
    debug_log "UI restored"
}

# Prompt user for input
# Arguments:
#   $1 - Prompt text
#   $2 - Variable name to store result
# Side effects:
#   Temporarily enables echo and canonical mode
input_prompt() {
    local prompt_text="$1"
    local result_var="$2"
    
    tput cup $((CACHED_TERM_HEIGHT - 1)) 0
    tput el
    printf "%s" "$prompt_text"
    tput cnorm 
    stty echo icanon
    
    local input_val
    read -r input_val
    
    stty -echo -icanon -ixon
    tput civis
    
    # Safe variable assignment without eval
    printf -v "$result_var" "%s" "$input_val"
    
    debug_log "User input: $input_val"
}

# Confirm destructive action
# Arguments:
#   $1 - Confirmation prompt
# Returns:
#   0 if confirmed, 1 if cancelled
confirm_action() {
    local prompt="$1"
    local response
    
    input_prompt "$prompt (y/N): " response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# FILE OPERATION FUNCTIONS
# ==============================================================================

# View the selected file with external viewer
view_file() {
    local filepath
    filepath=$(get_active_file_path)
    
    if [[ -z "$filepath" ]]; then
        STATUS_MESSAGE="No file selected to view."
        return
    fi

    # Try external openers first
    if command -v xdg-open &>/dev/null; then
        setsid xdg-open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    elif command -v open &>/dev/null; then
        open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    else
        # Fall back to pager
        STATUS_MESSAGE="External opener not found. Using pager."
        suspend_and_run "$FILE_VIEWER" "$filepath"
    fi
    
    debug_log "Viewed file: $filepath"
}

# Edit the selected file
edit_file() {
    local filepath
    filepath=$(get_active_file_path)
    
    if [[ -z "$filepath" ]] || [[ -d "$filepath" ]]; then
        STATUS_MESSAGE="Cannot edit: Is a directory or nothing selected."
        return
    fi
    
    suspend_and_run "$FILE_EDITOR" "$filepath"
    STATUS_MESSAGE="Edited '$filepath'."
    
    debug_log "Edited file: $filepath"
}

# Create a new directory
make_directory() {
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local current_dir="${active_pane_ref[dir]}"
    local dirname=""
    
    input_prompt "MkDir: " dirname
    
    if [[ -z "$dirname" ]]; then
        STATUS_MESSAGE="MkDir cancelled."
        return
    fi
    
    # Validate directory name
    if ! validate_dirname "$dirname"; then
        STATUS_MESSAGE="Invalid directory name."
        error_log "Invalid directory name attempted: $dirname"
        return
    fi
    
    # Create directory
    if mkdir -p "$current_dir/$dirname" 2>/dev/null; then
        STATUS_MESSAGE="Created directory: $dirname"
        refresh_panes
        debug_log "Created directory: $current_dir/$dirname"
    else
        STATUS_MESSAGE="Error creating directory."
        error_log "Failed to create directory: $current_dir/$dirname"
    fi
}

# Perform file operation (copy, move, delete)
# Arguments:
#   $1 - Operation type: "copy", "move", or "delete"
perform_file_operation() {
    local operation="$1"
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local inactive_pane_name
    inactive_pane_name=$(get_inactive_pane_name)
    local -n inactive_pane_ref=$inactive_pane_name

    # Get selected files
    local files_to_operate_on
    readarray -t files_to_operate_on < <("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}" 2>/dev/null || true)

    if [[ ${#files_to_operate_on[@]} -eq 0 ]]; then
        STATUS_MESSAGE="No files selected."
        return
    fi

    # Confirm destructive operations
    if [[ "$operation" == "delete" ]]; then
        if ! confirm_action "Delete ${#files_to_operate_on[@]} file(s)?"; then
            STATUS_MESSAGE="Delete cancelled."
            return
        fi
    fi

    local dest_dir="${inactive_pane_ref[dir]}"
    local success_count=0
    local error_count=0

    # Perform operation on each file
    for src_path in "${files_to_operate_on[@]}"; do
        [[ -e "$src_path" ]] || continue
        
        case "$operation" in
            copy)
                if cp -r "$src_path" "$dest_dir/" 2>/dev/null; then
                    success_count=$((success_count+1))
                    debug_log "Copied: $src_path -> $dest_dir/"
                else
                    error_count=$((error_count+1))
                    error_log "Failed to copy: $src_path"
                fi
                ;;
            move)
                if mv "$src_path" "$dest_dir/" 2>/dev/null; then
                    success_count=$((success_count+1))
                    debug_log "Moved: $src_path -> $dest_dir/"
                else
                    error_count=$((error_count+1))
                    error_log "Failed to move: $src_path"
                fi
                ;;
            delete)
                if rm -rf "$src_path" 2>/dev/null; then
                    success_count=$((success_count+1))
                    debug_log "Deleted: $src_path"
                else
                    error_count=$((error_count+1))
                    error_log "Failed to delete: $src_path"
                fi
                ;;
        esac
    done

    # Report results
    STATUS_MESSAGE="Successfully performed '$operation' on $success_count file(s)."
    if [[ $error_count -gt 0 ]]; then 
        STATUS_MESSAGE="$STATUS_MESSAGE Errors on $error_count file(s)."
    fi
    
    refresh_panes
}

# ==============================================================================
# KEY HANDLING FUNCTIONS
# ==============================================================================

# Handle navigation keys (arrows, page up/down, home, end)
# Arguments:
#   $1 - Key sequence
#   $2 - Reference to common_args array
# Returns:
#   CSV list of lines to update (via stdout)
handle_navigation_key() {
    local key="$1"
    shift
    local common_args=("$@")
    local -n pane_ref=$ACTIVE_PANE_NAME
    local new_state=""
    local needs_full_redraw=0

    case "$key" in
        $'\e[A') # Up
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "up" "${common_args[@]}" 2>/dev/null || true)
            ;;
        $'\e[B') # Down
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "down" "${common_args[@]}" 2>/dev/null || true)
            ;;
        $'\e[5~') # Page Up
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "page_up" --step $((CACHED_PANE_HEIGHT - 2)) "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
        $'\e[6~') # Page Down
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "page_down" --step $((CACHED_PANE_HEIGHT - 2)) "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
        $'\e[H'|$'\e[1~') # Home
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "home" "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
        $'\e[F'|$'\e[4~') # End
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "end" "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
        $'\e[C'|'') # Enter / Right arrow
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "enter" "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
        $'\e[D'|$'\x7f') # Back / Backspace / Left arrow
            new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "back" "${common_args[@]}" 2>/dev/null || true)
            needs_full_redraw=1
            ;;
    esac

    if [[ -n "$new_state" ]]; then
        update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
    fi

    # Return whether full redraw is needed
    echo "$needs_full_redraw"
}

# Handle function keys (F1-F10)
# Arguments:
#   $1 - Key sequence
handle_function_key() {
    local key="$1"

    case "$key" in
        $'\eOP'|$'\e[11~') # F1 - Help
            STATUS_MESSAGE="Nav: Arrows/PgUp/PgDn/Home/End. Tab: Switch. Space/Ins: Mark. F10: Exit."
            draw_ui
            ;;
        $'\eOQ'|$'\e[12~') # F2 - View
            view_file
            draw_ui
            ;;
        $'\eOR'|$'\e[13~') # F3 - Edit
            edit_file
            draw_ui
            ;;
        $'\eOS'|$'\e[14~') # F4 - Make Directory
            make_directory
            draw_ui
            ;;
        $'\e[15~') # F5 - Copy
            perform_file_operation "copy"
            draw_ui
            ;;
        $'\e[17~') # F6 - Move
            perform_file_operation "move"
            draw_ui
            ;;
        $'\e[18~') # F7 - Delete
            perform_file_operation "delete"
            draw_ui
            ;;
        $'\e[21~'|$'\e[24~') # F10 - Quit
            return 1
            ;;
    esac
    
    return 0
}

# Handle pane switching (Tab key)
handle_pane_switch() {
    local old_active_pane_name=$ACTIVE_PANE_NAME
    local -n old_active_pane_ref=$old_active_pane_name
    
    # Switch active pane
    ACTIVE_PANE_NAME=$(get_inactive_pane_name)
    local -n new_active_pane_ref=$ACTIVE_PANE_NAME
    
    # Update both cursor lines
    local old_col_offset
    local new_col_offset
    
    if [[ "$old_active_pane_name" == "PANE_0" ]]; then
        old_col_offset=0
        new_col_offset=$((CACHED_HALF_WIDTH + 1))
    else
        old_col_offset=$((CACHED_HALF_WIDTH + 1))
        new_col_offset=0
    fi
    
    update_line "$old_active_pane_name" "${old_active_pane_ref[cursor_pos]}" "$old_col_offset"
    update_line "$ACTIVE_PANE_NAME" "${new_active_pane_ref[cursor_pos]}" "$new_col_offset"
    
    debug_log "Switched to $ACTIVE_PANE_NAME"
}

# Handle mark toggle (Space / Insert)
# Arguments:
#   $@ - Common args array
handle_mark_toggle() {
    local common_args=("$@")
    local -n pane_ref=$ACTIVE_PANE_NAME
    
    local new_state
    new_state=$("$PANE_MANAGER_SCRIPT" toggle_mark "${common_args[@]}" 2>/dev/null || true)
    update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
    
    local lines_to_update_csv=${pane_ref[lines_to_update]}
    
    # If no partial update info, do full redraw
    if [[ -z "$lines_to_update_csv" ]]; then
        draw_ui
    else
        echo "$lines_to_update_csv"
    fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
    local start_dir_0=${1:-"$(pwd)"}
    local start_dir_1=${2:-"$HOME"}

    # Initialize
    check_dependencies
    init_terminal
    cache_dimensions
    
    # Initialize panes
    if ! init_pane PANE_0 "$start_dir_0" "$CACHED_PANE_HEIGHT" "$CACHED_HALF_WIDTH"; then
        echo "Failed to initialize PANE_0" >&2
        exit 1
    fi
    
    if ! init_pane PANE_1 "$start_dir_1" "$CACHED_PANE_HEIGHT" "$CACHED_HALF_WIDTH"; then
        echo "Failed to initialize PANE_1" >&2
        exit 1
    fi

    draw_ui
    
    debug_log "Entering main loop"
    
    # Main event loop
    while true; do
        # Check for window resize
        if [[ $NEEDS_REDRAW -eq 1 ]]; then
            cache_dimensions
            refresh_panes
            draw_ui
            NEEDS_REDRAW=0
            debug_log "Window resized and redrawn"
        fi

        # Read input with timeout to catch resize signals
        local key
        if ! IFS= read -rsn1 -t "$INPUT_TIMEOUT" key; then
            continue # No key pressed, loop back to check NEEDS_REDRAW
        fi

        # Handle escape sequences
        if [[ "$key" == $'\e' ]]; then
            local seq=""
            while read -rsn1 -t "$ESCAPE_SEQ_TIMEOUT" char; do 
                seq="$seq$char"
            done
            key="$key$seq"
        fi

        STATUS_MESSAGE=""
        local -n pane_ref=$ACTIVE_PANE_NAME
        local lines_to_update_csv=""

        # Build common arguments for pane manager script
        local common_args=(
            --dir "${pane_ref[dir]}"
            --cursor "${pane_ref[cursor_pos]}"
            --scroll "${pane_ref[scroll_offset]}"
            --marks-file "${pane_ref[marks_file]}"
            --cache-file "${pane_ref[cache_file]}"
            --height "$CACHED_PANE_HEIGHT"
        )

        # Route key to appropriate handler
        case "$key" in
            # Navigation keys
            $'\e[A'|$'\e[B'|$'\e[5~'|$'\e[6~'|$'\e[H'|$'\e[1~'|$'\e[F'|$'\e[4~'|$'\e[C'|''|$'\e[D'|$'\x7f')
                local needs_full_redraw
                needs_full_redraw=$(handle_navigation_key "$key" "${common_args[@]}")
                
                if [[ "$needs_full_redraw" == "1" ]]; then
                    draw_ui
                else
                    lines_to_update_csv=${pane_ref[lines_to_update]}
                fi
                ;;
            
            # Tab - switch panes
            $'\t')
                handle_pane_switch
                ;;
            
            # Space / Insert - toggle mark
            ' '|$'\e[2~')
                lines_to_update_csv=$(handle_mark_toggle "${common_args[@]}")
                ;;
            
            # Ctrl+R - refresh
            $'\x12')
                refresh_panes
                draw_ui
                ;;
            
            # Function keys
            $'\eOP'|$'\e[11~'|$'\eOQ'|$'\e[12~'|$'\eOR'|$'\e[13~'|$'\eOS'|$'\e[14~'|$'\e[15~'|$'\e[17~'|$'\e[18~'|$'\e[21~'|$'\e[24~')
                if ! handle_function_key "$key"; then
                    break # F10 or quit
                fi
                ;;
            
            # 'q' - quit
            'q')
                break
                ;;
        esac

        # Perform partial line updates if needed
        if [[ -n "$lines_to_update_csv" ]] && [[ "$NEEDS_REDRAW" -eq 0 ]]; then
            local col_offset
            if [[ "$ACTIVE_PANE_NAME" == "PANE_0" ]]; then
                col_offset=0
            else
                col_offset=$((CACHED_HALF_WIDTH + 1))
            fi
            
            IFS=',' read -ra lines_to_update_arr <<< "$lines_to_update_csv"
            for line_num in "${lines_to_update_arr[@]}"; do
                update_line "$ACTIVE_PANE_NAME" "$line_num" "$col_offset"
            done
        fi
    done
    
    debug_log "Exiting main loop"
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    main "$@"
fi
