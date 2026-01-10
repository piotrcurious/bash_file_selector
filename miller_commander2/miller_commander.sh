#!/usr/bin/env bash
# ==============================================================================
# BASH MILLER COMMANDER (Expanded)
# Complete Function Key Support, External Editor, and Forked Viewer
# ==============================================================================
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PANE_MANAGER_SCRIPT="$SCRIPT_DIR/file_selector.sh"

# Check dependencies
if [ ! -x "$PANE_MANAGER_SCRIPT" ]; then
    echo "Error: The pane manager script '$PANE_MANAGER_SCRIPT' is not executable or not found." >&2
    exit 1
fi

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
}
trap cleanup EXIT INT TERM HUP

# Enter alt screen, hide cursor, disable echo/canonical
tput smcup
tput civis
stty -echo -icanon -ixon 2>/dev/null || true

# ==============================================================================
#  HELPER FUNCTIONS
# ==============================================================================

# --- UI State Management ---

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
    # Helper: Extract single file path from pane manager selection logic
    # Note: We use the 'get_selection' but restrict it to the cursor if no marks
    local selection
    selection=$("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}" 2>/dev/null || true)
    
    # If multiple selected (via marks), just return the first one, 
    # or empty if nothing valid.
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

# --- External Interactions (Editors/Viewers) ---

# Temporarily leave TUI mode to run a foreground interactive command (Editor)
suspend_and_run() {
    local cmd="$1"
    shift
    
    # 1. Restore terminal
    tput rmcup
    tput cnorm
    stty "$OLD_STTY"

    # 2. Run command
    "$cmd" "$@" || true

    # 3. Resume TUI
    tput smcup
    tput civis
    stty -echo -icanon -ixon 2>/dev/null || true
    
    # Force full redraw
    refresh_panes
    draw_ui
}

# Prompt user for string input (at bottom of screen)
input_prompt() {
    local prompt_text="$1"
    local result_var="$2"
    
    local term_height=$(tput lines)
    
    # Move to footer
    tput cup $((term_height - 1)) 0
    tput el
    printf "%s" "$prompt_text"
    tput cnorm # Show cursor
    
    # We must enable echo/canon to allow user typing/backspacing
    stty echo icanon
    
    read -r input_val
    
    # Restore raw mode
    stty -echo -icanon -ixon
    tput civis
    
    eval "$result_var=\"\$input_val\""
}

# F2: View File (Forked/External)
view_file() {
    local filepath
    filepath=$(get_active_file_path)
    
    if [ -z "$filepath" ]; then
        STATUS_MESSAGE="No file selected to view."
        return
    fi

    # Try to use system default opener (xdg-open or open)
    # This forks the process so the terminal isn't blocked, 
    # relying on the OS to pick the right program.
    if command -v xdg-open &>/dev/null; then
        setsid xdg-open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    elif command -v open &>/dev/null; then
        open "$filepath" >/dev/null 2>&1 &
        STATUS_MESSAGE="Opened '$filepath' externally."
    else
        # Fallback: internal TUI viewer (less)
        STATUS_MESSAGE="External opener not found. Using pager."
        suspend_and_run "${PAGER:-less}" "$filepath"
    fi
}

# F3: Edit File
edit_file() {
    local filepath
    filepath=$(get_active_file_path)
    
    if [ -z "$filepath" ] || [ -d "$filepath" ]; then
        STATUS_MESSAGE="Cannot edit: Is a directory or nothing selected."
        return
    fi
    
    # Use environment EDITOR or default to nano
    suspend_and_run "${EDITOR:-nano}" "$filepath"
    STATUS_MESSAGE="Edited '$filepath'."
}

# F4: Make Directory
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

# F5/F6/F7 Operations
perform_file_operation() {
    local operation="$1"
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local inactive_pane_name=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
    local -n inactive_pane_ref=$inactive_pane_name

    readarray -t files_to_operate_on < <("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}" 2>/dev/null || true)

    if [ ${#files_to_operate_on[@]} -eq 0 ]; then
        STATUS_MESSAGE="No files selected."
        return
    fi

    local dest_dir="${inactive_pane_ref[dir]}"
    local success_count=0
    local error_count=0

    for src_path in "${files_to_operate_on[@]}"; do
        [ -e "$src_path" ] || continue
        case "$operation" in
            copy) if cp -r "$src_path" "$dest_dir/"; then success_count=$((success_count+1)); else error_count=$((error_count+1)); fi ;;
            move) if mv "$src_path" "$dest_dir/"; then success_count=$((success_count+1)); else error_count=$((error_count+1)); fi ;;
            delete) if rm -rf "$src_path"; then success_count=$((success_count+1)); else error_count=$((error_count+1)); fi ;;
        esac
    done

    STATUS_MESSAGE="Successfully performed '$operation' on $success_count file(s)."
    if [ $error_count -gt 0 ]; then STATUS_MESSAGE="$STATUS_MESSAGE Errors on $error_count file(s)."; fi

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

# ---------- AWK compositor (ANSI-aware, called once per frame) ----------
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

# ---------- draw_ui ----------
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
    # Updated footer to reflect full functionality
    printf " F1 Help  F2 View  F3 Edit  F4 MkDir  F5 Copy  F6 Move  F7 Delete  F10 Quit"
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
    display_line=$(awk -v LW="$half_width" -v RW="0" -v H="1" \
        -f <(printf '%s\n' "$AWK_COMPOSITOR") "$render_file" "/dev/null" "$half_width" "0" "1")

    tput cup "$((line_num - pane_ref[scroll_offset]))" "$col_offset"
    printf "%s" "${display_line%│}"
    rm -f "$render_file"
}

# ---------- main ----------
main() {
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$(( (term_width - 1) / 2 ))
    local pane_height=$((term_height - 2))

    local start_dir_0=${1:-"$(pwd)"}
    local start_dir_1=${2:-"$HOME"}
    init_pane PANE_0 "$start_dir_0" "$pane_height" "$half_width"
    init_pane PANE_1 "$start_dir_1" "$pane_height" "$half_width"

    draw_ui
    while true; do
        local key
        IFS= read -rsn1 key || key=""

        # Read escaped sequences (e.g. arrow keys, F-keys)
        if [[ "$key" == $'\e' ]]; then
            local seq=""
            # Small timeout to read remaining sequence bytes
            while read -rsn1 -t 0.005 char; do seq="$seq$char"; done
            key="$key$seq"
        fi

        STATUS_MESSAGE=""
        local -n pane_ref=$ACTIVE_PANE_NAME
        local lines_to_update_csv=""

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
                lines_to_update_csv=${pane_ref[lines_to_update]}
                ;;
            $'\e[B') # Down
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "down" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                lines_to_update_csv=${pane_ref[lines_to_update]}
                ;;
            $'\e[C'|'') # Enter
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "enter" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_ui
                ;;
            $'\e[D') # Back
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" navigate --direction "back" "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                draw_ui
                ;;
            $'\t') # Tab
                local old_active_pane_name=$ACTIVE_PANE_NAME
                local -n old_active_pane_ref=$old_active_pane_name
                ACTIVE_PANE_NAME=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
                local -n new_active_pane_ref=$ACTIVE_PANE_NAME

                update_line "$old_active_pane_name" "${old_active_pane_ref[cursor_pos]}" "$([ "$old_active_pane_name" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))"
                update_line "$ACTIVE_PANE_NAME" "${new_active_pane_ref[cursor_pos]}" "$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))"
                ;;
            ' ') # Space (Mark)
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" toggle_mark "${common_args[@]}" 2>/dev/null || true)
                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                lines_to_update_csv=${pane_ref[lines_to_update]}
                ;;
            
            # --- F-Keys (Covering variations) ---
            
            # F1 (Help)
            $'\eOP'|$'\e[11~') 
                STATUS_MESSAGE="Keys: Arrows/Enter, Tab: Switch, Space: Mark, F2: View, F3: Edit, F4: MkDir, F5-7: Ops"
                draw_ui 
                ;;
                
            # F2 (View - Forked)
            $'\eOQ'|$'\e[12~') 
                view_file
                draw_ui 
                ;;
                
            # F3 (Edit - Nano/Custom)
            $'\eOR'|$'\e[13~') 
                edit_file
                draw_ui 
                ;;
                
            # F4 (MkDir)
            $'\eOS'|$'\e[14~') 
                make_directory
                draw_ui 
                ;;
                
            # F5 (Copy)
            $'\e[15~') 
                perform_file_operation "copy"
                draw_ui 
                ;;
                
            # F6 (Move)
            $'\e[17~') 
                perform_file_operation "move"
                draw_ui 
                ;;
                
            # F7 (Delete)
            $'\e[18~') 
                perform_file_operation "delete"
                draw_ui 
                ;;
                
            # F10 (Quit)
            $'\e[21~'|$'\e[24~'|'q') 
                break 
                ;;
        esac

        if [ -n "$lines_to_update_csv" ]; then
            local col_offset=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo 0 || echo $((half_width + 1)))
            IFS=',' read -ra lines_to_update_arr <<< "$lines_to_update_csv"
            for line_num in "${lines_to_update_arr[@]}"; do
                update_line "$ACTIVE_PANE_NAME" "$line_num" "$col_offset"
            done
        else
            # Only full redraw if explicitly needed (draw_ui called inside case)
            :
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    main "$@"
fi
