# NoonCommander Version Analysis

This document provides a detailed analysis of the evolution of the `NoonCommander` shell script, tracking feature changes, bug fixes, and regressions across versions.

### `selecta.sh`

*   **Initial State:** A basic file selection script. It can list files and save a selection to a temporary file. It lacks advanced navigation, file operations, and a sophisticated UI.

### `NoonC.sh`

*   **Feature Change:** This is a more advanced file manager than `selecta.sh`. It introduces a paginated display, cursor navigation, and basic file operations (rename, delete, copy, move).
*   **Known Issues:** This version lacks directory navigation.

### `NoonC2.sh`

*   **Feature Change:** This version introduces directory navigation, allowing the user to move into subdirectories and go up to parent directories. It also switches to a more robust method of getting the selected file path.

### `NoonC3.sh`

*   **Context:** This file is a **code snippet**, not a full script. It contains two functions: `preview_file` and `edit_file`, which are designed to be integrated into a larger script.
*   **Feature Change:**
    *   `preview_file` introduces a MIME-type-aware preview, using different tools (`less`, `identify`, `pdftotext`, `ffprobe`, `unzip`, `xxd`) for different file types.
    *   `edit_file` also checks the MIME type, opening text files in `nano` and binary files in `hexedit`.

### `NoonCommander.sh`

*   **Feature Change:** This version integrates the advanced preview and edit functionalities from `NoonC3.sh` into a complete file manager. It also adds a host of new features:
    *   A colorful UI with a detailed header and keybinding summary.
    *   A clipboard for copy and cut operations.
    *   The ability to create new files and directories.
    *   A file search function.
    *   A detailed file information panel.

### `NoonC_v2_4.sh`

*   **Feature Change:** This version is a major refactoring, focusing on code quality, robustness, and new features. Key changes include:
    *   **Marks System:** Introduces the ability to mark multiple files for bulk operations.
    *   **Destination Picker:** Adds a destination picker with support for favorites.
    *   **Improved UI:** A more professional and organized UI.
    *   **Code Quality:** The code is more modular and uses more robust practices, such as using `mapfile` for file indexing.

### `NoonC_v3_0.sh`

*   **Feature Change:** This version builds on `v2.4`, with a focus on optimization and UI improvements.
    *   **Performance:** Switches from a bash array to a cache file for file indexing, which is more memory-efficient.
    *   **UI:** The UI is refined, with improved visual indicators for file types, symbolic links, and marked items.

### `NoonC_v3_3.sh`

*   **Bug Fix:** This version introduces critical bug fixes related to terminal state management.
    *   **Terminal State Restoration:** It captures and restores the initial terminal settings (`stty -g`), preventing issues after the script exits.
    *   **Alternate Screen Buffer:** It uses the alternate screen buffer (`tput smcup`/`rmcup`) for a cleaner user experience.

### `NoonC_v3_52.sh`

*   **Bug Fix:** This version fixes a critical bug where the UI for the `choose_destination` function was being captured by a variable, by redirecting all UI drawing to `stderr`.
*   **Feature Change:** Adds the ability to mark all items in the current directory.

### `NoonC_v4_5.sh`

*   **Feature Change:** This is a highly polished and feature-rich version.
    *   **Interactive Clipboard:** Introduces an interactive clipboard that works with both single and multiple marked items.
    *   **Improved Bulk Operations:** The workflow for bulk operations is improved, allowing the user to mark items, navigate to a destination, and then paste.

### `NoonCv5.sh`

*   **Major Regression:** This version represents a significant step backward in the script's evolution. It appears to be a rewrite or modification of an earlier version, and it **loses many of the advanced features and bug fixes** from `v2.4` through `v4.5`, including:
    *   The alternate screen buffer and proper terminal state restoration.
    *   The interactive, multi-item clipboard.
    *   The destination picker with favorites.
    *   The robust file indexing and UI rendering methods.
*   **Feature Change:** It re-introduces a more basic set of features, similar to `NoonCommander.sh`, but with some improvements such as a more organized main loop.
