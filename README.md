# Shell-Bun

> ☕ **Shell-Bun** combines "build" and "run" - inspired by Swedish fika culture, where gathering for coffee and pastries (🍩🍰) creates the perfect environment for productive collaboration!

A terminal user interface written in Go (powered by [Bubble Tea](https://github.com/charmbracelet/bubbletea)) for managing build environments with speed, parallelism, and polish.

![demo](shell-bun-demo.gif)

## 🚀 Easy Deployment

**Shell-Bun ships as a single self-contained binary** – build it once with Go and copy it anywhere:

- **Build & Copy**: `go build ./cmd/shellbun` produces the `shellbun` executable ready for distribution
- **No External Dependencies**: Everything is linked into the binary (Bubble Tea, lipgloss, etc.)
- **Portable**: Works on Linux, macOS, Windows (via cross-compilation), containers, cloud instances, embedded systems
- **Self-Contained**: No runtime installation scripts or package managers required
- **Version Control Friendly**: Commit the binary or build recipe alongside your project

## Features

- **Completely Generic Actions**: Define any action names you want (build, test, deploy, lint, etc.)
- **Unified Interactive Menu**: Seamlessly combine arrow-key navigation with fuzzy search typing
- **Multi-Selection**: Select multiple commands and execute them in parallel
- **Simple Configuration Format**: Define applications and their commands in a clean INI-style format
- **Working Directory Support**: Specify custom working directories for each application
- **Built-in Status Messages**: Automatic progress logging with emojis and colors
- **Parallel Execution**: Run multiple commands simultaneously with execution summary
- **Automatic Logging**: Commands logged to timestamped files with configurable log directories
- **Containerized Execution**: Optionally run all commands through a configurable container command
- **Interactive Log Viewer**: Browse and view execution logs after everything is completed
- **Color-coded Output**: Beautiful terminal interface with intuitive visual feedback
- **Single Binary Distribution**: Compiled Go executable with Bubble Tea UI stack included

## 🤖 CI/CD & Automation Ready

Shell-Bun is designed for both interactive development and automated CI/CD pipelines:

### Non-Interactive Mode
- **Scriptable**: Run specific commands without user interaction
- **Pipeline Friendly**: Proper exit codes (0 = success, 1 = failure)
- **Batch Operations**: Execute multiple actions in sequence
- **Error Handling**: Clear error messages and failure reporting
- **Structured Output**: CI-friendly logging format
- **Parallel Processing**: All actions execute simultaneously for maximum speed
- **Pattern Matching**: Fuzzy matching with wildcards and substrings

### Perfect for DevOps
- **Standardize Builds**: Same build commands across development and CI
- **Version Control**: Check the script into your repository 
- **No Installation**: Works immediately on any CI runner with bash
- **Flexible Configuration**: Different configs for dev, staging, production
- **Debug Support**: Enhanced logging for troubleshooting build issues
- **High Performance**: Parallel execution reduces build times significantly

## Usage

### Build the Binary
```bash
go build ./cmd/shellbun
```

### Interactive Mode (Default)
```bash
# Use default config file (shell-bun.cfg)
./shellbun

# Use custom config file
./shellbun --config my-config.cfg

# Enable debug mode (creates/overwrites debug.log)
./shellbun --debug
```

### Non-Interactive Mode (CI/CD)
```bash
# Run multiple actions for an application
./shellbun --ci APIServer test_unit,deploy_staging
```

**Fuzzy Pattern Matching:**
Shell-Bun supports powerful pattern matching for both applications and actions in CI mode:

```bash
# Wildcard patterns  
./shellbun --ci "API*" "build*"             # Apps starting with 'API', actions starting with 'build'
```

**CI Mode Features:**
- ✅ **Zero user interaction** - perfect for automated pipelines
- ✅ **Proper exit codes** - exits with 0 on success, 1 on failure
- ✅ **Clear output** - structured logging suitable for CI systems
- ✅ **Error handling** - detailed error messages and failure reporting
- ✅ **Multiple actions** - run several commands in sequence
- ✅ **Flexible execution** - run specific actions or all available actions
- ✅ **Parallel processing** - multiple applications run simultaneously for faster builds
- ✅ **Fuzzy pattern matching** - powerful wildcards and substring matching

### On Windows

Build for Windows using Go's cross-compilation support:
```bash
GOOS=windows GOARCH=amd64 go build -o shellbun.exe ./cmd/shellbun
```

Run the resulting executable in PowerShell, Command Prompt, or a terminal of your choice.

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

# Global settings (before any app sections)
log_dir=logs       # Global log directory for all apps
container=docker run --rm ubuntu

[ApplicationName]
# Define any action names - completely customizable!
build=command to build the application
test_unit=command to run unit tests
deploy_production=command to deploy to production
clean=command to clean build artifacts
working_dir=optional/path/to/working/directory
log_dir=optional/path/to/override/global/log/dir  # Optional per-app override

[AnotherApp]
build=make all
test=make test
serve=./start_server.sh
clean=make clean
working_dir=~/projects/my-app
```

- `log_dir` (optional): Sets a global directory where log files are stored. Individual apps can override it.
- `container` (optional): When set, every command is executed inside the specified container command. Shell-Bun automatically appends `bash -lc "<your command>"` to the container invocation so complex workflows can stay isolated.

## Testing

Shell-Bun includes a comprehensive test suite to ensure reliability and maintainability.

### Running Tests Locally

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test suite
./tests/run_tests.sh -t ci_mode

# Run with verbose output
./tests/run_tests.sh -v
```

### Prerequisites

- **Bash 4.0+** (same as Shell-Bun)
- **BATS** (Bash Automated Testing System)

The test runner will automatically install BATS if it's not found, or you can install it manually:

```bash
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats
```

### Test Suite Coverage

The test suite includes comprehensive tests for:

- ✅ Configuration file parsing and validation
- ✅ CI mode execution (single and parallel)
- ✅ Pattern matching (exact, wildcard, substring)
- ✅ Working directory handling
- ✅ Log directory configuration
- ✅ Command-line argument parsing
- ✅ Error handling and edge cases
- ✅ Container command integration

### Continuous Integration

Tests run automatically on:
- Pull requests to main/master branches
- Pushes to main/master
- Before creating releases

The CI pipeline tests on multiple platforms (Ubuntu, macOS) and Bash versions (4.4, 5.0, 5.1, 5.2).

For detailed testing documentation, see [tests/README.md](tests/README.md).
