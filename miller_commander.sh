#!/usr/bin/env bash
# ==============================================================================
# BASH MILLER COMMANDER
# ==============================================================================
#
# A two-pane file manager using Miller columns, inspired by Midnight Commander.
# It uses a separate script, file_selector.sh, to manage the state of each
# pane, making this script the main controller for the UI and user input.
#

# --- Strict Mode & Globals ---
set -euo pipefail

# --- Script Dependencies & Constants ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PANE_MANAGER_SCRIPT="$SCRIPT_DIR/file_selector.sh"
if [ ! -x "$PANE_MANAGER_SCRIPT" ]; then
    echo "Error: The pane manager script '$PANE_MANAGER_SCRIPT' is not executable or not found." >&2
    exit 1
fi

# --- Global State ---
# Associative arrays to hold the state for each pane
declare -A PANE_0 PANE_1
ACTIVE_PANE_NAME="PANE_0" # The name of the currently active pane
STATUS_MESSAGE=""

# --- Terminal Handling & Cleanup ---
# Function to be called on script exit to restore the terminal state
cleanup() {
    # Restore terminal settings
    stty echo
    # Show cursor
    tput cnorm
    # Switch back to the main screen buffer
    tput rmcup
    # Clean up temporary files
    rm -f "${PANE_0[marks_file]}" "${PANE_0[cache_file]}" 2>/dev/null || true
    rm -f "${PANE_1[marks_file]}" "${PANE_1[cache_file]}" 2>/dev/null || true
}
trap cleanup EXIT

# Hide cursor and switch to alternate screen buffer at the start
tput smcup
tput civis
# Ensure stty is reset if the script is interrupted
stty -echo

# --- Pane Management ---
# Securely updates a pane's state from the pane manager's output
update_pane_state() {
    local -n pane_ref=$1
    local input_state="$2"

    while IFS='=' read -r key value; do
        if [[ -n "$key" ]]; then
            pane_ref[$key]="$value"
        fi
    done <<< "$input_state"
}
# Initializes a pane's state using the pane manager script
init_pane() {
    local -n pane_ref=$1 # Use a nameref to the associative array (PANE_0 or PANE_1)
    local start_dir="$2"
    local pane_height="$3"
    local pane_width="$4"

    # Create temp files for marks and cache
    pane_ref[marks_file]=$(mktemp)
    pane_ref[cache_file]=$(mktemp)

    # Get the initial state from the pane manager
    local new_state
    new_state=$("$PANE_MANAGER_SCRIPT" init \
        --dir "$start_dir" \
        --marks-file "${pane_ref[marks_file]}" \
        --cache-file "${pane_ref[cache_file]}")

    update_pane_state "$1" "$new_state"
}

# Updates a pane's state based on a navigation action
navigate_pane() {
    local -n pane_ref=$1
    local direction="$2"

    local new_state
    local term_height
    term_height=$(tput lines)
    local pane_height=$((term_height - 3))

    new_state=$("$PANE_MANAGER_SCRIPT" navigate \
        --dir "${pane_ref[dir]}" \
        --cursor "${pane_ref[cursor_pos]}" \
        --scroll "${pane_ref[scroll_offset]}" \
        --marks-file "${pane_ref[marks_file]}" \
        --cache-file "${pane_ref[cache_file]}" \
        --direction "$direction" \
        --height "$pane_height")

    update_pane_state "$1" "$new_state"
}

# --- File Operations ---
perform_file_operation() {
    local operation="$1"
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local inactive_pane_name=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
    local -n inactive_pane_ref=$inactive_pane_name

    readarray -t files_to_operate_on < <("$PANE_MANAGER_SCRIPT" get_selection \
        --dir "${active_pane_ref[dir]}" \
        --cursor "${active_pane_ref[cursor_pos]}" \
        --marks-file "${active_pane_ref[marks_file]}" \
        --cache-file "${active_pane_ref[cache_file]}")

    if [ ${#files_to_operate_on[@]} -eq 0 ]; then
        STATUS_MESSAGE="No files selected."
        return
    fi

    local dest_dir="${inactive_pane_ref[dir]}"
    local success_count=0
    local error_count=0

    for src_path in "${files_to_operate_on[@]}"; do
        if [ ! -e "$src_path" ]; then continue; fi
        case "$operation" in
            copy)
                if cp -r "$src_path" "$dest_dir/"; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            move)
                if mv "$src_path" "$dest_dir/"; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            delete)
                if rm -rf "$src_path"; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
        esac
    done

    STATUS_MESSAGE="Successfully performed '$operation' on $success_count file(s)."
    if [ $error_count -gt 0 ]; then
        STATUS_MESSAGE="$STATUS_MESSAGE Errors on $error_count file(s)."
    fi

    # After any file operation, re-index both panes to reflect changes
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$((term_width / 2))
    local pane_height=$((term_height - 3))
    init_pane "$ACTIVE_PANE_NAME" "${active_pane_ref[dir]}" "$pane_height" "$half_width"
    init_pane "$inactive_pane_name" "${inactive_pane_ref[dir]}" "$pane_height" "$half_width"
}


# --- UI Drawing ---
draw_ui() {
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$((term_width / 2))
    local pane_height=$((term_height - 3)) # Reserve lines for top/bottom bars

    # Clear screen
    tput clear

    # --- Draw Panes ---
    local -n active_pane_ref=$ACTIVE_PANE_NAME
    local inactive_pane_name=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
    local -n inactive_pane_ref=$inactive_pane_name

    # Get pane content from the manager script
    local pane0_content
    pane0_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_0[dir]}" \
        --cursor "${PANE_0[cursor_pos]}" \
        --scroll "${PANE_0[scroll_offset]}" \
        --marks-file "${PANE_0[marks_file]}" \
        --cache-file "${PANE_0[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "true" || echo "false")" \
        --height "$pane_height" \
        --width "$half_width")

    local pane1_content
    pane1_content=$("$PANE_MANAGER_SCRIPT" get_pane_content \
        --dir "${PANE_1[dir]}" \
        --cursor "${PANE_1[cursor_pos]}" \
        --scroll "${PANE_1[scroll_offset]}" \
        --marks-file "${PANE_1[marks_file]}" \
        --cache-file "${PANE_1[cache_file]}" \
        --is-active "$([ "$ACTIVE_PANE_NAME" == "PANE_1" ] && echo "true" || echo "false")" \
        --height "$pane_height" \
        --width "$half_width")

    # Use paste to draw columns side-by-side
    paste -d '|' <(echo "$pane0_content") <(echo "$pane1_content")

    # --- Draw Bottom Bar ---
    tput cup $((term_height - 1)) 0
    tput el
    echo -n " F1 Help  F2 View  F3 Edit  F4 MkDir  F5 Copy  F6 Move  F7 Delete  F10 Quit"
    tput cup $((term_height - 2)) 0
    tput el
    echo -n " $STATUS_MESSAGE"
}


# --- Main Application Logic ---
main() {
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local half_width=$((term_width / 2))
    local pane_height=$((term_height - 3))

    # Initialize both panes, allowing overrides from command-line arguments
    local start_dir_0=${1:-"$(pwd)"}
    local start_dir_1=${2:-"$HOME"}
    init_pane PANE_0 "$start_dir_0" "$pane_height" "$half_width"
    init_pane PANE_1 "$start_dir_1" "$pane_height" "$half_width"

    while true; do
        draw_ui

        # Read a single character of input, clearing IFS to read spaces literally
        local key
        IFS= read -rsn1 key

        # Handle multi-byte escape sequences for arrow keys, etc.
        if [[ "$key" == $'\e' ]]; then
            local seq=""
            # Read the rest of the sequence
            while read -rsn1 -t 0.05 char; do
                seq="$seq$char"
            done
            key="$key$seq"
        fi

        STATUS_MESSAGE="" # Clear status on new keypress

        case "$key" in
            # Navigation
            $'\e[A') navigate_pane "$ACTIVE_PANE_NAME" "up" ;;
            $'\e[B') navigate_pane "$ACTIVE_PANE_NAME" "down" ;;
            $'\e[C') navigate_pane "$ACTIVE_PANE_NAME" "enter" ;;
            $'\e[D') navigate_pane "$ACTIVE_PANE_NAME" "back" ;;
            '')   navigate_pane "$ACTIVE_PANE_NAME" "enter" ;; # Enter key

            # Pane switching
            $'\t') # Tab key
                ACTIVE_PANE_NAME=$([ "$ACTIVE_PANE_NAME" == "PANE_0" ] && echo "PANE_1" || echo "PANE_0")
                ;;

            # Marking files
            ' ') # Space bar
                local -n pane_ref=$ACTIVE_PANE_NAME
                # The toggle_mark script now returns the new state, so we must capture it.
                local new_state
                new_state=$("$PANE_MANAGER_SCRIPT" toggle_mark \
                    --dir "${pane_ref[dir]}" \
                    --cursor "${pane_ref[cursor_pos]}" \
                    --scroll "${pane_ref[scroll_offset]}" \
                    --marks-file "${pane_ref[marks_file]}" \
                    --cache-file "${pane_ref[cache_file]}")

                update_pane_state "$ACTIVE_PANE_NAME" "$new_state"
                ;;

            # Function Keys
            $'\e[11~') # F1 Help
                STATUS_MESSAGE="Help: Use arrow keys, Tab to switch, Space to mark, F-keys for actions."
                ;;
            $'\e[12~') # F2 View
                STATUS_MESSAGE="View operation not implemented."
                ;;
            $'\e[13~') # F3 Edit
                STATUS_MESSAGE="Edit operation not implemented."
                ;;
            $'\e[14~') # F4 MkDir
                STATUS_MESSAGE="MkDir operation not implemented."
                ;;
            $'\e[15~') # F5 Copy
                perform_file_operation "copy"
                ;;
            $'\e[17~') # F6 Move
                perform_file_operation "move"
                ;;
            $'\e[18~') # F7 Delete
                perform_file_operation "delete"
                ;;
            $'\e[19~') # F8 Back
                navigate_pane "$ACTIVE_PANE_NAME" "back"
                ;;
            $'\e[21~') # F10 Quit
                break
                ;;

            # Quit
            'q')
                break
                ;;
        esac
    done
}

# --- Script Entry Point ---
# Ensure the script is not being sourced
if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    main "$@"
fi
