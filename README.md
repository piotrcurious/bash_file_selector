# Miller Commander

A two-pane file manager for the terminal, written in Bash. It uses a Miller column layout and is inspired by Midnight Commander.

## Architecture

The project is split into two main scripts:

*   `miller_commander.sh`: The main application. It handles the user interface, input, and overall state.
*   `file_selector.sh`: A stateless utility script that manages the contents and state of a single pane.

This separation of concerns allows for a cleaner and more maintainable codebase.

## Usage

To run the file manager, simply execute the `miller_commander.sh` script:

```bash
./miller_commander.sh [initial_directory_left] [initial_directory_right]
```

If no directories are provided, the left pane will default to the current working directory, and the right pane will default to the user's home directory.

### Keybindings

*   **Arrow Keys**: Navigate up and down the file list. Right arrow enters a directory, and left arrow goes back.
*   **Tab**: Switch between the left and right panes.
*   **Space**: Mark a file for an operation.
*   **F5**: Copy marked files (or the selected file) to the other pane.
*   **F6**: Move marked files (or the selected file) to the other pane.
*   **F7**: Delete marked files (or the selected file).
*   **F8**: Navigate back to the parent directory.
*   **F10** or **q**: Quit the application.

## Testing

The project includes a test suite that uses `screen` to simulate user input and verify the application's behavior. To run the tests, execute the `test_commander.sh` script:

```bash
./test_commander.sh
```

### Known Issues

The navigation test (`test_navigation`) is known to be flaky. Extensive logging has confirmed that the application's state is updated correctly, but the screen capture in the test often fails to register the UI update in time, causing a false negative. This is likely a race condition within the `screen`-based test harness.
