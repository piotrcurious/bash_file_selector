# Miller Commander - v2

This version introduces significant performance and usability improvements.

### Key Enhancements:

*   **Partial UI Updates:** Implemented a partial redraw mechanism. Instead of redrawing the entire screen on every keypress, this version only updates the lines that have changed, resulting in a much smoother experience, especially on slow connections. The `file_selector.sh` now returns a `lines_to_update` variable to facilitate this.
*   **External Program Integration:** Added support for opening files in external editors and viewers (e.g., `nano`, `less`) using the `suspend_and_run` function.
*   **Full F-Key Support:** Expanded keybindings to include a full range of function keys for operations like `View` (F2), `Edit` (F3), and `MkDir` (F4).
