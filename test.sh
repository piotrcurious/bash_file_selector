#!/usr/bin/env bash
set -euo pipefail

# Cleanup previous runs
rm -rf test_dir

# --- Setup ---
mkdir -p test_dir/source test_dir/dest
echo "source" > test_dir/source/file_to_move.txt
echo "dest" > test_dir/dest/file_to_move.txt
touch test_dir/source/file_to_delete.txt

# Start Miller Commander in a detached screen session
# Pane 0: source | Pane 1: dest
screen -d -m -S mc_test ./improved/miller_commander.sh test_dir/source test_dir/dest

# Give the app a moment to initialize
sleep 1

# --- Test 1: Delete Confirmation (Cancel) ---
# In pane 0 (source), the file list is [.., file_to_delete.txt, file_to_move.txt]
# Navigate to file_to_delete.txt (1 down from ..)
screen -S mc_test -X stuff $'\e[B'
sleep 0.5

# Press F8 to delete
screen -S mc_test -X stuff $'\e[19~'
sleep 0.5

# Send "n" to the confirmation prompt and press Enter
screen -S mc_test -X stuff "n"
screen -S mc_test -X stuff $'\x0a'
sleep 0.5

# --- Test 2: MkDir (F7) ---
# Press F7 to create a directory
screen -S mc_test -X stuff $'\e[18~'
sleep 0.5
# Type the directory name and press Enter
screen -S mc_test -X stuff "new_dir"
screen -S mc_test -X stuff $'\x0a'
sleep 1

# --- Test 3: Overwrite Confirmation (Confirm) ---
# Navigate to file_to_move.txt (1 more down)
screen -S mc_test -X stuff $'\e[B'
sleep 0.5

# Mark the file for moving
screen -S mc_test -X stuff " "
sleep 0.5

# Switch to pane 1 (dest)
screen -S mc_test -X stuff $'\t'
sleep 0.5

# Press F6 to move (this should trigger the overwrite prompt)
screen -S mc_test -X stuff $'\e[17~'
sleep 0.5

# Send "y" to the confirmation prompt and press Enter
screen -S mc_test -X stuff "y"
screen -S mc_test -X stuff $'\x0a'
sleep 1 # Allow time for file operation

# --- Cleanup and Verification ---
# Kill the screen session
screen -S mc_test -X quit

test_passed=true

# Verification 1: Check that the file was NOT deleted
if [ ! -f "test_dir/source/file_to_delete.txt" ]; then
    echo "FAIL: file_to_delete.txt was deleted when it should not have been."
    test_passed=false
fi

# Verification 2: Check that the new directory was created
if [ ! -d "test_dir/source/new_dir" ]; then
    echo "FAIL: new_dir was not created."
    test_passed=false
fi

# Verification 3: Check that the file was moved (no longer in source)
if [ -f "test_dir/source/file_to_move.txt" ]; then
    echo "FAIL: file_to_move.txt was not moved from the source directory."
    test_passed=false
fi

# Verification 4: Check that the destination file WAS overwritten
if ! grep -q "source" test_dir/dest/file_to_move.txt; then
    echo "FAIL: dest/file_to_move.txt was not overwritten."
    test_passed=false
fi

# Final Cleanup
rm -rf test_dir

if [ "$test_passed" = true ]; then
    echo "All confirmation and remapping tests passed!"
    exit 0
else
    echo "One or more tests failed."
    exit 1
fi
