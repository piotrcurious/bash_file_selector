# NoonCommander Development Roadmap

This document outlines a roadmap for the future development of `NoonCommander`, based on an analysis of its version history. The goal is to create a unified, feature-rich, and stable `NoonCommander v6`.

## 1. Backportable Bug Fixes and Features

The following features and bug fixes are considered safe and highly beneficial to backport to all existing versions of the script:

*   **Terminal State Restoration:** The practice of capturing and restoring terminal settings (`stty -g`) is crucial for preventing terminal issues after the script exits. This should be implemented in all versions.
*   **Alternate Screen Buffer:** Using the alternate screen buffer (`tput smcup`/`tput rmcup`) provides a cleaner user experience and should be a standard feature.
*   **Subshell UI Bug Fix:** The fix for the `choose_destination` function, which redirects UI drawing to `stderr`, is essential for any version that uses this function or a similar pattern.
*   **Robust File Indexing:** The use of `find -print0` and `mapfile` for file indexing is a significant improvement for handling filenames with special characters and should be adopted in all versions.

## 2. Re-introduction of Regressed Features

The following features were present in some versions but were lost in others. They should be re-introduced in a future unified version:

*   **Advanced File Preview:** The MIME-type-aware file preview from `NoonC3.sh` was a powerful feature that should be restored, providing a richer user experience than a simple `less` or `bat` preview.
*   **Advanced Editing:** The ability to open binary files in a hex editor, as seen in `NoonC3.sh`, should also be re-introduced.

## 3. Proposed Feature Set for `NoonCommander v6`

A future `NoonCommander v6` should consolidate the best features from all versions into a single, stable script. The proposed feature set includes:

*   **Core Functionality:**
    *   Directory navigation, including "go up" with `Backspace`.
    *   Multi-file marking and operations.
    *   An interactive, multi-item clipboard for copy, cut, and paste.
    *   The ability to create new files and directories.
    *   A comprehensive, searchable help panel.
*   **UI:**
    *   A detailed and colorful UI with visual indicators for file types, symbolic links, and marked items.
    *   A destination picker with support for favorites.
*   **Technical Excellence:**
    *   Robust error handling with `set -euo pipefail`.
    *   Safe arithmetic and file operations.
    *   Proper terminal state management and use of the alternate screen buffer.
    *   A clean, modular, and well-documented codebase.
