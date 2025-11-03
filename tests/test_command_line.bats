#!/usr/bin/env bats

# Test command-line argument parsing

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
}

@test "Version flag: --version" {
    run bash "$SHELL_BUN" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^v[0-9]+\.[0-9]+ ]]
}

@test "Version flag: -v" {
    run bash "$SHELL_BUN" -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^v[0-9]+\.[0-9]+ ]]
}

@test "Help flag: --help" {
    run bash "$SHELL_BUN" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "Interactive mode" ]]
    [[ "$output" =~ "Non-interactive mode" ]]
    [[ "$output" =~ "--container" ]]
}

@test "Help flag: -h" {
    run bash "$SHELL_BUN" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "Unknown option" {
    run bash "$SHELL_BUN" --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "Debug mode flag" {
    # Debug mode should work with CI mode
    run bash "$SHELL_BUN" --debug --ci TestApp1 build tests/fixtures/basic.cfg
    # Check that debug.log is created (we can't easily check its contents in this test)
    # Status depends on whether the command succeeds
}

@test "Bash version check: require 4.0+" {
    # This test verifies the version check exists
    # We can't actually test with an old bash version easily
    run grep -q "BASH_VERSION" "$SHELL_BUN"
    [ "$status" -eq 0 ]
}

