#!/usr/bin/env bash
set -euo pipefail

# --- Test Setup ---
TEST_DIR=$(mktemp -d)
trap 'cleanup' EXIT
cleanup() {
    screen -S mc_test -X quit || true
    rm -rf "$TEST_DIR"
}

# Create test files and directories
mkdir -p "$TEST_DIR/dir1/sdir1"
mkdir -p "$TEST_DIR/dir2"
touch "$TEST_DIR/dir1/file1.txt"
touch "$TEST_DIR/dir1/file2.txt"
touch "$TEST_DIR/file3.log"

# --- Test Harness ---
APP_PATH="$(pwd)/miller_commander2/miller_commander.sh"
SESSION_NAME="mc_test"

# Start the app in a detached screen session
screen -dmS "$SESSION_NAME" "$APP_PATH" "$TEST_DIR" "$TEST_DIR/dir1"

# Give the app a moment to start
sleep 1

send_keys() {
    local keys_to_send="$1"
    sleep 0.2
    screen -S "$SESSION_NAME" -p 0 -X stuff "$keys_to_send"
    sleep 0.2
}

capture_screen() {
    screen -S "$SESSION_NAME" -p 0 -X hardcopy -h "screen_capture.txt"
    # The hardcopy can have trailing whitespace, so we normalize it
    sed -e 's/[[:space:]]*$//' screen_capture.txt
}

# --- Test Cases ---
echo "--- Running Miller Commander 2 Tests ---"

# Test 1: Initial screen
echo -n "Test 1: Initial screen renders correctly... "
sleep 1 # Wait for initial render
DUMP_1=$(capture_screen)
if echo "$DUMP_1" | grep -q "dir1/"; then
    echo "PASS"
else
    echo "FAIL"
    echo "--- Captured Screen ---"
    echo "$DUMP_1"
    echo "-----------------------"
    exit 1
fi

# Test 2: Navigate down (partial update)
echo -n "Test 2: Navigate down triggers partial update... "
send_keys $'\e[B' # Down arrow
sleep 1
DUMP_2=$(capture_screen)
if echo "$DUMP_2" | grep -q "file3.log"; then
    echo "PASS"
else
    echo "FAIL"
    echo "--- Captured Screen ---"
    echo "$DUMP_2"
    echo "-----------------------"
    exit 1
fi

# Test 3: Select item (partial update)
echo -n "Test 3: Select item triggers partial update... "
send_keys " " # Spacebar
sleep 1
DUMP_3=$(capture_screen)
if echo "$DUMP_3" | grep -q "*   file3.log"; then
    echo "PASS"
else
    echo "FAIL"
    echo "--- Captured Screen ---"
    echo "$DUMP_3"
    echo "-----------------------"
    exit 1
fi


# Test 4: Enter directory (full update)
echo -n "Test 4: Entering a directory triggers full update... "
send_keys "" # Enter key
sleep 1
DUMP_4=$(capture_screen)
if echo "$DUMP_4" | grep -q "sdir1/"; then
    echo "PASS"
else
    echo "FAIL"
    echo "--- Captured Screen ---"
    echo "$DUMP_4"
    echo "-----------------------"
    exit 1
fi

# Test 5: Tab navigation
echo -n "Test 5: Tab navigation switches panes... "
send_keys $'\t'
sleep 1
DUMP_5=$(capture_screen)
if echo "$DUMP_5" | grep -q "sdir1/"; then
    echo "PASS"
else
    echo "FAIL"
    echo "--- Captured Screen ---"
    echo "$DUMP_5"
    echo "-----------------------"
    exit 1
fi

# Test 6: Quit
echo -n "Test 6: 'q' quits the application... "
send_keys "q"
sleep 1
if ! screen -list | grep -q "$SESSION_NAME"; then
    echo "PASS"
else
    echo "FAIL: Screen session still running."
    exit 1
fi

echo "--- All tests passed! ---"
