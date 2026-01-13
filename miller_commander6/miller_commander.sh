#!/usr/bin/env bash
# ==============================================================================
# BASH MILLER COMMANDER (Complete with Advanced Navigation)
# ==============================================================================
# ==============================================================================
# BASH MILLER COMMANDER (With Instant Resize Support)
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LOG_FILE="$SCRIPT_DIR/commander.log"  
error_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "${LOG_FILE:-/dev/null}"
}
PANE_MANAGER_SCRIPT="$SCRIPT_DIR/file_selector.sh"

# Check dependencies
if [ ! -x "$PANE_MANAGER_SCRIPT" ]; then
    echo "Error: The pane manager script '$PANE_MANAGER_SCRIPT' is not executable or not found." >&2
    exit 1
fi

# Detect showkey availability
HAS_SHOWKEY=0
if command -v showkey &>/dev/null; then HAS_SHOWKEY=1; fi

# Global flag for resize
NEEDS_REDRAW=0
handle_resize() {
    NEEDS_REDRAW=1
}
trap handle_resize SIGWINCH

declare -A PANE_0 PANE_1
ACTIVE_PANE_NAME="PANE_0"
STATUS_MESSAGE=""

# Save stty so we can restore exact original state on exit
OLD_STTY=$(stty -g)

cleanup() {
    stty "$OLD_STTY" 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true

    # Clean temp files
    rm -f "${PANE_0[marks_file]:-}" "${PANE_0[cache_file]:-}" "${PANE_0[render_file]:-}" 2>/dev/null || true
    rm -f "${PANE_1[marks_file]:-}" "${PANE_1[cache_file]:-}" "${PANE_1[render_file]:-}" 2>/dev/null || true
    #rm -f "$LOG_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# Enter alt screen, hide cursor, disable echo/canonical
tput smcup
tput civis
#stty -echo -icanon -ixon -isig 2>/dev/null || true
#stty -echo -icanon -ixon -isig intr undef quit undef susp undef 2>/dev/null || true
#stty -echo -icanon -ixon -isig -brkint -inpck -istrip 2>/dev/null || true
stty -echo -icanon -ixon 2>/dev/null || true


# ==============================================================================
#  HELPER FUNCTIONS
# ==============================================================================

calculate_size() {
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local selection
    selection=$(get_active_file_path)

    if [ -z "$selection" ]; then
        STATUS_MESSAGE="Nothing selected to calculate."
        return
    fi

    if [ -d "$selection" ]; then
        STATUS_MESSAGE="Calculating directory size: $(basename "$selection")..."
        draw_ui # Show the status message
        
        # Calculate human-readable size of directory
        local dir_size
        dir_size=$(du -sh "$selection" 2>/dev/null | cut -f1)
        STATUS_MESSAGE="Size of '$(basename "$selection")': $dir_size"
    else
        # For files, just use ls or stat
        local file_size
        file_size=$(ls -lh "$selection" | awk '{print $5}')
        STATUS_MESSAGE="Size of '$(basename "$selection")': $file_size"
    fi
}

update_pane_state() {
    local -n pane_ref=$1
    local input_state="$2"
    pane_ref[lines_to_update]=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local key=${line%%=*}
        local value=${line#*=}
        pane_ref["$key"]="$value"
    done <<< "$input_state"
}

init_pane() {
    local -n pane_ref=$1
    local start_dir="$2"
    local pane_height="$3"
    local pane_width="$4"

    pane_ref[marks_file]=$(mktemp)
    pane_ref[cache_file]=$(mktemp)
    pane_ref[render_file]=$(mktemp)

    local new_state
    new_state=$("$PANE_MANAGER_SCRIPT" init \
        --dir "$start_dir" \
        --marks-file "${pane_ref[marks_file]}" \
        --cache-file "${pane_ref[cache_file]}" \
        --height "$pane_height" \
        --width "$pane_width" 2>/dev/null || true)

    update_pane_state "$1" "$new_state"
}

get_active_file_path() {
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local selection
    selection=$("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}" 2>/dev/null || true)

    if [ -n "$selection" ]; then
        echo "$selection" | head -n1
    else
        echo ""
    fi
}

refresh_panes() {
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$(( (term_width - 1) / 2 ))
    local pane_height=$((term_height - 2))

    local inactive_pane_name=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local -n inactive_pane_ref=$inactive_pane_name

    init_pane "$ACTIVE_PANE_NAME" "${active_pane_ref[dir]}" "$pane_height" "$half_width"
    init_pane "$inactive_pane_name" "${inactive_pane_ref[dir]}" "$pane_height" "$half_width"
}

suspend_and_run() {
    local cmd="$1"
    shift
    tput rmcup
    tput cnorm
    stty "$OLD_STTY"

    "$cmd" "$@" || true

    tput smcup
    tput civis
    stty -echo -icanon -ixon 2>/dev/null || true
    #stty -echo -icanon -ixon -isig -brkint -inpck -istrip 2>/dev/null || true

    refresh_panes
    draw_ui
}

input_prompt() {
    local prompt_text="$1"
    local result_var="$2"
    local term_height=$(tput lines)

    tput cup $((term_height - 1)) 0
    tput el
    printf "%s" "$prompt_text"
    tput cnorm
    stty echo icanon
    read -r input_val
    stty -echo -icanon -ixon
    tput civis
    printf -v "$result_var" "%s" "$input_val"
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

# Returns: 0=Yes, 1=No, 2=All
confirm_overwrite() {
    local target="$1"
    local response
    
    # Clean footer area and prompt
    tput cup $(( $(tput lines) - 1 )) 0
    tput el
    printf " File exists: %s. Overwrite? [n] y a: " "$(basename "$target")"
    
    tput cnorm
    stty echo icanon
    read -r response
    stty -echo -icanon -ixon
    tput civis

    case "$response" in
        [Aa]*) return 2 ;; # All
        [Yy]*) return 0 ;; # Yes
        *)     return 1 ;; # No (Default)
    esac
}

view_file() {
    local filepath
    filepath=$(get_active_file_path)
    if [ -z "$filepath" ]; then
        STATUS_MESSAGE="No file selected to view."
        return
    fi

    if command -v xdg-open &>/dev/null; then
        setsid xdg-open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    elif command -v open &>/dev/null; then
        open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    else
        STATUS_MESSAGE="External opener not found. Using pager."
        suspend_and_run "${PAGER:-less}" "$filepath"
    fi
}

edit_file() {
    local filepath
    filepath=$(get_active_file_path)
    if [ -z "$filepath" ] || [ -d "$filepath" ]; then
        STATUS_MESSAGE="Cannot edit: Is a directory or nothing selected."
        return
    fi
    suspend_and_run "${EDITOR:-nano}" "$filepath"
    STATUS_MESSAGE="Edited '$filepath'."
}

make_directory() {
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local current_dir="${active_pane_ref[dir]}"
    local dirname=""
    input_prompt "MkDir: " dirname

    if [ -n "$dirname" ]; then
        if mkdir -p "$current_dir/$dirname"; then
            STATUS_MESSAGE="Created directory: $dirname"
            refresh_panes
        else
            STATUS_MESSAGE="Error creating directory."
        fi
    else
        STATUS_MESSAGE="MkDir cancelled."
    fi
}



perform_file_operation() {
    local operation="$1"
    local source_pane_name="$ACTIVE_PANE_NAME"
    local -n source_pane_ref="$source_pane_name"
    local OVERWRITE_ALL=false
    local dest_dir=""

    # 1. Determine Destination
    if [[ "$operation" != "delete" ]]; then
        local dest_pane_name=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
        local -n dest_pane_ref="$dest_pane_name"
        dest_dir="${dest_pane_ref[dir]}"
        
        [[ "${source_pane_ref[dir]}" == "$dest_dir" ]] && { STATUS_MESSAGE="Source/Dest are same."; return; }
    fi

    # 2. Get Selected Files
    mapfile -t files_to_operate_on < <("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${source_pane_ref[dir]}" \
        --cursor "${source_pane_ref[cursor_pos]}" \
        --marks-file "${source_pane_ref[marks_file]}" \
        --cache-file "${source_pane_ref[cache_file]}" 2>/dev/null)

    [[ ${#files_to_operate_on[@]} -eq 0 ]] && { STATUS_MESSAGE="No files selected."; return; }

    # 3. Handle Deletion Confirmation (Global)
    if [[ "$operation" == "delete" ]]; then
        if ! confirm_action "Delete ${#files_to_operate_on[@]} items?"; then
            STATUS_MESSAGE="Delete cancelled."; return
        fi
    fi

    # 4. Process Loop
    local success_count=0 error_count=0 skipped_count=0

    for src_path in "${files_to_operate_on[@]}"; do
        [[ -e "$src_path" ]] || continue
        local filename=$(basename "$src_path")

        if [[ "$operation" != "delete" ]]; then
            local dest_path="$dest_dir/$filename"
            
            if [[ -e "$dest_path" ]]; then
                if [[ "$OVERWRITE_ALL" == "true" ]]; then
                    : # Proceed to operation
                else
                    local res=0
                    confirm_overwrite "$dest_path" || res=$?
                    if [[ $res -eq 1 ]]; then
                        skipped_count=$((skipped_count + 1))
                        continue
                    elif [[ $res -eq 2 ]]; then
                        OVERWRITE_ALL=true
                    fi
                fi
            fi
        fi

        case "$operation" in
            copy)   cp -r "$src_path" "$dest_dir/" && success_count=$((success_count+1)) || error_count=$((error_count+1)) ;;
            move)   mv "$src_path" "$dest_dir/" && success_count=$((success_count+1)) || error_count=$((error_count+1)) ;;
            delete) rm -rf "$src_path" && success_count=$((success_count+1)) || error_count=$((error_count+1)) ;;
        esac
    done

    STATUS_MESSAGE="Done: $success_count OK, $error_count Error, $skipped_count Skipped."
    refresh_panes
}



render_pane_to_file() {
    local pane_content="$1"
    local out_file="$2"
    local width="$3"
    local height="$4"
    printf "%s" "$pane_content" > "$out_file"
    local current_lines
    current_lines=$(wc -l < "$out_file" 2>/dev/null || echo 0)
    while [ "$current_lines" -lt "$height" ]; do
        printf "\n" >> "$out_file"
        current_lines=$((current_lines+1))
    done
}

# --- AWK SCRIPTS ---

# Existing compositor for full redraws (merges Left and Right)
AWK_COMPOSITOR='BEGIN {
  L = ARGV[1]; R = ARGV[2]; LW = ARGV[3]+0; RW = ARGV[4]+0; H = ARGV[5]+0;
  for(i=0;i<6;i++) ARGV[i]="";
  lcount = 0; while ((getline line < L) > 0) { lcount++; Larr[lcount] = line } close(L)
  rcount = 0; while ((getline line < R) > 0) { rcount++; Rarr[rcount] = line } close(R)
  ansi_re = "\033\\[[0-9;:?]*[A-Za-z]"
  for (i = 1; i <= H; i++) {
    l = (i <= lcount ? Larr[i] : "")
    r = (i <= rcount ? Rarr[i] : "")
    Lout = fmt(l, LW, ansi_re)
    Rout = fmt(r, RW, ansi_re)
    printf("%s│%s\n", Lout, Rout)
  }
  exit
}
function strip_ansi(s, t) { t = s; gsub(/\033\[[0-9;:?]*[A-Za-z]/, "", t); return t }
function vislen(s) { return length(strip_ansi(s)) }
function fmt(s, w, ansi_re, v, out, rem, matchpos, matchlen, token, count, need) {
  v = vislen(s)
  if (v == w) return s
  if (v < w) {
    need = w - v; out = s; for (j = 0; j < need; j++) out = out " "; return out
  }
  out = ""; rem = s; count = 0
  while (length(rem) > 0 && count < w) {
    if (match(rem, ansi_re)) {
      if (RSTART == 1) { out = out substr(rem, 1, RLENGTH); rem = substr(rem, RLENGTH+1); continue }
      else { out = out substr(rem, 1, 1); rem = substr(rem, 2); count++; continue }
    } else { need = w - count; out = out substr(rem, 1, need); break }
  }
  return out
}
'

# New Single Pane Renderer for Optimized Redraw
AWK_SINGLE_RENDERER='BEGIN {
  L = ARGV[1]; W = ARGV[2]+0; H = ARGV[3]+0;
  for(i=0;i<4;i++) ARGV[i]="";
  lcount = 0; while ((getline line < L) > 0) { lcount++; Larr[lcount] = line } close(L)
  ansi_re = "\033\\[[0-9;:?]*[A-Za-z]"
  for (i = 1; i <= H; i++) {
    l = (i <= lcount ? Larr[i] : "")
    printf("%s\n", fmt(l, W, ansi_re))
  }
  exit
}
function strip_ansi(s, t) { t = s; gsub(/\033\[[0-9;:?]*[A-Za-z]/, "", t); return t }
function vislen(s) { return length(strip_ansi(s)) }
function fmt(s, w, ansi_re, v, out, rem, matchpos, matchlen, token, count, need) {
  v = vislen(s)
  if (v == w) return s
  if (v < w) {
    need = w - v; out = s; for (j = 0; j < need; j++) out = out " "; return out
  }
  out = ""; rem = s; count = 0
  while (length(rem) > 0 && count < w) {
    if (match(rem, ansi_re)) {
      if (RSTART == 1) { out = out substr(rem, 1, RLENGTH); rem = substr(rem, RLENGTH+1); continue }
      else { out = out substr(rem, 1, 1); rem = substr(rem, 2); count++; continue }
    } else { need = w - count; out = out substr(rem, 1, need); break }
  }
  return out
}
'

# Full redraw of entire UI (Clears screen, draws both panes + separator + footer)
draw_ui() {
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local footer_lines=2
    local pane_height=$((term_height - footer_lines))
    local half_width=$(( (term_width - 1) / 2 ))

    tput clear
    : "${PANE_0[dir]:=$(pwd)}"
    : "${PANE_1[dir]:=$HOME}"

    local pane0_content pane1_content
    pane0_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_0[dir]}" --cursor "${PANE_0[cursor_pos]}" --scroll "${PANE_0[scroll_offset]}" \
        --marks-file "${PANE_0[marks_file]}" --cache-file "${PANE_0[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "true" || echo "false")" \
        --height "$pane_height" --width "$half_width" 2>/dev/null || true)

    pane1_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_1[dir]}" --cursor "${PANE_1[cursor_pos]}" --scroll "${PANE_1[scroll_offset]}" \
        --marks-file "${PANE_1[marks_file]}" --cache-file "${PANE_1[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_1" ] && echo "true" || echo "false")" \
        --height "$pane_height" --width "$half_width" 2>/dev/null || true)

    render_pane_to_file "$pane0_content" "${PANE_0[render_file]}" "$half_width" "$pane_height"
    render_pane_to_file "$pane1_content" "${PANE_1[render_file]}" "$half_width" "$pane_height"

    awk -v LW="$half_width" -v RW="$half_width" -v H="$pane_height" \
        -f <(printf '%s\n' "$AWK_COMPOSITOR") "${PANE_0[render_file]}" "${PANE_1[render_file]}" "$half_width" "$half_width" "$pane_height"

    tput cup $((term_height - 2)) 0
    tput el
    printf " %s\n" "$STATUS_MESSAGE"
    tput el
    printf " F1 Help  F2 Menu  F3 View  F4 Edit  F5 Copy  F6 Move  F7 MkDir  F8 Delete  F9 Pulldown  F10 Quit"
}

# [OPTIMIZATION]
# Draws ONLY the specified pane without clearing screen or touching the other pane
draw_single_pane() {
    local pane_name="$1"
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local footer_lines=2
    local pane_height=$((term_height - footer_lines))
    local half_width=$(( (term_width - 1) / 2 ))

    # Calculate offset
    local col_offset=0
    if [[ "$pane_name" == "PANE_1" ]]; then
        col_offset=$((half_width + 1))
    fi

    local -n pane_ref=$pane_name
    local pane_content
    pane_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${pane_ref[dir]}" --cursor "${pane_ref[cursor_pos]}" --scroll "${pane_ref[scroll_offset]}" \
        --marks-file "${pane_ref[marks_file]}" --cache-file "${pane_ref[cache_file]}" \
        --is-active "true" \
        --height "$pane_height" --width "$half_width" 2>/dev/null || true)

    render_pane_to_file "$pane_content" "${pane_ref[render_file]}" "$half_width" "$pane_height"

    # Use Single Renderer AWK to get formatted lines
    local formatted_lines
    mapfile -t formatted_lines < <(awk -v W="$half_width" -v H="$pane_height" \
        -f <(printf '%s\n' "$AWK_SINGLE_RENDERER") "${pane_ref[render_file]}" "$half_width" "$pane_height")

    # Print lines to specific screen location
    local r=0
    for line in "${formatted_lines[@]}"; do
        tput cup $r $col_offset
        printf "%s" "$line"
        r=$((r + 1))
    done
}

update_line() {
    local pane_name="$1"
    local line_num="$2"
    local col_offset="$3"
    local -n pane_ref=$pane_name

    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$(( (term_width - 1) / 2 ))
    local pane_height=$((term_height - 2))

    local line_content
    line_content=$("$PANE_MANAGER_SCRIPT" get_line \
        --dir "${pane_ref[dir]}" --cursor "${pane_ref[cursor_pos]}" --scroll "${pane_ref[scroll_offset]}" \
        --marks-file "${pane_ref[marks_file]}" --cache-file "${pane_ref[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "$pane_name" ] && echo "true" || echo "false")" \
        --height "$pane_height" --width "$half_width" \
        --line "$line_num" 2>/dev/null || true)

    local render_file
    render_file=$(mktemp)
    render_pane_to_file "$line_content" "$render_file" "$half_width" "1"

    local display_line
    # Use Single Renderer for single line too for consistency
    display_line=$(awk -v W="$half_width" -v H="1" \
        -f <(printf '%s\n' "$AWK_SINGLE_RENDERER") "$render_file" "$half_width" "1")

    tput cup "$((line_num - pane_ref[scroll_offset]))" "$col_offset"
    printf "%s" "$display_line"
    rm -f "$render_file"
}


# --- INPUT HANDLER ---
# Returns the key pressed. Handles Ctrl-Space specifically.

get_input() {
    local key
    # Standard read. We capture the exit status to handle timeouts.
    if ! IFS= read -rsn1 -t 0.1 key; then
        return 1
    fi

    # 1. Detect Ctrl-Space (now mapped to \x1f / Octal 037)
#    if [[ "$key" == $'\x1f' || "$key" == $'\x00' || -z "$key" ]]; then
#        echo "CTRL_SPACE"
#        return 0
#    fi

    # 2. Handle Escape Sequences (Arrows, F-keys)
    if [[ "$key" == $'\e' ]]; then
        local seq=""
        while read -rsn1 -t 0.005 char; do
            seq="$seq$char"
        done
        echo "$key$seq"
        return 0
    fi

    # 3. Handle Regular Keys (including Enter)
    echo "$key"
    return 0
}


# ---------- main ----------
main() {
    local start_dir_0=${1:-"$(pwd)"}
    local start_dir_1=${2:-"$HOME"}

    # Initial dimension capture
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$(( (term_width - 1) / 2 ))
    local pane_height=$((term_height - 2))

    init_pane PANE_0 "$start_dir_0" "$pane_height" "$half_width"
    init_pane PANE_1 "$start_dir_1" "$pane_height" "$half_width"

    draw_ui

    while true; do
        # 1. Check if a resize happened via the trap
        if [[ $NEEDS_REDRAW -eq 1 ]]; then
            term_height=$(tput lines)
            term_width=$(tput cols)
            half_width=$(( (term_width - 1) / 2 ))
            pane_height=$((term_height - 2))

            # Refresh caches with new dimensions
            refresh_panes
            draw_ui
            NEEDS_REDRAW=0
        fi

		# 1. Read input
		local key
        key=$(get_input) || continue
        
        # If get_input returned 1 (timeout), loop back to check for resizes
        if [[ $? -ne 0 ]]; then
            continue
        fi

        STATUS_MESSAGE=""
        local -n pane_ref=$ACTIVE_PANE_NAME
        local lines_to_update_csv=""
        
        # Capture scroll offset before navigation
        local old_scroll="${pane_ref[scroll_offset]}"

        local common_args=(
            --dir "${pane_ref[dir]}"
            --cursor "${pane_ref[cursor_pos]}"
            --scroll "${pane_ref[scroll_offset]}"
            --marks-file "${pane_ref[marks_file]}"
            --cache-file "${pane_ref[cache_file]}"
            --height "$pane_height"
        )

        case "$key" in
            # --- Navigation ---
            $'\e[A') # Up
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "up" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                
                # [FIX]: Check if scroll changed
                if [ "${pane_ref[scroll_offset]}" != "$old_scroll" ]; then
                    draw_single_pane "$ACTIVE_PANE_NAME"
                    lines_to_update_csv=""
                else
                    lines_to_update_csv=${pane_ref[lines_to_update]}
                fi
                ;;
            $'\e[B') # Down
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "down" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                
                # [FIX]: Check if scroll changed
                if [ "${pane_ref[scroll_offset]}" != "$old_scroll" ]; then
                    draw_single_pane "$ACTIVE_PANE_NAME"
                    lines_to_update_csv=""
                else
                    lines_to_update_csv=${pane_ref[lines_to_update]}
                fi
                ;;
            $'\e[5~') # Page Up
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "page_up" --step $((pane_height - 2)) "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_single_pane "$ACTIVE_PANE_NAME"
                ;;
            $'\e[6~') # Page Down
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "page_down" --step $((pane_height - 2)) "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_single_pane "$ACTIVE_PANE_NAME"
                ;;
            $'\e[H'|$'\e[1~') # Home
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "home" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_single_pane "$ACTIVE_PANE_NAME"
                ;;
            $'\e[F'|$'\e[4~') # End
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "end" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_single_pane "$ACTIVE_PANE_NAME"
                ;;
            $'\e[C]'|'') # Enter ('' handles Enter key)
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "enter" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_ui # Directory change affects everything usually
                ;;
            $'\e[D'|$'\x7f') # Back / Backspace
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "back" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_ui # Directory change affects everything
                ;;
            $'\t') # Tab
                local old_active_pane_name=$ACTIVE_PANE_NAME
                local -n old_active_pane_ref=$old_active_pane_name
                ACTIVE_PANE_NAME=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
                local -n new_active_pane_ref=$ACTIVE_PANE_NAME
                update_line "$old_active_pane_name" "${old_active_pane_ref[cursor_pos]}" "$([ "$old_active_pane_name" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))"
                update_line "$ACTIVE_PANE_NAME" "${new_active_pane_ref[cursor_pos]}" "$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))"
                ;;
            ' '|$'\e[2~') # Space / Insert
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" toggle_mark "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                lines_to_update_csv=${pane_ref[lines_to_update]}
                if [ -z "$lines_to_update_csv" ]; then draw_single_pane "$ACTIVE_PANE_NAME"; fi
                ;;

               # --- Ctrl-Space: Display Size ---
              $'\e[27;5;13~' | $'\e[13;5u' | $'\a' | $'\x07')
                calculate_size
                draw_ui
                ;;                
                
            $'\x12') # Ctrl+R
                refresh_panes
                draw_ui
                ;;
            $'\eOP'|$'\e[11~') # F1 Help
                STATUS_MESSAGE="Nav: Arrows/PgUp/PgDn/Home/End. Tab: Switch. Space/Ins: Mark. F10: Exit."
                draw_ui
                ;;
            $'\eOQ'|$'\e[12~') # F2 Menu
                STATUS_MESSAGE="F2 Menu: Not implemented."
                draw_ui
                ;;
            $'\eOR'|$'\e[13~') # F3 View
                view_file
                draw_ui
                ;;
            $'\eOS'|$'\e[14~') # F4 Edit
                edit_file
                draw_ui
                ;;
            $'\e[15~') # F5 Copy
                perform_file_operation "copy"
                draw_ui
                ;;
            $'\e[17~') # F6 Move
                perform_file_operation "move"
                draw_ui
                ;;
            $'\e[18~') # F7 MkDir
                make_directory
                draw_ui
                ;;
            $'\e[19~') # F8 Delete
                perform_file_operation "delete"
                draw_ui
                ;;
            $'\e[20~') # F9 Pulldown Menu
                STATUS_MESSAGE="F9 Pulldown Menu: Not implemented."
                draw_ui
                ;;
            $'\e[21~'|$'\e[24~'|'q') # F10 Quit
                break
                ;;
                
        esac

        # 4. Perform partial line updates if a full redraw wasn't triggered
        if [ -n "$lines_to_update_csv" ] && [ "$NEEDS_REDRAW" -eq 0 ]; then
            local col_offset=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))
            IFS=',' read -ra lines_to_update_arr <<< "$lines_to_update_csv"
            for line_num in "${lines_to_update_arr[@]}"; do
                update_line "$ACTIVE_PANE_NAME" "$line_num" "$col_offset"
            done
        fi
    done
}



if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    main "$@"
fi
