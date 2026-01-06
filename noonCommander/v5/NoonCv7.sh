#!/usr/bin/env bash

BASH Commander - Enhanced File Manager

Version: 2.3 (preserve structure + destination browser & favorites)

set -euo pipefail

------- Configuration -------

FILES_PER_PAGE=20 INDENT="    " SELECTION_FILE="$(mktemp --tmpdir commander_selection.XXXXXX)" CLIPBOARD_FILE="$(mktemp --tmpdir commander_clipboard.XXXXXX)" TMP_INDEX_FILE="$(mktemp --tmpdir commander_index.XXXXXX)" MARKS_FILE="$(mktemp --tmpdir commander_marks.XXXXXX)" DEST_FAV_FILE="${HOME}/.commander_dest_favs"

state

CURRENT_DIR="$(pwd)" CURSOR_POS=0 CURRENT_PAGE=0 CLIPBOARD_MODE=""  # 'copy' or 'cut' WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)" TOTAL_FILES=0 TOTAL_PAGES=1 FILES=()   # bash array of indexed files

Ensure favorites file exists

mkdir -p "${HOME}" touch "$DEST_FAV_FILE"

Terminal setup / cleanup

cleanup_exit() { stty sane || true tput cnorm || true rm -f -- "$SELECTION_FILE" "$CLIPBOARD_FILE" "$TMP_INDEX_FILE" "$MARKS_FILE" >/dev/null 2>&1 || true clear exit } trap cleanup_exit INT TERM EXIT

put terminal into raw-ish mode for single-key input (and restore on exit)

enable_input_mode() { stty -echo -icanon time 0 min 0 tput civis } disable_input_mode() { stty sane tput cnorm } enable_input_mode

Update wrap width on resize

on_resize() { WRAP_WIDTH="$(tput cols 2>/dev/null || echo 80)" } trap 'on_resize' WINCH

------- Utilities -------

format_size() { local size=$1 if (( size < 1024 )); then echo "${size}B" elif (( size < 1048576 )); then awk -v s="$size" 'BEGIN{printf "%.1fK", s/1024}' elif (( size < 1073741824 )); then awk -v s="$size" 'BEGIN{printf "%.1fM", s/1048576}' else awk -v s="$size" 'BEGIN{printf "%.1fG", s/1073741824}' fi }

Index directory safely (handles spaces/newlines)

index_dir() { local dir="$1" : > "$TMP_INDEX_FILE"

# Use find -mindepth 1 -maxdepth 1 -print0, collect, sort
mapfile -t -d '' FILES < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z) || true

# fallback when above yields nothing (older sort implementations)
if [[ "${#FILES[@]}" -eq 0 ]]; then
    IFS=$'

' read -r -d '' -a FILES < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -n1 printf '%s ' | sort -f | sed -z 's/ $//' && printf '�') || true fi

: > "$TMP_INDEX_FILE"
for f in "${FILES[@]}"; do
    printf '%s�' "$f" >> "$TMP_INDEX_FILE"
done

TOTAL_FILES=0
if [[ -s "$TMP_INDEX_FILE" ]]; then
    TOTAL_FILES=$(tr -cd '�' < "$TMP_INDEX_FILE" | wc -c)
else
    TOTAL_FILES=0
fi

if (( TOTAL_FILES == 0 )); then
    TOTAL_PAGES=1
else
    TOTAL_PAGES=$(( (TOTAL_FILES + FILES_PER_PAGE - 1) / FILES_PER_PAGE ))
fi

# ensure cursor/page in valid range
if (( CURRENT_PAGE >= TOTAL_PAGES )); then CURRENT_PAGE=$((TOTAL_PAGES - 1)); fi
if (( CURRENT_PAGE < 0 )); then CURRENT_PAGE=0; fi
if (( CURSOR_POS >= FILES_PER_PAGE )); then CURSOR_POS=$((FILES_PER_PAGE - 1)); fi

}

read_index_entry() { local idx="$1" awk -v n="$idx" 'BEGIN{RS="�"; ORS=""} NR==n+1{print $0}' "$TMP_INDEX_FILE" || true }

Marks utilities

is_marked() { local path="$1" [[ -s "$MARKS_FILE" ]] || return 1 grep -Fxq -- "$path" "$MARKS_FILE" 2>/dev/null }

toggle_mark() { local path="$1" if is_marked "$path"; then grep -Fxv -- "$path" "$MARKS_FILE" 2>/dev/null > "${MARKS_FILE}.tmp" || true mv -f "${MARKS_FILE}.tmp" "$MARKS_FILE" else printf '%s ' "$path" >> "$MARKS_FILE" fi }

get_marked_array() { local -n out_arr=$1 out_arr=() if [[ -s "$MARKS_FILE" ]]; then mapfile -t out_arr < "$MARKS_FILE" fi }

clear_marks() { : > "$MARKS_FILE" }

messages (temporarily leave raw mode)

show_message() { local msg="$1" local duration="${2:-1.5}" disable_input_mode echo -e " [1;32m${msg}[0m" sleep "$duration" enable_input_mode } show_error() { local msg="$1" local duration="${2:-1.5}" disable_input_mode echo -e " [1;31m${msg}[0m" >&2 sleep "$duration" enable_input_mode }

------- Destination chooser (browser + favorites) -------

choose_destination() { # returns chosen path or empty string on cancel disable_input_mode while true; do clear echo -e "[1mChoose destination directory[0m" echo echo "Favorites:" local i=1 mapfile -t favs < <(grep -v '^#' "$DEST_FAV_FILE" 2>/dev/null || true) if (( ${#favs[@]} == 0 )); then echo "  (no favorites yet)" else for f in "${favs[@]}"; do echo "  [$i] $f" ((i++)) done fi echo echo "Options:" echo "  [number] - choose favorite" echo "  b - browse filesystem" echo "  a - add current directory to favorites" echo "  q - cancel" echo read -rp $'Select: ' choice case "$choice" in q) enable_input_mode; printf ''; return ;; b) browse_dir="$CURRENT_DIR" while true; do clear echo -e "Browse: [32m$browse_dir[0m" echo # list only directories mapfile -t dirs < <(find "$browse_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort) echo "0) Select this directory" echo "u) Up" local idx=1 for d in "${dirs[@]}"; do echo "${idx}) $(basename "$d")" ((idx++)) done echo "n) New directory" echo "a) Add to favorites" echo "c) Cancel browse" read -rp $'Choose: ' bch case "$bch" in 0) enable_input_mode printf '%s' "$browse_dir" return ;; u) browse_dir="$(dirname "$browse_dir")" ;; n) read -rp $'New dir name: ' nd [[ -n "$nd" ]] && mkdir -p -- "$browse_dir/$nd" && show_message "Created $nd" 0.6 ;; a) # add to favorites file if ! grep -Fxq -- "$browse_dir" "$DEST_FAV_FILE" 2>/dev/null; then printf '%s ' "$browse_dir" >> "$DEST_FAV_FILE" show_message "Added to favorites." 0.7 else show_message "Already in favorites." 0.7 fi ;; c) break ;; '') ;; *) if [[ "$bch" =~ ^[0-9]+$ ]]; then sel=$((bch)) if (( sel >=1 && sel <= ${#dirs[@]} )); then browse_dir="${dirs[$((sel-1))]}" fi fi ;; esac done ;; a) # add CURRENT_DIR to favorites if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then printf '%s ' "$CURRENT_DIR" >> "$DEST_FAV_FILE" show_message "Added current dir to favorites." 0.7 else show_message "Already a favorite." 0.7 fi ;; '') ;; # ignore *) if [[ "$choice" =~ ^[0-9]+$ ]]; then num=$((choice)) if (( num >= 1 && num <= ${#favs[@]} )); then enable_input_mode printf '%s' "${favs[$((num-1))]}" return fi fi ;; esac done }

------- UI / drawing -------

draw_page() { clear on_resize

echo -e "[1m[36m📁 BASH COMMANDER[0m - [32m$CURRENT_DIR[0m"
echo -e "[2mFiles: $TOTAL_FILES | Page: $((CURRENT_PAGE + 1))/$TOTAL_PAGES[0m"

echo -e "[33m↑↓[0m:Move  [33mEnter[0m:Open  [33m←[0m:Up  [33m(space)[0m:Mark  [33m[p][0m:Preview  [33m[e][0m:Edit  [33m[c][0m:Copy  [33m[x][0m:Cut  [33m[v][0m:Paste"
echo -e "[33m[m][0m:Move  [33m[d][0m:Delete  [33m[r][0m:Rename  [33m[n][0m:New  [33m[s][0m:Search  [33m[i][0m:Info  [33m[q][0m:Quit"
echo -e "[33m[C][0m:Copy marked  [33m[M][0m:Move marked  [33m[D][0m:Delete marked  [33m[u][0m:Unmark all  [33m[F][0m:Add current dir to favorites  [33m[h][0m:Help"
echo

if [[ -s "$CLIPBOARD_FILE" ]]; then
    local clip_item
    clip_item=$(<"$CLIPBOARD_FILE")
    echo -e "[34m📋 Clipboard [$CLIPBOARD_MODE]: $(basename "$clip_item")[0m"
    echo
fi

local start=$(( CURRENT_PAGE * FILES_PER_PAGE ))
local end=$(( start + FILES_PER_PAGE - 1 ))
if (( end >= TOTAL_FILES )); then end=$((TOTAL_FILES - 1)); fi

if (( TOTAL_FILES == 0 )); then
    echo -e "  [2m(Empty directory)[0m"
    return
fi

local i=0
local idx=0
while IFS= read -r -d '' entry; do
    if (( idx < start )); then ((idx++)); continue; fi
    if (( idx > end )); then break; fi

    local rel="${entry#$CURRENT_DIR/}"
    local display="$rel"
    if [[ -d "$entry" ]]; then display="$display/"; fi

    if (( idx == start + CURSOR_POS )); then
        printf '%s' "[1m[36m> "
    else
        printf '  '
    fi

    if is_marked "$entry"; then
        printf '[*] '
    else
        printf '    '
    fi

    local maxw=$(( WRAP_WIDTH - 10 ))
    if (( maxw < 20 )); then maxw=20; fi

    printf '%s' "$(echo "$display" | fold -s -w "$maxw" | sed -n '1p')"
    printf '

' local rest rest=$(echo "$display" | fold -s -w "$maxw" | sed -n '2,$p' || true) if [[ -n "$rest" ]]; then while IFS= read -r line; do printf '      %s ' "$line" done <<<"$rest" fi

printf '[0m'
    ((idx++))
    ((i++))
done <"$TMP_INDEX_FILE"

}

------- Actions -------

get_selected_path() { if (( TOTAL_FILES == 0 )); then printf '' return fi local global_index=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS )) if (( global_index < 0 || global_index >= TOTAL_FILES )); then printf '' return fi read_index_entry "$global_index" }

preview_file() { local file file="$(get_selected_path)" [[ -z "$file" ]] && { show_message "No file selected."; return; } if [[ -d "$file" ]]; then show_error "'$file' is a directory."; return; fi

disable_input_mode
clear
echo -e "[36m[1mPreviewing:[0m $file"
echo "-----------------------------------"
local mime
mime=$(file --mime-type -b "$file" 2>/dev/null || echo "")
case "$mime" in
    text/*)
        if command -v bat &>/dev/null; then
            bat --style=plain --paging=always "$file"
        else
            less "$file"
        fi
        ;;
    image/*)
        if command -v identify &>/dev/null; then
            identify "$file" 2>/dev/null | sed -n '1,200p'
        else
            file "$file"
        fi
        echo
        read -rp "Press Enter to continue..."
        ;;
    application/pdf)
        if command -v pdftotext &>/dev/null; then
            pdftotext "$file" - | less
        else
            echo "Install pdftotext (poppler-utils) for PDF previews."
            read -rp "Press Enter to continue..."
        fi
        ;;
    audio/*|video/*)
        if command -v ffprobe &>/dev/null; then
            ffprobe -v error -show_format -show_streams "$file" 2>&1 | less
        elif command -v mediainfo &>/dev/null; then
            mediainfo "$file" | less
        else
            file "$file"
            read -rp "Press Enter to continue..."
        fi
        ;;
    application/zip|application/x-tar|application/gzip)
        if command -v unzip &>/dev/null && [[ "$mime" == "application/zip" ]]; then
            unzip -l "$file" | less
        elif command -v tar &>/dev/null; then
            tar -tf "$file" 2>/dev/null | less
        else
            file "$file"
            read -rp "Press Enter to continue..."
        fi
        ;;
    *)
        echo "Binary or unknown filetype. Hex preview (first 100 lines):"
        if command -v xxd &>/dev/null; then
            xxd "$file" | head -n 100 | less
        else
            hexdump -C "$file" | head -n 100 | less
        fi
        ;;
esac
enable_input_mode
index_dir "$CURRENT_DIR"

}

edit_file() { local file file="$(get_selected_path)" [[ -z "$file" ]] && { show_message "No file selected."; return; } if [[ -d "$file" ]]; then show_error "'$file' is a directory."; return; fi

disable_input_mode
local editor="${EDITOR:-nano}"
local mime
mime=$(file --mime-type -b "$file" 2>/dev/null || echo "")
if [[ "$mime" == text/* ]]; then
    "$editor" "$file"
else
    echo "Binary file detected."
    read -rp "Edit with hex editor? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        if command -v hexedit &>/dev/null; then
            hexedit "$file"
        elif command -v xxd &>/dev/null; then
            tmphex="$(mktemp --tmpdir commander_hex.XXXXXX)"
            xxd "$file" > "$tmphex"
            "$editor" "$tmphex"
            read -rp "Save changes? [y/N]: " save
            if [[ "$save" =~ ^[Yy]$ ]]; then
                xxd -r "$tmphex" > "$file"
            fi
            rm -f "$tmphex"
        else
            echo "No hex editor available."
            read -rp "Press Enter to continue..."
        fi
    fi
fi
enable_input_mode
index_dir "$CURRENT_DIR"

}

rename_file() { local src src="$(get_selected_path)" [[ -z "$src" ]] && { show_message "No file selected."; return; } disable_input_mode read -rp $' [33mRename '"$(basename "$src")"': [0m' newname if [[ -z "$newname" ]]; then show_message "Rename cancelled." enable_input_mode return fi local dest dest="$(dirname "$src")/$newname" if [[ -e "$dest" ]]; then show_error "Destination exists!" elif mv -- "$src" "$dest"; then show_message "Renamed." else show_error "Rename failed!" fi enable_input_mode index_dir "$CURRENT_DIR" }

delete_file() { local path path="$(get_selected_path)" [[ -z "$path" ]] && { show_message "No file selected."; return; } disable_input_mode read -rp $' [31mDelete '"$(basename "$path")"'? [y/N]: [0m' ans if [[ "$ans" =~ ^[Yy]$ ]]; then if rm -rf -- "$path"; then show_message "Deleted." else show_error "Delete failed!" fi else show_message "Delete cancelled." fi enable_input_mode index_dir "$CURRENT_DIR" }

---- Multi-file operations (preserve structure) ----

copy_marked() { local marked get_marked_array marked if (( ${#marked[@]} == 0 )); then show_message "No marked items to copy." 1 return fi

# choose destination interactively
dest="$(choose_destination)"
if [[ -z "$dest" ]]; then show_message "Copy cancelled."; return; fi

# preserve structure relative to CURRENT_DIR when possible
local base="$CURRENT_DIR"
local ok=0 fail=0
for src in "${marked[@]}"; do
    if [[ "$src" == "$base"* ]]; then
        rel="${src#$base/}"
    else
        rel="$(basename "$src")"
    fi
    dest_full="$dest/$rel"
    mkdir -p -- "$(dirname "$dest_full")"
    if cp -a -- "$src" "$dest_full" 2>/dev/null; then
        ((ok++))
    else
        ((fail++))
    fi
done
show_message "Copy complete: $ok succeeded, $fail failed." 1.5

}

move_marked() { local marked get_marked_array marked if (( ${#marked[@]} == 0 )); then show_message "No marked items to move." 1 return fi

dest="$(choose_destination)"
if [[ -z "$dest" ]]; then show_message "Move cancelled."; return; fi

local base="$CURRENT_DIR"
local ok=0 fail=0
for src in "${marked[@]}"; do
    if [[ "$src" == "$base"* ]]; then
        rel="${src#$base/}"
    else
        rel="$(basename "$src")"
    fi
    dest_full="$dest/$rel"
    mkdir -p -- "$(dirname "$dest_full")"
    if mv -- "$src" "$dest_full" 2>/dev/null; then
        ((ok++))
    else
        ((fail++))
    fi
done

# clear marks for moved items
: > "$MARKS_FILE"
index_dir "$CURRENT_DIR"
show_message "Move complete: $ok succeeded, $fail failed." 1.5

}

delete_marked() { local marked get_marked_array marked if (( ${#marked[@]} == 0 )); then show_message "No marked items to delete." 1 return fi disable_input_mode read -rp $' [31mDelete '"${#marked[@]}"' marked items? [y/N]: [0m' ans if [[ ! "$ans" =~ ^[Yy]$ ]]; then show_message "Delete cancelled."; enable_input_mode; return fi local ok=0 fail=0 for src in "${marked[@]}"; do if rm -rf -- "$src" 2>/dev/null; then ((ok++)); else ((fail++)); fi done : > "$MARKS_FILE" enable_input_mode index_dir "$CURRENT_DIR" show_message "Delete complete: $ok succeeded, $fail failed." 1.5 }

unmark_all() { : > "$MARKS_FILE" show_message "All marks cleared." 0.7 }

------- Remaining single-item actions (unchanged) -------

copy_file() { local src src="$(get_selected_path)" [[ -z "$src" ]] && { show_message "No file selected."; return; } disable_input_mode read -rp $' [33mCopy to (path): [0m' dest if [[ -z "$dest" ]]; then show_message "Copy cancelled."; enable_input_mode; return; fi if cp -r -- "$src" "$dest"; then show_message "Copied." else show_error "Copy failed!" fi enable_input_mode index_dir "$CURRENT_DIR" }

move_file() { local src src="$(get_selected_path)" [[ -z "$src" ]] && { show_message "No file selected."; return; } disable_input_mode read -rp $' [33mMove to (path): [0m' dest if [[ -z "$dest" ]]; then show_message "Move cancelled."; enable_input_mode; return; fi if mv -- "$src" "$dest"; then show_message "Moved." else show_error "Move failed!" fi enable_input_mode index_dir "$CURRENT_DIR" }

clipboard_copy() { local src src="$(get_selected_path)" [[ -z "$src" ]] && { show_message "No file selected."; return; } printf '%s' "$src" > "$CLIPBOARD_FILE" CLIPBOARD_MODE="copy" show_message "Copied to clipboard: $(basename "$src")" 1 }

clipboard_cut() { local src src="$(get_selected_path)" [[ -z "$src" ]] && { show_message "No file selected."; return; } printf '%s' "$src" > "$CLIPBOARD_FILE" CLIPBOARD_MODE="cut" show_message "Cut to clipboard: $(basename "$src")" 1 }

clipboard_paste() { if [[ ! -s "$CLIPBOARD_FILE" ]]; then show_error "Clipboard is empty!"; return; fi local src dest src=$(<"$CLIPBOARD_FILE") dest="$CURRENT_DIR/$(basename "$src")" if [[ ! -e "$src" ]]; then show_error "Source no longer exists!" : > "$CLIPBOARD_FILE" CLIPBOARD_MODE="" return fi if [[ "$CLIPBOARD_MODE" == "copy" ]]; then if cp -r -- "$src" "$dest" 2>/dev/null; then show_message "Pasted (copy)." index_dir "$CURRENT_DIR" else show_error "Paste failed!" fi elif [[ "$CLIPBOARD_MODE" == "cut" ]]; then if mv -- "$src" "$dest" 2>/dev/null; then show_message "Pasted (move)." : > "$CLIPBOARD_FILE" CLIPBOARD_MODE="" index_dir "$CURRENT_DIR" else show_error "Paste failed!" fi fi }

create_new() { disable_input_mode read -rp $' Create: [f]ile or [d]irectory? ' choice case "$choice" in f) read -rp $' [33mNew file name: [0m' fname [[ -z "$fname" ]] && { show_message "Cancelled."; enable_input_mode; return; } if touch "$CURRENT_DIR/$fname"; then show_message "File created: $fname" index_dir "$CURRENT_DIR" else show_error "Failed to create file!" fi ;; d) read -rp $' [33mNew directory name: [0m' dname [[ -z "$dname" ]] && { show_message "Cancelled."; enable_input_mode; return; } if mkdir -p "$CURRENT_DIR/$dname"; then show_message "Directory: $dname created." index_dir "$CURRENT_DIR" else show_error "Failed to create directory!" fi ;; *) show_message "Cancelled." ;; esac enable_input_mode }

search_files() { disable_input_mode read -rp $' [33mSearch for: [0m' query if [[ -z "$query" ]]; then show_message "Search cancelled."; enable_input_mode; return; fi clear echo -e "[36mSearch results for: '$query'[0m" echo "-----------------------------------" find "$CURRENT_DIR" -iname "$query" 2>/dev/null | less enable_input_mode }

show_info() { local path path="$(get_selected_path)" [[ -z "$path" ]] && { show_message "No file selected."; return; } disable_input_mode clear echo -e "[36m[1mFile Information[0m" echo "-----------------------------------" echo -e "[33mPath:[0m $path" if [[ -d "$path" ]]; then local count count=$(find "$path" -mindepth 1 2>/dev/null | wc -l) echo -e "[33mType:[0m Directory" echo -e "[33mItems:[0m $count" else local size mime size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo 0) mime=$(file --mime-type -b "$path" 2>/dev/null || echo "") echo -e "[33mType:[0m File" echo -e "[33mSize:[0m $(format_size "$size") ($size bytes)" echo -e "[33mMIME:[0m $mime" fi echo ls -lh -- "$path" 2>/dev/null || true echo read -rp "Press Enter to continue..." enable_input_mode }

enter_item() { local path path="$(get_selected_path)" [[ -z "$path" ]] && { show_message "No file selected."; return; } if [[ -d "$path" ]]; then CURRENT_DIR="$path" CURRENT_PAGE=0 CURSOR_POS=0 index_dir "$CURRENT_DIR" else printf '%s ' "$path" >> "$SELECTION_FILE" if command -v xdg-open &>/dev/null; then xdg-open "$path" &>/dev/null & elif command -v open &>/dev/null; then open "$path" &>/dev/null & else show_message "No GUI opener found; file recorded in selection file." fi fi }

go_up() { local parent parent="$(dirname "$CURRENT_DIR")" if [[ "$parent" != "$CURRENT_DIR" ]]; then CURRENT_DIR="$parent" CURRENT_PAGE=0 CURSOR_POS=0 index_dir "$CURRENT_DIR" fi }

goto_top() { CURRENT_PAGE=0 CURSOR_POS=0 }

goto_bottom() { CURRENT_PAGE=$((TOTAL_PAGES - 1)) CURSOR_POS=$(( (TOTAL_FILES - 1 - CURRENT_PAGE * FILES_PER_PAGE) )) if (( CURSOR_POS < 0 )); then CURSOR_POS=0; fi }

refresh_index() { index_dir "$CURRENT_DIR" show_message "Refreshed index." 0.5 }

show_help() { disable_input_mode clear cat <<'EOF' BASH COMMANDER - Help

Navigation: Up/Down arrows - move selection Enter           - open file / enter directory ← or Backspace  - go to parent directory g               - go to top G               - go to bottom R               - refresh listing Space           - toggle mark (selection) p               - preview file e               - edit file c               - copy (ask destination) x               - cut (ask destination on paste) v               - paste clipboard into current dir m               - move file (ask destination) d               - delete r               - rename n               - new file/dir s               - search i               - info h               - show this help q               - quit

Multi-file (marked) operations: C - Copy marked items to destination directory (preserves directory structure relative to the current listing root) M - Move marked items to destination directory (preserves structure) D - Delete all marked items (with confirmation) u - Unmark all F - Add current directory to favorites

Destination browser/favorites: When invoking multi-file operations you'll be asked to choose a destination. You can pick from favorites, browse the filesystem, create new dirs, and add favorites for persistence.

Marked items are saved to a temporary marks file (deleted on exit).

EOF read -rp "Press Enter to return..." enable_input_mode }

Movement helpers

move_cursor_up() { if (( CURSOR_POS > 0 )); then ((CURSOR_POS--)) elif (( CURRENT_PAGE > 0 )); then ((CURRENT_PAGE--)) CURSOR_POS=$(( FILES_PER_PAGE - 1 )) fi } move_cursor_down() { local last_on_page=$(( (CURRENT_PAGE + 1) * FILES_PER_PAGE - 1 )) if (( last_on_page >= TOTAL_FILES )); then last_on_page=$(( TOTAL_FILES - 1 )); fi local pos_global=$(( CURRENT_PAGE * FILES_PER_PAGE + CURSOR_POS )) if (( pos_global < last_on_page )); then ((CURSOR_POS++)) elif (( CURRENT_PAGE < TOTAL_PAGES - 1 )); then ((CURRENT_PAGE++)) CURSOR_POS=0 fi }

Initial indexing

index_dir "$CURRENT_DIR"

------- Main loop -------

while true; do draw_page

IFS= read -r -n1 key || key=''

if [[ $key == $'' ]]; then
    IFS= read -r -n2 -t 0.05 rest || rest=''
    key+="$rest"
    case "$key" in
        $'[A') move_cursor_up ;;    # up
        $'[B') move_cursor_down ;;  # down
        $'[D') go_up ;;             # left arrow -> go up
        $'[C') enter_item ;;        # right arrow -> enter
        *) ;;
    esac
    continue
fi

if [[ $key == $'

' || $key == $' ' ]]; then enter_item continue fi

case "$key" in
    '')
        continue
        ;;
    $'') go_up ;;     # backspace / delete
    'q') break ;;
    'p') preview_file ;;
    'e') edit_file ;;
    'r') rename_file ;;
    'd') delete_file ;;
    'c') clipboard_copy ;;
    'x') clipboard_cut ;;
    'v') clipboard_paste ;;
    'm') move_file ;;
    'n') create_new ;;
    's') search_files ;;
    'i') show_info ;;
    'g') goto_top ;;
    'G') goto_bottom ;;
    'R') refresh_index ;;
    'h') show_help ;;
    ' ') # toggle mark
        {
            sel="$(get_selected_path)"
            [[ -n "$sel" ]] && toggle_mark "$sel"
        }
        ;;
    'C') copy_marked ;;
    'M') move_marked ;;
    'D') delete_marked ;;
    'u') unmark_all ;;
    'F')
        # add current dir to favorites
        if ! grep -Fxq -- "$CURRENT_DIR" "$DEST_FAV_FILE" 2>/dev/null; then
            printf '%s

' "$CURRENT_DIR" >> "$DEST_FAV_FILE" show_message "Added current dir to favorites." 0.7 else show_message "Already a favorite." 0.7 fi ;; $'	') ;; # ignore tab *) if [[ $key =~ [0-9] ]]; then digit="$key" if (( digit > 0 && digit <= TOTAL_PAGES )); then CURRENT_PAGE=$((digit - 1)) CURSOR_POS=0 fi fi ;; esac done

restore

disable_input_mode clear echo -e "[32mSession ended.[0m" if [[ -s "$SELECTION_FILE" ]]; then echo "Selections saved in: $SELECTION_FILE" else rm -f "$SELECTION_FILE" >/dev/null 2>&1 || true fi
