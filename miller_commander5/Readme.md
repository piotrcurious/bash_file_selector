# Miller Commander - v5

This version introduces a significant performance optimization for UI rendering.

### Key Feature:

*   **Separate Pane Refresh:** A `draw_single_pane` function is introduced, allowing the application to redraw only the active pane instead of the entire screen. This is particularly noticeable during navigation and scrolling, resulting in a much smoother and more responsive user experience.
*   **Overwrite Confirmation:** An interactive confirmation prompt (`confirm_overwrite` function) is added for copy and move operations to prevent accidentally overwriting files. This prompt includes "Yes," "No," and "All" options.
