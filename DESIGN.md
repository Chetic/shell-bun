# Shell-Bun Design

## Table of Contents
- [Overview](#overview)
- [Design Philosophy](#design-philosophy)
- [Core Features](#core-features)
- [Architecture](#architecture)
- [Configuration System](#configuration-system)
- [Execution Modes](#execution-modes)
- [User Interface](#user-interface)
- [Use Cases](#use-cases)
- [Technical Implementation](#technical-implementation)
- [Testing and Quality](#testing-and-quality)

---

## Overview

**Shell-Bun** is a command-line tool for managing build environments, development workflows, and task automation. The configuration file format is intentionally simple to welcome users of all levels of experience. The configuration file is shared between local and continuous integration builds to support a single source of truth for how software is built and managed.

> **Implementation note (2025):** The reference implementation now uses Go with the Bubble Tea TUI framework, replacing the earlier bash prototype while preserving all behaviours outlined in this document.

### Purpose

Shell-Bun addresses the need for managing multiple applications and their various build/test/deploy commands through a unified interface. The tool provides:

1. **Unified Task Management**: A single tool to manage build, test, deployment, and custom commands across multiple applications
2. **Interactive and Automated Execution**: Support for both interactive development use and CI/CD automation
3. **Single-File Distribution**: Distributed as a standalone executable with no external dependencies
4. **Flexible Configuration**: INI-style configuration supporting user-defined workflows

### Design Characteristics

- **Generic Action System**: Actions are user-defined rather than prescribed by the tool
- **Single-File Distribution**: Distributed as a single executable file
- **Dual-Mode Operation**: Supports both interactive and non-interactive execution
- **Portable**: Runs on Linux, macOS, Windows, containers, and cloud instances

---

## Design Philosophy

### 1. Single-File Distribution

The tool is distributed as a single executable file with no external dependencies. This design choice enables:

- Distribution as a single file
- Version control alongside project code
- Deployment without package managers or installation procedures
- Execution in restricted environments

### 2. User-Defined Configuration

The tool does not enforce predefined action names or directory structures:

- Actions are defined by users in configuration (e.g., `build_host`, `test_integration`, `deploy_staging`)
- No required directory structure
- Working directories, log locations, and container execution are configurable per application

### 3. Unified Configuration for Development and CI

The same configuration file supports both interactive development and automated CI/CD execution. This approach eliminates the need for separate tooling or configuration maintenance across environments.

### 4. Interactive Mode Design

The interactive mode implements:

- Combined search and navigation (type to filter, arrow keys to navigate)
- Multi-selection with parallel execution
- Visual feedback through color-coding and status indicators
- Automatic logging with timestamps
- Post-execution log browsing

---

## Core Features

### 1. Generic Action System

**Description:**
Action names are user-defined in the configuration file rather than prescribed by the tool.

**Examples:**
```ini
[MyApp]
build=make all
build_host=make host
build_target=make target
test_unit=npm test
test_integration=npm run test:integration
deploy_staging=./deploy.sh staging
deploy_production=./deploy.sh production
lint=eslint .
format=prettier --write .
custom_action=./my_script.sh
```

**Use Cases:**
- Embedded firmware with separate host/target builds
- Multi-stage deployments
- Different test suites
- Code quality tools
- Custom workflows unique to your project

### 2. Interactive Unified Menu

**Description:**
A keyboard-driven interface for selecting and executing commands.

**Features:**
- **Fuzzy Search**: Type any characters to filter commands instantly
- **Arrow Navigation**: Use ↑/↓ to navigate, PgUp/PgDn to jump
- **Multi-Selection**: Space bar to toggle selection, + to select all visible, - to deselect all
- **Instant Execution**: Enter to run current command or all selected commands
- **Details View**: View full configuration for any application
- **Log Viewer**: Browse execution logs after batch runs

**User Workflow:**
1. Launch Shell-Bun in interactive mode
2. Type characters to filter (e.g., "build" shows all build actions)
3. Select one or multiple commands
4. Press Enter to execute
5. View logs if needed

### 3. Parallel Execution

**Description:**
Multiple commands execute simultaneously when selected, and a summary is presented at the end of which commands were successful and which were not.

**Behavior:**
- Interactive mode with multiple selections: Commands execute in parallel
- CI mode: All matched commands execute in parallel
- Each command logs to its own timestamped file
- Execution summary shows success/failure counts
- Failed commands are highlighted in output

### 4. CI/CD Mode

**Description:**
A non-interactive interface for automated pipeline execution.

**Features:**
- Pattern matching for applications and actions
- Parallel execution by default
- Proper exit codes (0=success, 1=failure)
- Structured output suitable for CI logs
- No user interaction required
- Clear error reporting

**Usage Examples:**
```
# Run specific action
./shell-bun.sh --ci MyWebApp build

# Run multiple actions
./shell-bun.sh --ci APIServer "test_unit,deploy_staging"

# Pattern matching
./shell-bun.sh --ci "API*" "test*"      # All apps starting with "API", all test actions
./shell-bun.sh --ci "*Web*" build       # All apps containing "Web", build action
./shell-bun.sh --ci "*" all             # All apps, all actions
```

### 5. Working Directory Management

**Description:**
Applications can specify a working directory for command execution.

**Configuration:**
```ini
[MyApp]
working_dir=/absolute/path/to/app
# or
working_dir=relative/path/from/executable
# or
working_dir=~/path/with/tilde
build=make all
```

**Behavior:**
- Commands execute in the specified directory
- Path resolution handles absolute, relative, and tilde paths
- If no working_dir specified, commands run from executable location
- Container mode: working_dir is relative to container's starting point

### 6. Container Integration

**Description:**
Commands can optionally execute inside containers.

**Configuration:**
```ini
# Global container command
container=docker run --rm ubuntu

[MyApp]
build=make all  # Executed inside container
```

**Behavior:**
- Container execution is transparent to the command definition
- Supports any container runtime (Docker, Podman, etc.)
- Working directories are handled inside containers
- Environment setup handled within container

**Application:**
- Build environment consistency
- Testing on different distributions
- Process isolation
- Build reproducibility

### 7. Logging

**Description:**
All command execution is logged with timestamps.

**Features:**
- Timestamped log files: `YYYYMMDD_HHMMSS_App_Action.log`
- Global log directory with per-app overrides
- Path resolution (absolute, relative, tilde)
- Automatic directory creation
- Post-execution log viewer
- Failed operations highlighted

**Configuration:**
```ini
# Global log directory
log_dir=logs

[App1]
build=make all
# logs to: logs/20250131_143025_App1_build.log

[App2]
log_dir=app2_logs  # Override for this app
build=make all
# logs to: app2_logs/20250131_143025_App2_build.log
```

### 8. Pattern Matching

**Description:**
Fuzzy matching in CI mode for selecting applications and actions.

**Pattern Types:**

1. **Exact Match**: `MyWebApp` matches only "MyWebApp"
2. **Wildcard Patterns**: 
   - `*Web*` matches any app containing "Web"
   - `API*` matches apps starting with "API"
   - `*Server` matches apps ending with "Server"
3. **Substring Match**: `web` matches "MyWebApp", "WebServer", "Backend_Web"
4. **Multiple Patterns**: `MyWebApp,API*,mobile` matches all three patterns

**Use Cases:**
```
# Test all microservices
./shell-bun.sh --ci "*Service" test_unit

# Build all frontend apps
./shell-bun.sh --ci "*Frontend*,*UI*" build

# Deploy all staging environments
./shell-bun.sh --ci "*" deploy_staging
```

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Shell-Bun                           │
│                      (shell-bun.sh)                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌────────────────┐    ┌──────────────────┐           │
│  │ Config Parser  │───▶│   Data Storage   │           │
│  │                │    │  (Associative    │           │
│  │ - INI parsing  │    │   Arrays)        │           │
│  │ - Validation   │    └──────────────────┘           │
│  └────────────────┘                                    │
│           │                                             │
│           ▼                                             │
│  ┌────────────────────────────────────────┐           │
│  │         Mode Selection                 │           │
│  │                                        │           │
│  │  CI Mode          Interactive Mode     │           │
│  │     │                    │             │           │
│  └─────┼────────────────────┼─────────────┘           │
│        │                    │                          │
│        ▼                    ▼                          │
│  ┌─────────────┐    ┌──────────────┐                 │
│  │  Pattern    │    │  Unified     │                 │
│  │  Matcher    │    │  Menu UI     │                 │
│  │             │    │              │                 │
│  │ - Fuzzy     │    │ - Navigation │                 │
│  │ - Wildcards │    │ - Filtering  │                 │
│  │ - Substring │    │ - Selection  │                 │
│  └──────┬──────┘    └──────┬───────┘                 │
│         │                  │                          │
│         └────────┬─────────┘                          │
│                  ▼                                     │
│         ┌────────────────┐                            │
│         │   Executor     │                            │
│         │                │                            │
│         │ - Sequential   │                            │
│         │ - Parallel     │                            │
│         │ - Logging      │                            │
│         │ - Container    │                            │
│         └────────┬───────┘                            │
│                  │                                     │
│                  ▼                                     │
│         ┌─────────────────┐                           │
│         │  Log Manager    │                           │
│         │  & Log Viewer   │                           │
│         └─────────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

### Data Structures

The implementation uses key-value data structures for efficient data management:

1. **Applications**: List of application names
2. **Actions**: Key-value store for commands (key: "app:action", value: "command")
3. **Action Lists**: Actions available per application
4. **Working Directories**: Working directory per application
5. **Log Directories**: Log directory per application
6. **Selections**: Currently selected items in interactive mode
7. **Execution Results**: Tracking for post-execution log viewing

### Control Flow

#### Interactive Mode
```
Start
  ↓
Parse Config
  ↓
Show Unified Menu ←──────┐
  ↓                       │
User Input                │
  │                       │
  ├─ Type → Filter items ─┘
  ├─ Arrow keys → Navigate ─┘
  ├─ Space → Toggle selection ─┘
  ├─ Enter → Execute
  │           ↓
  │    ┌─────────────┐
  │    │  Single or  │
  │    │  Multiple?  │
  │    └──┬──────┬───┘
  │       │      │
  │    Single  Multiple
  │       │      │
  │       │      ├─→ Parallel Execution
  │       │      │   ↓
  │       │      │   Summary & Log Viewer
  │       │      │   ↓
  │       │      │   Back to Menu ─────┘
  │       │
  │       └─→ Execute Single
  │           ↓
  │           Show Output
  │           ↓
  │           Back to Menu ─────────┘
  │
  └─ ESC → Exit
```

#### CI Mode
```
Start
  ↓
Parse Config
  ↓
Match Apps (Pattern)
  ↓
Match Actions (Pattern)
  ↓
Spawn All Commands in Parallel
  ↓
Wait for All Completions
  ↓
Collect Results
  ↓
Print Summary
  ↓
Exit (0=success, 1=failure)
```

---

## Configuration System

### INI-Style Format

Shell-Bun uses a simple, readable INI-style configuration:

```ini
# Comments start with #

# Global settings (before any app sections)
log_dir=logs
container=docker run --rm ubuntu

# Application sections
[ApplicationName]
action_name=command to execute
another_action=another command
working_dir=/path/to/working/directory
log_dir=/path/to/log/directory  # Optional per-app override

[AnotherApp]
# ... more apps
```

### Configuration Parsing

**Algorithm:**
1. Read file line by line
2. Skip empty lines and comments
3. Section headers (`[AppName]`) create new applications
4. Key-value pairs (`key=value`) are processed:
   - Before any section: global settings (`log_dir`, `container`)
   - Within a section: actions or app-specific settings (`working_dir`, `log_dir`)
5. Actions are stored with composite keys: `"app:action"`

**Validation:**
- Configuration file must exist
- At least one application must be defined
- Invalid configurations produce clear error messages

### Special Keys

1. **`log_dir`** (global or per-app): Log directory path
2. **`container`** (global): Container command prefix
3. **`working_dir`** (per-app): Command execution directory
4. **Everything else**: User-defined actions

### Path Resolution

Paths in configuration support:
- **Absolute paths**: `/usr/local/myapp`
- **Relative paths**: `../myapp`, `build/output` (relative to executable location)
- **Tilde expansion**: `~/myapp` (expands to user's home directory)

---

## Execution Modes

### Interactive Mode (Default)

**Invocation:**
```
./shell-bun.sh                    # Default config
./shell-bun.sh my-config.cfg      # Custom config
./shell-bun.sh --debug            # With debug logging
```

**Features:**
- Rich terminal UI with colors and formatting
- Keyboard-driven navigation
- Real-time filtering
- Multi-selection capability
- Immediate visual feedback
- Post-execution log browsing

**Requirements:**
- Interactive terminal (TTY)
- Terminal with ANSI color support

### CI/CD Mode (Non-Interactive)

**Invocation:**
```
./shell-bun.sh --ci APP_PATTERN ACTION_PATTERN [config]
```

**Features:**
- No user interaction
- Pattern-based selection
- Parallel execution
- Proper exit codes
- Structured output
- Error aggregation

**Exit Codes:**
- `0`: All operations succeeded
- `1`: One or more operations failed or invalid arguments

**Output Format:**
```
Loading configuration from: shell-bun.cfg
Found 3 applications
Applications: MyWebApp APIServer EmbeddedFirmware

Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)
App pattern: 'API*'
Action pattern: 'test*'
Matched apps: APIServer
Config: shell-bun.cfg
========================================

Running 2 actions in parallel...
========================================
🚀 Starting: APIServer - test_unit: ...
🚀 Starting: APIServer - test_integration: ...
✅ Completed: APIServer - test_unit
✅ Completed: APIServer - test_integration

========================================
CI Execution Summary (Parallel):
Commands executed: 2
✅ Successful operations: 2
🎉 All operations completed successfully
```

### Debug Mode

**Invocation:**
```
./shell-bun.sh --debug [config]
```

**Features:**
- Creates `debug.log` in the working directory
- Logs key events, decisions, and state changes
- Useful for troubleshooting

**Debug Output Includes:**
- Key press events (ASCII codes, sequences)
- Filter changes
- Selection state
- Menu navigation
- Command execution

---

## User Interface

### Interactive Menu Components

#### Title Box
```
╔══════════════════════════════════════════════════════════════════════════════╗
║      Shell-Bun by Fredrik Reveny (https://github.com/Chetic/shell-bun/)     ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

#### Help Text
```
Navigation: ↑/↓ arrows | PgUp/PgDn: page | Type: filter | Space: select | Enter: execute | ESC: quit
Shortcuts: '+' select visible | '-' deselect visible | Delete: clear filter | Enter: run current or selected
```

#### Filter Status
```
Filter: build
Selected: 3 items
```

#### Menu Items
```
  MyWebApp - build
► MyWebApp - test                [✓]
  MyWebApp - deploy
  ... 2 more item(s) below ...
```

**Visual Indicators:**
- `►` : Current selection (highlighted)
- `[✓]`: Selected for batch execution
- Colors: Commands in white/cyan, details in yellow/purple, selected in green

#### Scroll Indicators
```
  ... 5 more item(s) above ...
[menu items]
  ... 8 more item(s) below ...
```

### Log Viewer

After parallel execution, Shell-Bun automatically presents a log viewer:

```
📋 Select a log file to view (q to quit):

► SUCCESS: MyWebApp - build (/path/to/log/20250131_143025_MyWebApp_build.log)
  SUCCESS: APIServer - test_unit (/path/to/log/20250131_143026_APIServer_test_unit.log)
  FAILED: EmbeddedFirmware - flash (/path/to/log/20250131_143027_EmbeddedFirmware_flash.log)

Use ↑/↓ arrows, PgUp/PgDn, Enter to view, q to menu, ESC to exit
```

**Features:**
- Failed logs shown first (red)
- Successful logs shown after (green)
- Press Enter to view log in `less`
- `q` to return to main menu
- ESC to exit Shell-Bun

### Keyboard Controls

| Key | Action |
|-----|--------|
| **Navigation** | |
| ↑/↓ | Move selection up/down |
| PgUp/PgDn | Jump 10 items up/down |
| Home/End | (Future: Jump to start/end) |
| **Filtering** | |
| Any letter/number | Add to filter |
| Backspace | Remove last character |
| Ctrl+Backspace | Clear entire filter |
| Delete | Clear entire filter |
| **Selection** | |
| Space | Toggle selection of current item |
| + | Select all visible items |
| - | Deselect all visible items |
| **Execution** | |
| Enter | Execute current OR all selected |
| **Other** | |
| ESC | Quit application |

### Color Scheme

- **Blue/Cyan**: Headers, navigation hints, current selection
- **Yellow**: Filters, "Show Details" items, warnings
- **Green**: Selected items, successful operations
- **Red**: Failed operations, errors
- **Purple**: "Show Details" when highlighted
- **Dim**: Non-critical information, hints

---

## Use Cases

### 1. Multi-Application Development Environment

**Scenario:** You're developing a system with a web frontend, API backend, and embedded firmware.

**Configuration:**
```ini
[Frontend]
install=npm install
build=npm run build
dev=npm run dev
test=npm test
lint=npm run lint
format=npm run format

[Backend]
install=pip install -r requirements.txt
build=python setup.py build
dev=python app.py --dev
test=pytest
migrate=python manage.py migrate
seed=python manage.py seed

[Firmware]
build_host=make host
build_target=make target
flash=make flash
debug=make debug
clean=make clean
```

**Workflows:**
- **Daily development**: Use interactive mode to quickly run dev servers, tests, or specific builds
- **CI/CD**: `./shell-bun.sh --ci "*" test` to test everything
- **Deployment**: `./shell-bun.sh --ci "Backend,Frontend" build` to build production artifacts

### 2. Docker-Isolated Build Environment

**Scenario:** Ensure consistent builds across team members and CI by running everything in containers.

**Configuration:**
```ini
container=docker run --rm -v $(pwd):/workspace -w /workspace node:18

[WebApp]
install=npm install
build=npm run build
test=npm test
```

**Behavior:**
Every command runs inside a Node.js container:
```
docker run --rm -v $(pwd):/workspace -w /workspace node:18 <command-execution>
```

**Characteristics:**
- Environment consistency across machines
- Specified Node.js version
- Dependency isolation
- Version changes through container image updates

### 3. Complex Embedded Firmware Development

**Scenario:** Building firmware for multiple targets, flashing to devices, running host tests.

**Configuration:**
```ini
[STM32Firmware]
working_dir=firmware/stm32
build_debug=arm-none-eabi-gcc -DDEBUG ...
build_release=arm-none-eabi-gcc -O2 ...
flash_debug=openocd -f board/stm32f4discovery.cfg -c "program build/debug.elf verify reset exit"
flash_release=openocd -f board/stm32f4discovery.cfg -c "program build/release.elf verify reset exit"
test_host=gcc -DHOST_TEST ... && ./test_runner
clean=rm -rf build/*

[ESP32Firmware]
working_dir=firmware/esp32
build=idf.py build
flash=idf.py flash
monitor=idf.py monitor
menuconfig=idf.py menuconfig
clean=idf.py fullclean
```

**Workflows:**
- **Build all variants**: Select multiple build actions and run in parallel
- **Quick flash**: Filter "flash", select, execute
- **CI**: `./shell-bun.sh --ci "*Firmware" build_release` to build all release versions

### 4. Microservices Development

**Scenario:** 10 microservices, each with build, test, deploy actions.

**Configuration:**
```ini
[UserService]
working_dir=services/user
build=docker build -t user-service .
test=go test ./...
deploy_dev=kubectl apply -f k8s/dev/
deploy_prod=kubectl apply -f k8s/prod/

[PaymentService]
working_dir=services/payment
build=docker build -t payment-service .
test=go test ./...
deploy_dev=kubectl apply -f k8s/dev/
deploy_prod=kubectl apply -f k8s/prod/

# ... 8 more services
```

**Workflows:**
- **Test everything**: `./shell-bun.sh --ci "*Service" test` in CI
- **Deploy to dev**: `./shell-bun.sh --ci "*Service" deploy_dev`
- **Update one service**: Filter by name, select actions, execute

### 5. CI/CD Pipeline Integration

**Scenario:** GitHub Actions, GitLab CI, Jenkins, etc.

**GitHub Actions Example:**
```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Test all applications
        run: ./shell-bun.sh --ci "*" test
      
      - name: Build production
        run: ./shell-bun.sh --ci "*" build
```

**Characteristics:**
- Shared configuration for local development and CI
- Configuration-based action management
- Parallel execution
- Structured error reporting

### 6. Code Quality Toolchain

**Scenario:** Multiple code quality tools across different languages.

**Configuration:**
```ini
[CodeQuality]
lint_js=eslint .
lint_py=flake8 .
lint_go=golint ./...
format_js=prettier --write .
format_py=black .
type_check=mypy .
security_scan=bandit -r .
test_coverage=pytest --cov
```

**Workflows:**
- **Pre-commit**: Run linters interactively
- **CI**: `./shell-bun.sh --ci CodeQuality "lint_*"` to run all linters
- **Format code**: Select format actions, execute in parallel

---

## Technical Implementation

### Parallel Execution

**Approach:**
1. Spawn each command as a separate process
2. Track process identifiers
3. Each process redirects output to its log file
4. Wait for all processes to complete
5. Collect exit codes
6. Generate execution summary

**Characteristics:**
- Parallel execution through OS process scheduling
- Process isolation (failures are independent)
- Concurrent resource usage

**Limitations:**
- No inter-process communication mechanism
- No dependency-based execution ordering
- Potential resource contention with many concurrent processes

### Container Execution

**How It Works:**
When `container` is set globally, every command is wrapped:

```
# User's command in config
build=make all

# Actual execution
docker run --rm ubuntu <shell> "make all"
```

**With working_dir:**
```
# Config
working_dir=/app
build=make all

# Execution
docker run --rm ubuntu <shell> "cd /app && make all"
```

**Execution Details:**
- Commands execute within the container environment
- Environment variables and PATH are properly initialized
- Working directory changes are handled within the container

### Log File Management

**Naming Convention:**
```
YYYYMMDD_HHMMSS_AppName_ActionName.log
```

**Example:**
```
20250131_143025_MyWebApp_build.log
```

**Directory Resolution:**
1. Check for app-specific `log_dir`
2. Fall back to global `log_dir`
3. Fall back to `./logs` relative to executable
4. Create directory if it doesn't exist
5. Fall back to executable directory if creation fails

**Log File Content:**
- Standard output and standard error are both captured
- For single execution, output is shown to user and logged simultaneously

### Pattern Matching Algorithm

**Three Matching Strategies:**

1. **Exact Match:**
   - Pattern must exactly match the item name

2. **Wildcard Match:**
   - Patterns containing `*` use glob-style matching
   - `*` matches any sequence of characters

3. **Substring Match (Case-Insensitive):**
   - If not an exact or wildcard match, perform case-insensitive substring search

**Comma-Separated Patterns:**
- Multiple patterns separated by commas are evaluated independently
- Results are deduplicated

### Error Handling

**Configuration Errors:**
- Missing config file: Clear error, usage instructions
- No applications defined: Error with explanation
- Invalid syntax: Ignored (lines that don't match expected format)

**Execution Errors:**
- Missing command: Error logged, execution skipped
- Invalid working directory: Error logged, execution skipped
- Command failure: Exit code captured, marked as failed, summary updated

**Exit Codes:**
- Interactive mode: Always exits 0 (unless ESC pressed)
- CI mode: 0 if all commands succeed, 1 if any fail

---

## Testing and Quality

### Test Suite

The project includes an automated test suite.

**Test Coverage:**
- Configuration parsing
- CI mode execution
- Pattern matching (exact, wildcard, substring)
- Command-line argument handling
- Working directory resolution
- Log directory configuration
- Container command integration
- Error conditions and edge cases

**Test Areas:**
1. Configuration file parsing
2. Non-interactive CI execution
3. Fuzzy matching algorithms
4. CLI argument parsing
5. Working directory handling
6. Log directory configuration
7. Container working directory handling

### Continuous Integration

**Platforms Tested:**
- Ubuntu
- macOS
- Windows

**CI Pipeline:**
1. Syntax validation
2. Static analysis
3. Test suite execution
4. Platform matrix testing

### Code Quality

**Practices:**
- Error handling for undefined variables and failures
- Proper variable handling
- Modular code organization
- Descriptive naming conventions
- Code documentation

---

## Future Enhancements

### Potential Features

1. **Dependency Management:**
   - Declare dependencies between actions
   - Automatic execution ordering
   - Example: Run `build` before `test`

2. **Action Groups:**
   - Group related actions
   - Example: `pre-commit` group runs lint + format + test_unit

3. **Environment Variables:**
   - Per-app environment variable configuration
   - Secret management integration

4. **Remote Execution:**
   - SSH to remote hosts
   - Distributed execution across multiple machines

5. **Action Aliases:**
   - Short aliases for common actions
   - Example: `b` for `build`, `t` for `test`

6. **Conditional Execution:**
   - Only run if files changed
   - Skip if previous action failed

7. **Hooks:**
   - Pre/post action hooks
   - Example: Notification on completion

8. **Plugin System:**
   - Extend functionality without modifying core
   - Custom actions, integrations

9. **Configuration Includes:**
   - Split large configs into multiple files
   - Shared configs across projects

10. **Interactive Configuration Builder:**
    - Wizard to generate configuration files
    - Templates for common setups

### Backward Compatibility

Any future enhancements will maintain backward compatibility:
- Existing configs will continue to work
- Core design principles remain unchanged

---

## Summary

Shell-Bun implements a task management system with a single-file distribution model and dual-mode operation. The design balances interactive usability with automation requirements.

The generic action system and configuration-based approach support various development workflows, from single-application projects to multi-language, multi-service systems.

**Implementation Characteristics:**
- Single file distribution
- User-defined action system
- Interactive and non-interactive execution modes
- No external dependencies required
- Configuration-driven behavior
- Comprehensive test coverage

---

**Document Version:** 1.0  
**Last Updated:** October 31, 2025  
**Author:** Fredrik Reveny  
**Repository:** https://github.com/Chetic/shell-bun/
