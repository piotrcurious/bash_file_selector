# Analysis of Script Versions

This document provides a concise, technically-focused summary of the changes between different versions of the `selecta` and `NoonCommander` scripts.

---

## `selecta.sh` vs `selecta2.sh`

- **Refactoring:** `selecta2.sh` is a rewrite with a more modular structure, using functions for drawing the UI, handling cursor movement, and file selection.
- **Features Added:** Multi-file selection, explicit pagination, and a quit option.
- **Features Removed:** Page Up/Down navigation, function key support for auxiliary scripts, and dynamic page sizing.
- **Technical Changes:** The script now uses `nl` for line numbering, `read -rsn1` for key handling, and a different `awk`-based implementation for word wrapping.

---

## `noonCommander/NoonC.sh` vs `noonCommander/NoonC2.sh`

- **Features Added:** Directory navigation (enter subdirectory, go up to parent), and the UI now displays the current directory path.
- **Technical Changes:** The script has been refactored to support directory navigation, with new functions for indexing directories, entering items, and going up. File operations have been updated to handle file paths correctly.

---

## `noonCommander/NoonC2.sh` vs `noonCommander/NoonC3.sh`

- **Features Added:** File preview (MIME-type aware, using external tools like `less`, `identify`, `pdftotext`, etc.) and file editing (`nano` for text, `hexedit` for binary).
- **Technical Changes:** The main loop now handles keybindings for the new preview and edit functions.

---

## `noonCommander/NoonC3.sh` vs `noonCommander/NoonC_v2_4.sh`

- **Features Added:** Multi-file marking and operations (copy, move, delete), a clipboard system for single-file copy/cut/paste, a destination picker with favorites, a more detailed UI with visual indicators for file types, the ability to create new files/directories, a detailed info panel, and a help panel.
- **Regressions:** The MIME-type-based preview/edit feature was replaced with a simpler preview (`bat`/`less`) and editing via the default system editor.
- **Technical Changes:** The script was heavily refactored for modularity and robustness, with a safer file indexing method, improved terminal handling, and a configuration file for favorite destinations.

---

## `noonCommander/NoonC_v2_4.sh` vs `noonCommander/NoonC_v3_0.sh`

- **Performance:** The script was refactored to use a temporary cache file for the file list instead of a Bash array, improving memory efficiency. The UI now streams from the cache file for faster rendering.
- **UI Enhancements:** The UI was polished with a new cursor and mark style, support for displaying symbolic links, a redesigned help panel, and truncation for long filenames.
- **Technical Changes:** The script now uses `set -euo pipefail` for stricter error handling, `readonly` variables, and more robust file operations. The `format_size` function was removed.

---

## `noonCommander/NoonC_v3_3.sh` vs `noonCommander/NoonC_v3_52.sh`

- **Bug Fix:** A critical bug in the `choose_destination` function that prevented the UI from being displayed was fixed by redirecting UI drawing to `stderr`.
- **Features Added:** A "Mark All" feature and support for `Backspace` to navigate to the parent directory.
- **UI Enhancements:** The help panel was improved, the `choose_destination` function now accepts a context-aware title, and screen clearing is more reliable.

---

## `noonCommander/NoonC_v3_52.sh` vs `noonCommander/NoonC_v4_5.sh`

- **Workflow Change:** The script was redesigned to use a more interactive clipboard model. Users now copy/cut items (single or marked) to the clipboard, navigate to a destination, and paste.
- **Features Added:** The clipboard now supports multiple items.
- **Technical Changes:** The script's error handling and robustness were improved, and arithmetic operations were made safer.

---

## `noonCommander/NoonC_v4_5.sh` vs `noonCommander/NoonCommander.sh`

- **Regression:** This version is a significant regression, reverting to an earlier, less feature-rich state.
- **Features Removed:** The interactive multi-file clipboard, advanced UI with colors and indicators, "Mark All" and "Unmark All" features, and the detailed help and info panels were all removed.
- **Technical Changes:** The script reverts to a less robust file indexing method, less safe arithmetic, and removes the terminal state restoration and alternate screen buffer features.

---

## `noonCommander/NoonCommander.sh` vs `noonCommander/NoonCv5.sh`

- **Features Added:** This version reintroduces many of the advanced features from previous versions, including a robust file indexing mechanism, multi-file marking, a clipboard system, an enhanced UI with colors and more detailed information, new navigation commands (`g` for top, `G` for bottom, `R` for refresh), and a comprehensive help panel.
- **Technical Changes:** The script has been substantially refactored and expanded, with a more organized structure and a greater number of functions. Error handling and the preview/edit functionalities have also been improved.
