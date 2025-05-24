# Shell-Bun

An interactive bash script for managing build environments with advanced features and no external dependencies.

## Features

- **Unified Interactive Menu**: Seamlessly combine arrow-key navigation with fuzzy search typing
- **Multi-Selection**: Select multiple commands and execute them in parallel
- **Simple Configuration Format**: Define applications and their build commands in a clean INI-style format
- **Built-in Status Messages**: Automatic progress logging with emojis and colors
- **Parallel Execution**: Run multiple commands simultaneously with execution summary
- **Color-coded Output**: Beautiful terminal interface with intuitive visual feedback
- **No Dependencies**: Pure bash implementation with no external tools required

## Usage

### Running the Script

```bash
# Use default config file (build-config.txt)
./shell-bun.sh

# Use custom config file
./shell-bun.sh my-config.txt

# Enable debug mode (creates debug.log file)
./shell-bun.sh --debug

# Debug mode with custom config
./shell-bun.sh --debug my-config.txt
```

### On Windows

Since this is a bash script, you'll need to run it in a bash environment like:
- Git Bash
- WSL (Windows Subsystem for Linux) 
- Cygwin
- MSYS2

Example in Git Bash:
```bash
bash shell-bun.sh
```

## Interactive Controls

### Navigation
- **↑/↓ Arrow Keys**: Navigate through filtered options
- **Page Up/Page Down**: Jump 10 lines up/down for faster navigation
- **Type any character**: Filter commands in real-time (fuzzy search)
- **Backspace**: Remove characters from filter
- **ESC**: Quit the application

### Selection & Execution
- **Space**: Toggle selection of current item for batch execution
- **Enter**: Execute highlighted command OR run all selected commands (if any selected)
- **'+'**: Select all actionable commands
- **'-'**: Clear all selections

### Visual Indicators
- **Green ►**: Currently highlighted item
- **[✓]**: Item selected for batch execution
- **🚀**: Command starting
- **✅**: Command completed successfully
- **❌**: Command failed

## Configuration File Format

The configuration file uses a simple INI-style format:

```ini
# Comments start with #
[ApplicationName]
build_host=command to build for host
build_target=command to build for target platform
run_host=command to run on host
clean=command to clean build directory

[AnotherApp]
build_host=make all
run_host=./app
clean=make clean
```

### Available Command Types

- `build_host`: Commands to build the application for the host platform
- `build_target`: Commands to build for a target platform (cross-compilation)
- `run_host`: Commands to run the application on the host
- `clean`: Commands to clean build artifacts

### Example Configuration

See `build-config.txt` for a complete example with multiple applications using `sleep` commands for testing.

## Sample Applications

The included `build-config.txt` contains example applications:

- **MyWebApp**: Web application with host/target builds
- **DatabaseService**: Database service with host build and run
- **MobileApp**: Mobile app with dev and production builds
- **APIServer**: API server with host and ARM target builds
- **Frontend**: Frontend application with dev server
- **TestSuite**: Test suite with compilation and execution

## Command Execution

### Single Command Execution
1. Navigate to or filter for desired command
2. Press Enter to execute immediately
3. Real-time status updates with emojis
4. Execution summary with success/failure status

### Parallel Execution
1. Use Space to select multiple commands (shows [✓] indicator)
2. Press Enter when items are selected to run all simultaneously
3. Commands execute in parallel in background processes
4. Detailed execution summary with individual success/failure tracking

## Built-in Status Messages

Shell-Bun automatically provides status messages for all operations:

```
🚀 Starting: MyWebApp - Build (Host)
✅ Completed: MyWebApp - Build (Host)
❌ Failed: APIServer - Build (Target)

📊 Execution Summary:
✅ Successful: 4
❌ Failed: 1
Failed commands:
  - APIServer - Build (Target)
```

## Advanced Features

### Fuzzy Search
Type any part of an application name or command to filter results instantly:
- Type "web" to find "MyWebApp" items
- Type "build" to show all build commands
- Type "api host" to find "APIServer - Build (Host)"
- Search is case-insensitive and matches anywhere in the text

### Smart Selection Management
- Selection persists across filtering operations
- Can't select "Show Details" items for execution
- Visual feedback for all selected items with [✓] markers
- Clear selection status display

### Enhanced Navigation
- Page Up/Page Down for quick navigation through long lists
- Arrow keys for precise navigation
- Filter state preserved during navigation

### Parallel Processing
- Multiple commands run simultaneously in background
- Individual status tracking for each command
- Overall execution summary with detailed failure reporting
- Non-blocking interface during execution

### Debug Mode
Enable debug mode for troubleshooting:
```bash
./shell-bun.sh --debug
```

Debug mode features:
- Creates `debug.log` file with detailed execution logs
- Enhanced error output display
- Key press analysis for terminal compatibility issues
- Detailed command execution tracking

## Safety Features

- Commands are displayed before execution
- User-friendly execution summaries
- Exit codes are captured and displayed
- Failed commands don't affect other parallel executions
- Ctrl+C can be used to cancel operations
- Error output captured and optionally displayed in debug mode

## Terminal Compatibility

Shell-Bun includes enhanced compatibility features:
- **WSL Support**: Special handling for Windows Subsystem for Linux key detection
- **Various Terminal Types**: Works with Git Bash, standard bash, zsh, etc.
- **Key Detection**: Advanced key sequence detection for arrow keys, page up/down
- **Color Support**: Automatic color detection and fallback

## Customization

To create your own build environment:

1. Copy `build-config.txt` to a new file
2. Replace the example applications with your actual projects
3. Replace `sleep` commands with real build commands
4. Run the script with your config file

Example real-world configuration:
```ini
[WebAPI]
build_host=cd api && npm install && npm run build
build_target=cd api && npm run build:prod
run_host=cd api && npm start
clean=cd api && rm -rf node_modules dist

[Frontend]
build_host=cd frontend && yarn install && yarn build
run_host=cd frontend && yarn dev
clean=cd frontend && rm -rf node_modules dist

[Backend]
build_host=cargo build
build_target=cargo build --release
run_host=cargo run
clean=cargo clean
```

## Performance

- Instant filtering and navigation response
- Non-blocking parallel execution
- Minimal resource usage
- Efficiently handles dozens of applications
- Background process management for parallel commands

## Troubleshooting

### Common Issues
- **Script not executable**: Use `bash shell-bun.sh` instead of `./shell-bun.sh`
- **Colors not working**: Your terminal may not support ANSI colors
- **Arrow keys not working**: Ensure you're in a proper bash terminal
- **Config file not found**: Check the file path and permissions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Fredrik Reveny 