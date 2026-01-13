# Noon Commander

This directory contains Noon Commander, a single-pane file manager written in Bash. The scripts have evolved over time, with each version adding new features and improvements.

## Feature Evolution

### `NoonC.sh` - The Initial Version

This is the first iteration of Noon Commander. It provides a basic but functional file manager with the following core features:

-   **File Indexing and Pagination:** Lists files in the current directory with support for multiple pages.
-   **Basic Navigation:** Uses arrow keys for moving the cursor.
-   **File Operations:** Supports `rename`, `delete`, `copy`, and `move` operations, each prompting for user input.

### `NoonCommander.sh` - Major Enhancements

This version represents a significant leap forward in functionality and user experience:

-   **Advanced UI:** A more polished interface with color-coded file types and a detailed header.
-   **File Preview:** Introduces a `preview_file` function that can display the contents of various file types (text, images, PDFs, archives).
-   **External Editor Support:** The `edit_file` function allows for editing files in an external editor (`$EDITOR`).
-   **Clipboard:** Implements a clipboard for `copy` and `cut` operations, allowing the user to navigate to a destination and `paste`.
-   **Search:** Adds a `search_files` function to find files within the current directory.
-   **File Information:** The `show_info` function displays detailed information about a file.

### `NoonC_v4_5.sh` & `NoonCv5.sh` - Marks and Bulk Operations

These versions introduce the ability to work with multiple files at once:

-   **File Marking:** Users can now mark multiple files for selection.
-   **Bulk Operations:** `Copy`, `move`, and `delete` operations can now be performed on all marked files.
-   **Destination Favorites:** A destination picker with a favorites system is added to streamline copy and move operations.
-   **Improved Robustness:** Better handling of filenames with spaces and special characters.
-   **Help Screen:** A help screen is added to explain the various keybindings.

The `v5` and `v6` scripts in this directory are further iterations on this foundation, with minor bug fixes and refinements.
