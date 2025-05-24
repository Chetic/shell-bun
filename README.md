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

### Navigation & Selection
- **↑/↓ Arrow Keys**: Navigate through filtered options
- **Type**: Filter commands in real-time (fuzzy search)
- **Space**: Toggle selection of current item
- **Enter**: Execute highlighted command immediately
- **ESC**: Quit the application

### Batch Operations
- **'+'**: Select all actionable commands
- **'-'**: Clear all selections
- **Tab**: Run all selected commands in parallel
- **Enter**: Run selected commands (if any selected), otherwise execute highlighted command

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
3. Confirmation prompt before execution
4. Real-time status updates with emojis

### Parallel Execution
1. Use Space to select multiple commands
2. Press Tab (or Enter when items selected) to run all selected commands
3. Commands execute simultaneously in background
4. Execution summary with success/failure counts

## Built-in Status Messages

Shell-Bun automatically provides status messages for all operations:

```
🚀 Starting: MyWebApp - Build (Host)
✅ Completed: MyWebApp - Build (Host)
❌ Failed: APIServer - Build (Target)

📊 Execution Summary:
✅ Successful: 4
❌ Failed: 1
```

## Advanced Features

### Fuzzy Search
Type any part of an application name or command to filter results:
- Type "web" to find "MyWebApp" items
- Type "build" to show all build commands
- Type "api host" to find "APIServer - Build (Host)"

### Smart Selection
- Selection persists across filtering
- Can't select "Show Details" items for execution
- Visual feedback for all selected items

### Parallel Processing
- Multiple commands run simultaneously
- Individual status tracking for each command
- Overall execution summary
- Non-blocking interface during execution

## Safety Features

- Commands are displayed before execution
- User confirmation required for single commands
- Exit codes are captured and displayed
- Ctrl+C can be used to cancel at any time
- Failed commands don't affect other parallel executions

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

- Instant filtering and navigation
- Non-blocking parallel execution
- Minimal resource usage
- Works efficiently with dozens of applications

## Troubleshooting

- **Script not executable**: Use `bash shell-bun.sh` instead of `./shell-bun.sh`
- **Colors not working**: Your terminal may not support ANSI colors
- **Arrow keys not working**: Ensure you're in a proper bash terminal
- **Parallel execution issues**: Check if your commands conflict with each other
- **Config file not found**: Check the file path and permissions

## License

This script is provided as-is for educational and development purposes. 