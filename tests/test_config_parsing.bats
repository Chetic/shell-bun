#!/usr/bin/env bats

# Test configuration parsing functionality

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

@test "Parse basic configuration file" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
}

@test "Parse configuration with multiple apps" {
    run bash "$SHELL_BUN" --ci TestApp2 deploy "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Deploying TestApp2" ]]
}

@test "Reject configuration with no apps" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/invalid.cfg"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No applications found" ]]
}

@test "Error on missing configuration file" {
    run bash "$SHELL_BUN" --ci TestApp1 build /nonexistent/config.cfg
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration file" ]] && [[ "$output" =~ "not found" ]]
}

@test "Parse global log_dir setting" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    # Script should load without error
}

@test "Parse container command setting" {
    # This will fail if docker is not available, but should at least parse correctly
    run bash "$SHELL_BUN" --ci ContainerApp hello "$TEST_FIXTURES/container.cfg"
    # Don't check status as docker may not be available
    [[ "$output" =~ "Container mode enabled" ]]
}

