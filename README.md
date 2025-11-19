# Shell-Bun

> ☕ **Shell-Bun** combines "build" and "run" - inspired by Swedish fika culture, where gathering for coffee and pastries (🍩🍰) creates the perfect environment for productive collaboration!

An interactive Python script for managing build environments with advanced features and minimal dependencies.

![demo](shell-bun-demo.gif)

## 🚀 Easy Deployment

**Shell-Bun is completely standalone** - it's a single Python script with minimal dependencies that can be deployed anywhere instantly:

- **Copy & Run**: Simply copy `shell_bun.py` to any system with Python 3.6+, write a simple `shell-bun.cfg` file and run `python shell_bun.py`
- **Minimal Dependencies**: Uses only Python standard library (stdlib) - no external packages required for production use
- **Portable**: Works on Linux, macOS, Windows, containers, cloud instances, embedded systems
- **Self-Contained**: Everything needed is in one file - perfect for DevOps, CI/CD, and quick deployments
- **Version Control Friendly**: Add it directly to your project repositories

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
- **Minimal Dependencies**: Pure Python implementation using only standard library (no external packages required)

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
- **No Installation**: Works immediately on any CI runner with Python 3.6+
- **Flexible Configuration**: Different configs for dev, staging, production
- **Debug Support**: Enhanced logging for troubleshooting build issues
- **High Performance**: Parallel execution reduces build times significantly

## Usage

### Running the Script

#### Interactive Mode (Default)
```bash
# Use default config file (shell-bun.cfg)
python shell_bun.py

# Use custom config file
python shell_bun.py my-config.txt

# Enable debug mode (creates debug.log file)
python shell_bun.py --debug

# Override the container command for this run
python shell_bun.py --container "podman exec -it my-builder" my-config.txt
```

#### Non-Interactive Mode (CI/CD)
```bash
# Run multiple actions for an application
python shell_bun.py --ci APIServer test_unit,deploy_staging
```

**Fuzzy Pattern Matching:**
Shell-Bun supports powerful pattern matching for both applications and actions in CI mode:

```bash
# Wildcard patterns  
python shell_bun.py --ci "API*" "build*"             # Apps starting with 'API', actions starting with 'build'
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

Since this is a Python script, you'll need Python 3.6+ installed:
- Download from [python.org](https://www.python.org/downloads/)
- Or use Windows Store Python
- Or use package managers like Chocolatey: `choco install python`

Example:
```bash
python shell_bun.py
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
python tests/run_tests.py

# Run specific test suite
python tests/run_tests.py -t ci_mode

# Run with verbose output
python tests/run_tests.py -v
```

### Prerequisites

- **Python 3.6+** (same as Shell-Bun)
- **pytest** (Python testing framework)

The test runner will automatically install pytest if it's not found, or you can install it manually:

```bash
# Install pytest
pip install pytest

# Or use the requirements file
pip install -r requirements.txt
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

The CI pipeline tests on multiple platforms (Ubuntu, macOS, Windows) and Python versions (3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.12).

For detailed testing documentation, see [tests/README.md](tests/README.md).
