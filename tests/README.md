# Shell-Bun Test Suite

This directory contains a comprehensive test suite for Shell-Bun using the BATS (Bash Automated Testing System) framework.

## Quick Start

### Running All Tests

```bash
# From the project root
./tests/run_tests.sh

# Or from the tests directory
cd tests
./run_tests.sh
```

### Running Specific Tests

```bash
# Run only CI mode tests
./tests/run_tests.sh -t ci_mode

# Run only config parsing tests
./tests/run_tests.sh -t config_parsing

# Run with verbose output
./tests/run_tests.sh -v
```

## Prerequisites

### Required
- **Bash 4.0+**: The test suite requires Bash 4.0 or higher (same as Shell-Bun itself)
- **BATS**: Bash Automated Testing System

### Installing BATS

The test runner will attempt to install BATS automatically, but you can install it manually:

#### macOS
```bash
brew install bats-core
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install bats
```

#### Other Linux
```bash
# Using npm
npm install -g bats

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

## Test Structure

### Test Files

The test suite is organized into logical groups:

- **`test_config_parsing.bats`**: Tests for configuration file parsing
  - Basic configuration loading
  - Multi-app configurations
  - Error handling for invalid configs
  - Global settings (log_dir, container)

- **`test_ci_mode.bats`**: Tests for non-interactive CI mode
  - Single action execution
  - Multiple action execution
  - Pattern matching
  - Error handling
  - Parallel execution

- **`test_pattern_matching.bats`**: Tests for fuzzy pattern matching
  - Exact matches
  - Wildcard patterns (`*App*`, `Test*`, `*build`)
  - Case-insensitive substring matching
  - Multiple comma-separated patterns

- **`test_command_line.bats`**: Tests for command-line argument parsing
  - Version flags (`--version`, `-v`)
  - Help flags (`--help`, `-h`)
  - Unknown option handling
  - Debug mode

- **`test_working_directory.bats`**: Tests for working directory functionality
  - Absolute paths
  - Relative paths
  - Tilde expansion (`~`)
  - Error handling for non-existent directories

- **`test_log_directory.bats`**: Tests for log directory functionality
  - Global log_dir setting
  - App-specific log_dir override
  - Path resolution (absolute, relative, tilde)

### Test Fixtures

Test fixtures are located in `tests/fixtures/`:

- **`basic.cfg`**: Basic multi-app configuration
- **`container.cfg`**: Configuration with container command
- **`working_dir.cfg`**: Configuration with working directories
- **`invalid.cfg`**: Invalid configuration (no apps)
- **`error.cfg`**: Configuration with failing commands

## Test Runner Options

```bash
./tests/run_tests.sh [options]

Options:
  -v, --verbose       Show verbose output
  -t, --test NAME     Run specific test file (e.g., ci_mode)
  -h, --help          Show help message

Examples:
  ./tests/run_tests.sh                    # Run all tests
  ./tests/run_tests.sh -v                 # Run with verbose output
  ./tests/run_tests.sh -t pattern_matching  # Run specific test
```

## Writing New Tests

### Test File Template

```bash
#!/usr/bin/env bats

# Test description

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

teardown() {
    # Clean up any test artifacts
}

@test "Test description" {
    run bash "$SHELL_BUN" --ci TestApp build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "expected output" ]]
}
```

### BATS Assertions

```bash
# Exit code checks
[ "$status" -eq 0 ]       # Success
[ "$status" -eq 1 ]       # Failure

# Output checks
[[ "$output" =~ "pattern" ]]        # Contains pattern
[[ "$output" == "exact match" ]]    # Exact match
[[ -z "$output" ]]                  # Empty output
[[ -n "$output" ]]                  # Non-empty output

# File checks
[[ -f "$file" ]]          # File exists
[[ -d "$dir" ]]           # Directory exists
[[ -x "$script" ]]        # File is executable
```

## Continuous Integration

### GitHub Actions

Tests run automatically on:
- **Pull Requests**: All PRs to main/master/develop branches
- **Push to main/master**: After merge
- **Releases**: Before creating a release
- **Manual trigger**: Via workflow_dispatch

See `.github/workflows/test.yml` for the full CI configuration.

### Test Matrix

Tests run on multiple platforms and Bash versions:
- **Platforms**: Ubuntu (latest), macOS (latest)
- **Bash versions**: 4.4, 5.0, 5.1, 5.2

### CI Commands

```bash
# What CI runs
chmod +x tests/run_tests.sh
bash tests/run_tests.sh -v

# Additional CI checks
bash -n shell-bun.sh              # Syntax check
shellcheck shell-bun.sh           # Linting
```

## Debugging Failed Tests

### Enable Debug Mode

```bash
# Run shell-bun with debug logging
bash shell-bun.sh --debug --ci TestApp build tests/fixtures/basic.cfg

# Check debug log
cat debug.log
```

### Verbose BATS Output

```bash
# See detailed test output
./tests/run_tests.sh -v

# Run BATS directly with trace
bats --trace tests/test_ci_mode.bats
```

### Manual Test Execution

```bash
# Run the exact command from a test
SCRIPT_DIR="$(pwd)"
SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"

bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
```

## Test Coverage

The test suite covers:

✅ Configuration parsing and validation  
✅ CI mode execution (single and parallel)  
✅ Pattern matching (exact, wildcard, substring)  
✅ Working directory handling  
✅ Log directory configuration  
✅ Command-line argument parsing  
✅ Error handling and validation  
✅ Multiple app and action execution  
✅ Container command integration  
✅ Path resolution (absolute, relative, tilde)  

## Contributing Tests

When adding new features to Shell-Bun:

1. **Write tests first** (TDD approach recommended)
2. **Add test fixtures** if needed in `tests/fixtures/`
3. **Run locally** before submitting PR: `./tests/run_tests.sh -v`
4. **Ensure CI passes** - tests must pass on all platforms
5. **Update documentation** if adding new test categories

## Troubleshooting

### BATS Not Found

```bash
# Install BATS manually
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu/Debian
```

### Bash Version Too Old

```bash
# Check your Bash version
bash --version

# macOS: Update via Homebrew
brew install bash

# Ubuntu: Usually has Bash 5.x by default
```

### Permission Denied

```bash
# Make test runner executable
chmod +x tests/run_tests.sh
```

### Tests Fail Locally But Pass in CI

- Check Bash version differences
- Verify file paths (use absolute paths in tests)
- Check for environment-specific dependencies

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Shell-Bun Repository](https://github.com/Chetic/shell-bun/)
- [GitHub Actions Workflow](.github/workflows/test.yml)

## License

The test suite is part of Shell-Bun and uses the same license (BSD 3-Clause).

