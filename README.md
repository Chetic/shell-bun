# Shell-Bun

> ☕ **Shell-Bun** combines "build" and "run" - inspired by Swedish fika culture, where gathering for coffee and pastries (🍩🍰) creates the perfect environment for productive collaboration!

An interactive bash script for managing build environments with advanced features and no external dependencies.

## 🚀 Easy Deployment

**Shell-Bun is completely standalone** - it's a single bash script with zero dependencies that can be deployed anywhere instantly:

- **Copy & Run**: Simply copy `shell-bun.sh` to any system with bash > 4, write a simple `shell-bun.cfg` file and run `shell-bun.sh`
- **No Installation Required**: No package managers, no compilation, no setup scripts
- **Portable**: Works on Linux, macOS, Windows (with bash), containers, cloud instances, embedded systems
- **Self-Contained**: Everything needed is in one file - perfect for DevOps, CI/CD, and quick deployments
- **Version Control Friendly**: Add it directly to your project repositories

## Features

- **Unified Interactive Menu**: Seamlessly combine arrow-key navigation with fuzzy search typing
- **Multi-Selection**: Select multiple commands and execute them in parallel
- **Simple Configuration Format**: Define applications and their build commands in a clean INI-style format
- **Working Directory Support**: Specify custom working directories for each application
- **Built-in Status Messages**: Automatic progress logging with emojis and colors
- **Parallel Execution**: Run multiple commands simultaneously with execution summary
- **Color-coded Output**: Beautiful terminal interface with intuitive visual feedback
- **No Dependencies**: Pure bash implementation with no external tools required

## Usage

### Running the Script

```bash
# Use default config file (shell-bun.cfg)
./shell-bun.sh

# Use custom config file
./shell-bun.sh my-config.txt

# Enable debug mode (creates debug.log file)
./shell-bun.sh --debug
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

## Configuration File Format

The configuration file uses a simple INI-style format:

```ini
# Comments start with #
[ApplicationName]
build_host=command to build for host
build_target=command to build for target platform
run_host=command to run on host
clean=command to clean build directory
working_dir=optional/path/to/working/directory

[AnotherApp]
build_host=make all
run_host=./app
clean=make clean
working_dir=~/projects/my-app
```

### Available Command Types

- `build_host`: Commands to build the application for the host platform
- `build_target`: Commands to build for a target platform (cross-compilation)
- `run_host`: Commands to run the application on the host
- `clean`: Commands to clean build artifacts
- `working_dir`: Optional working directory where commands should be executed

### Working Directory Support

The `working_dir` field allows you to specify where commands should be executed:

- **Absolute paths**: `/full/path/to/directory`
- **Relative paths**: `../relative/path` (relative to script location)
- **Tilde expansion**: `~/user/directory` (expands to home directory)
- **Default behavior**: If not specified, commands run from the script's directory

```ini
[WebApp]
build_host=npm run build
working_dir=~/projects/my-webapp

[BackendAPI]
build_host=cargo build --release
working_dir=../backend

[LegacySystem]
build_host=make all
working_dir=/opt/legacy-app
```

### Example Configuration

See `shell-bun.cfg` for a complete example with multiple applications using `sleep` commands for testing.

## Command Execution

### Single Command Execution
1. Navigate to or filter for desired command
2. Press Enter to execute immediately

### Parallel Execution
1. Use Space to select multiple commands (shows [✓] indicator)
2. Press Enter when items are selected to run all simultaneously
Commands execute in parallel in background processes

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


## Customization

To create your own build environment:

1. Copy `shell-bun.cfg` to a new file
2. Replace the example applications with your actual projects
3. Replace `sleep` commands with real build commands
4. Optionally specify working directories for each application
5. Run the script with your config file
