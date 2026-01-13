# Miller Commander - v1

This is the initial version of the Miller Commander, a dual-pane file manager written in Bash.

### Key Features:

*   **Dual-Pane UI:** Uses a `awk`-based compositor to render two panes side-by-side.
*   **Stateless Pane Management:** The `file_selector.sh` script handles pane logic (directory indexing, navigation, marking) in a stateless manner.
*   **Basic Operations:** Supports `copy`, `move`, and `delete` operations between panes using F-keys.
*   **Core Navigation:** Arrow keys for movement, `Enter` to enter directories, and `Tab` to switch panes.
