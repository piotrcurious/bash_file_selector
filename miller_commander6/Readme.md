# Miller Commander - v6

This version adds file and directory size information to the UI.

### Key Features:

*   **File Size Display:** The `file_selector.sh` is updated to include a `get_formatted_size` function, and the UI now displays the size of each file in a separate column.
*   **Directory Size Calculation:** A `calculate_size` function is added to `miller_commander.sh`, which can be triggered by pressing `Ctrl+G`. This function uses `du` to calculate the total size of any marked files or directories and displays the result in the status bar.
*   **Help File:** A `HELP.txt` file is introduced, which can be viewed by pressing `F1`.
