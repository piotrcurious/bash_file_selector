#!/usr/bin/env bash

file_selector.sh: Interactive file selector for current directory

Features:

- Handles large directories by indexing files in a temp file under /tmp

- Interactive navigation with arrow keys and page up/down

- Wraps long filenames with indentation

- Press Enter to select a file; selection saved to a temp file in cwd

- Function keys (F1-F4) call auxiliary scripts defined by environment variables FS_F1..FS_F4

--- Configuration and setup ---

Maximum lines per page (terminal height - header/footer)

TERM_LINES=$(tput lines) PAGE_SIZE=$((TERM_LINES - 4)) TERM_COLS=$(tput cols)

Temporary index file for listing all filenames

Unique per working directory using hash of cwd path

CWD_HASH=$(pwd | md5sum | cut -d' ' -f1) INDEX_FILE="/tmp/file_selector_${CWD_HASH}.idx"

File to store selected filename

SELECTED_FILE="$(pwd)/.file_selection.tmp"

Cleanup old index file if directory content changed (optional)

You may implement logic to refresh if mtime differs. For simplicity, always recreate.

rm -f "$INDEX_FILE"

Create index: filenames only (no directories), sorted

Adjust find options if you want other file types

find . -maxdepth 1 -type f -printf '%P\n' | sort > "$INDEX_FILE" TOTAL=$(wc -l < "$INDEX_FILE")

Variables for interactive navigation

offset=0          # current page start (0-based) selected=0        # current selected index (0-based)

enable_wrap() { local text="$1" width=$((TERM_COLS - 4)) if [ ${#text} -le "$width" ]; then printf "%s\n" "  $text" else # wrap by words echo "$text" | awk -v w=$width '{for(i=1;i<=NF;){line=$i;i++; while(i<=NF && length(line)+length($i)+1<=w){line=line" "$i;i++} print "  "line; line=""}}' fi }

draw_page() { clear echo "Files in $(pwd) (total: $TOTAL)" echo "Use Arrow keys to navigate, Enter to select, F1-F4 to trigger auxiliary scripts" echo "────────────────────────────────────────────────────────────" local end=$((offset + PAGE_SIZE - 1)) [ $end -ge $((TOTAL - 1)) ] && end=$((TOTAL - 1)) for ((i=offset; i<=end; i++)); do line=$(sed -n "$((i+1))p" "$INDEX_FILE") if [ $i -eq $selected ]; then # highlight selected printf "> "; enable_wrap "$line" else printf "  "; enable_wrap "$line" fi done }

Function to handle selection and exit

finish() { local sel_line=$(sed -n "$((selected+1))p" "$INDEX_FILE") echo "$sel_line" > "$SELECTED_FILE" cleanup exit }

Cleanup temp files

cleanup() { rm -f "$INDEX_FILE" }

Trap signals to cleanup

trap cleanup EXIT

Main loop

while true; do draw_page n  # read key (up to 3 chars) IFS= read -rsn3 key case "$key" in $'\e[A') # Up arrow ((selected>0)) && selected-- ((selected<offset)) && offset=$selected ;; $'\e[B') # Down arrow ((selected<TOTAL-1)) && selected++ ((selected>offset+PAGE_SIZE-1)) && offset=$((selected-PAGE_SIZE+1)) ;; $'\e[5~') # Page Up ((offset-PAGE_SIZE>=0)) && offset=$((offset-PAGE_SIZE)) || offset=0 selected=$offset ;; $'\e[6~') # Page Down ((offset+PAGE_SIZE<TOTAL)) && offset=$((offset+PAGE_SIZE)) || offset=$((TOTAL-PAGE_SIZE>0?TOTAL-PAGE_SIZE:0)) selected=$offset ;; "") # Enter finish ;; $'\e[11~') # F1 [ -n "$FS_F1" ] && eval "$FS_F1 "$(sed -n "$((selected+1))p" "$INDEX_FILE")"" ;; $'\e[12~') # F2 [ -n "$FS_F2" ] && eval "$FS_F2 "$(sed -n "$((selected+1))p" "$INDEX_FILE")"" ;; $'\e[13~') # F3 [ -n "$FS_F3" ] && eval "$FS_F3 "$(sed -n "$((selected+1))p" "$INDEX_FILE")"" ;; $'\e[14~') # F4 [ -n "$FS_F4" ] && eval "$FS_F4 "$(sed -n "$((selected+1))p" "$INDEX_FILE")"" ;; esac done

