# Shell-Bun

> ☕ **Shell-Bun** combines "build" and "run" - inspired by Swedish fika culture, where gathering for coffee and pastries (🍩🍰) creates the perfect environment for productive collaboration!

An interactive Rust application for managing build environments with advanced features, featuring a beautiful TUI and parallel execution.

![demo](shell-bun-demo.gif)

## 🚀 Installation

**Shell-Bun is a Rust application** that can be built from source or installed via cargo:

### Build from Source
```bash
cargo build --release
# Binary will be at target/release/shell-bun
```

### Install via Cargo
```bash
cargo install --path .
```

### Features
- **Single Binary**: Build once, run anywhere - Linux, macOS, Windows
- **Fast**: Written in Rust with parallel execution support
- **Modern TUI**: Beautiful terminal interface with fuzzy search
- **Portable**: Works in containers, cloud instances, and CI/CD pipelines

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
- **Fast & Reliable**: Written in Rust for performance and safety

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
- **Easy Installation**: Simple `cargo build` or use pre-built binaries
- **Flexible Configuration**: Different configs for dev, staging, production
- **Debug Support**: Enhanced logging for troubleshooting build issues
- **High Performance**: Parallel execution reduces build times significantly

## Usage

### Running the Script

#### Interactive Mode (Default)
```bash
# Use default config file (shell-bun.cfg)
shell-bun

# Use custom config file
shell-bun my-config.txt

# Enable debug mode
shell-bun --debug

# Override the container command for this run
shell-bun --container "podman exec -it my-builder" my-config.txt
```

#### Non-Interactive Mode (CI/CD)
```bash
# Run multiple actions for an application
shell-bun --ci APIServer test_unit,deploy_staging

# With custom config file
shell-bun --ci APIServer test_unit,deploy_staging my-config.cfg
```

**Fuzzy Pattern Matching:**
Shell-Bun supports powerful pattern matching for both applications and actions in CI mode:

```bash
# Wildcard patterns  
shell-bun --ci "API*" "build*"             # Apps starting with 'API', actions starting with 'build'
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

### Building and Development

**Prerequisites:**
- Rust 1.70+ (install from [rustup.rs](https://rustup.rs/))

**Development:**
```bash
# Clone the repository
git clone https://github.com/Chetic/shell-bun.git
cd shell-bun

# Build in debug mode
cargo build

# Build release binary
cargo build --release

# Run tests
cargo test
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
- `container` (optional): When set, every command is executed inside the specified container command. Shell-Bun automatically appends `bash -lc "<your command>"` to the container invocation so complex workflows can stay isolated. You can override the configured value per run with the `--container` CLI flag.

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

- **Rust 1.70+** (install from [rustup.rs](https://rustup.rs/))

Tests are written in Rust and run with `cargo test`:

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
