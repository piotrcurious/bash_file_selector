 preview_file() {
    local file="$(get_selected_path)"
    if [[ -d "$file" ]]; then
        echo "'$file' is a directory."
        sleep 1
        return
    fi
    mime=$(file --mime-type -b "$file")
    tput cnorm; stty sane
    clear
    echo "Previewing: $file"
    echo "---------------------------"
    case "$mime" in
        text/*)
            less "$file"
            ;;
        image/*)
            identify "$file" 2>/dev/null || file "$file"
            read -p "Press Enter to continue..."
            ;;
        application/pdf)
            pdftotext "$file" - | less
            ;;
        audio/*|video/*)
            ffprobe "$file" 2>&1 | less
            ;;
        application/zip)
            unzip -l "$file" | less
            ;;
        *)
            echo "Binary or unknown filetype. Hex preview:"
            xxd "$file" | less
            ;;
    esac
}

edit_file() {
    local file="$(get_selected_path)"
    if [[ -d "$file" ]]; then
        echo "'$file' is a directory."
        sleep 1
        return
    fi
    mime=$(file --mime-type -b "$file")
    tput cnorm; stty sane
    clear
    echo "Editing: $file"
    echo "---------------------------"
    case "$mime" in
        text/*)
            nano "$file"
            ;;
        *)
            hexedit "$file"
            ;;
    esac
}
