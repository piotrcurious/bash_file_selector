#!/usr/bin/env bash
set -euo pipefail

# Cleanup previous runs
rm -rf test_dir

# --- Setup ---
mkdir -p test_dir/source/sub_dir test_dir/dest
touch test_dir/source/file.txt

# Start Miller Commander in a detached screen session
# Pane 0: source | Pane 1: dest
screen -d -m -S mc_test ./improved/miller_commander.sh test_dir/source test_dir/dest

# Give the app a moment to initialize
sleep 1

# --- Test 1: Enter Directory ---
# In pane 0 (source), navigate to sub_dir
screen -S mc_test -X stuff $'\e[B'
sleep 0.5
screen -S mc_test -X stuff $'\e[B'
sleep 0.5
# Press Enter to enter the directory
screen -S mc_test -X stuff $'\x0a'
sleep 1

# Capture the screen content
screen -S mc_test -X hardcopy -h hardcopy.txt

# --- Cleanup and Verification ---
# Kill the screen session
screen -S mc_test -X quit

test_passed=true

# Verification 1: Check that the directory was entered
if ! grep -q "sub_dir" hardcopy.txt; then
    echo "FAIL: Did not enter the sub_dir directory."
    test_passed=false
fi

# Final Cleanup
rm -rf test_dir

if [ "$test_passed" = true ]; then
    echo "Directory entry test passed!"
    exit 0
else
    echo "Directory entry test failed."
    exit 1
fi
