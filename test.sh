#!/usr/bin/env bash
set -euo pipefail

# Start Miller Commander in a detached screen session
screen -d -m -S mc_test ./improved/miller_commander.sh

# Wait for the application to start
sleep 1

# Send a "down arrow" key press to navigate
screen -S mc_test -X stuff $'\e[B'

# Wait for the UI to update
sleep 1

# Capture the screen content
screen -S mc_test -X hardcopy -h hardcopy.txt

# Kill the screen session
screen -S mc_test -X quit

# Verify the output
if grep -q "miller_commander" hardcopy.txt; then
    echo "Test passed: Found 'miller_commander' in the output."
    exit 0
else
    echo "Test failed: Did not find 'miller_commander' in the output."
    exit 1
fi
