#!/usr/bin/env bash
# ==============================================================================
# TEST SUITE for miller_commander.sh using screen
# ==============================================================================

set -euo pipefail

# --- Globals & Setup ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
COMMANDER_SCRIPT="$SCRIPT_DIR/miller_commander.sh"
SESSION_NAME="mc_test_session_$$" # Use PID to ensure unique session name
TEST_DIR="test_environment"

setup() {
    echo "--- Setting up tests in '$TEST_DIR' ---"
    chmod +x "$COMMANDER_SCRIPT"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR/dir1/subdir" "$TEST_DIR/dir2"
    touch "$TEST_DIR/dir1/file1.txt"
    touch "$TEST_DIR/dir1/file2.txt"

    # Start screen session in detached mode
    screen -S "$SESSION_NAME" -d -m bash
    sleep 1 # Give screen time to start
}

# --- Teardown ---
teardown() {
    echo "--- Tearing down tests ---"
    screen -S "$SESSION_NAME" -X quit || true # Kill the screen session
    rm -rf "$TEST_DIR" screen_capture.txt
}
trap teardown EXIT

# --- Helper Functions ---
send_keys() {
    screen -S "$SESSION_NAME" -p 0 -X stuff "$1"
    sleep 0.8 # Adjust sleep to balance speed and reliability
}

capture_screen() {
    screen -S "$SESSION_NAME" -X hardcopy -h "screen_capture.txt"
    sleep 0.5
    echo "--- SCREEN CAPTURE ---"
    cat screen_capture.txt
    echo "----------------------"
}

# --- Test Cases ---
test_file_operations() {
    echo "[TEST] miller_commander.sh file operations"

    # Start the commander with dir1 in the left pane and dir2 in the right
    send_keys "$COMMANDER_SCRIPT $TEST_DIR/dir1 $TEST_DIR/dir2"
    send_keys $'\n'
    sleep 1

    # --- Test Copy ---
    echo "  Testing Copy (F5)..."
    # In miller_commander, 'space' marks a file AND moves the cursor down.
    # The test must reflect this behavior.
    send_keys $'\e[B'     # Down arrow (cursor moves from '..' to 'file1.txt')
    send_keys ' '        # Mark 'file1.txt' (cursor moves to 'file2.txt')
    send_keys ' '        # Mark 'file2.txt' (cursor moves to end of list)

    # F5 to copy to the inactive (right) pane (dir2)
    send_keys $'\e[15~' # F5 key
    sleep 1 # Allow time for file I/O

    if [[ ! -f "$TEST_DIR/dir2/file1.txt" || ! -f "$TEST_DIR/dir2/file2.txt" ]]; then
        echo "  [FAIL] Copy failed. Files not found in destination."
        capture_screen
        exit 1
    fi
    echo "  [PASS] Copy successful."

    # --- Cleanup before Move ---
    rm "$TEST_DIR/dir2/file1.txt" "$TEST_DIR/dir2/file2.txt"

    # --- Test Move ---
    echo "  Testing Move (F6)..."
    # The panes were refreshed, so we need to mark the files again.
    send_keys $'\e[A'     # Up arrow (to '..')
    send_keys $'\e[B'     # Down arrow (to 'file1.txt')
    send_keys ' '        # Mark 'file1.txt' (cursor moves to 'file2.txt')
    send_keys ' '        # Mark 'file2.txt'
    send_keys $'\e[17~' # F6 key
    sleep 1

    # Capture screen and check if the inactive pane (dir2) shows the new files
    local screen_output
    screen_output=$(capture_screen)
    if ! echo "$screen_output" | grep -q "file1.txt" || ! echo "$screen_output" | grep -q "file2.txt"; then
        echo "  [FAIL] Pane refresh after move failed."
        exit 1
    fi
    echo "  [PASS] Pane refresh after move successful."


    # Verify files are moved from dir1 to dir2
    if [[ -f "$TEST_DIR/dir1/file1.txt" || -f "$TEST_DIR/dir1/file2.txt" ]]; then
        echo "  [FAIL] Move failed. Source files still exist."
        capture_screen
        exit 1
    fi
     if [[ ! -f "$TEST_DIR/dir2/file1.txt" || ! -f "$TEST_DIR/dir2/file2.txt" ]]; then
        echo "  [FAIL] Move failed. Files not found in destination."
        capture_screen
        exit 1
    fi
    echo "  [PASS] Move successful."

    # --- Test Delete ---
    echo "  Testing Delete (F7)..."
    # Switch to the right pane (dir2), which now contains the files
    send_keys $'\t'

    # Mark the files again for deletion
    send_keys $'\e[A'     # Up arrow (to '..')
    send_keys $'\e[B'     # Down arrow (to 'file1.txt')
    send_keys ' '        # Mark 'file1.txt' (cursor moves to 'file2.txt')
    send_keys ' '        # Mark 'file2.txt'

    # F7 to delete
    send_keys $'\e[18~' # F7 key
    sleep 1

    if [[ -f "$TEST_DIR/dir2/file1.txt" || -f "$TEST_DIR/dir2/file2.txt" ]]; then
        echo "  [FAIL] Delete failed. Files still exist."
        capture_screen
        exit 1
    fi
    echo "  [PASS] Delete successful."

    # --- Quit ---
    send_keys 'q'
}

# --- Main Execution ---
test_navigation() {
    echo "[TEST] miller_commander.sh navigation"

    # KNOWN ISSUE: This test is flaky. Extensive logging has confirmed that the
    # application state is updated correctly, but the screen capture often fails
    # to register the UI update in time, causing a false negative. This is likely
    # a race condition within the screen-based test harness.
    # Start the commander with dir1/subdir
    send_keys "$COMMANDER_SCRIPT $TEST_DIR/dir1/subdir"
    send_keys $'\n'
    sleep 1

    # Now navigate back up to dir1 using the left arrow key
    send_keys $'\e[D'
    sleep 1

    # Capture the screen and verify we see a file from the parent directory
    local screen_output
    screen_output=$(capture_screen)
    if ! echo "$screen_output" | grep -q "file1.txt"; then
        echo "  [FAIL] Back navigation failed. Did not find 'file1.txt' in the view."
        exit 1
    fi
    echo "  [PASS] Back navigation successful."

    # Quit the application
    send_keys 'q'
}

main() {
    setup
    test_file_operations

    # Restart screen for the next test to ensure a clean state
    screen -S "$SESSION_NAME" -X quit || true
    sleep 1
    screen -S "$SESSION_NAME" -d -m bash
    sleep 1

    test_navigation
    echo "--- All tests passed ---"
}

main
