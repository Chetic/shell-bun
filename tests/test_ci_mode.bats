#!/usr/bin/env bats

# Test CI mode (non-interactive) functionality

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

@test "CI mode: Execute single action" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
    # Single action should not show summary
    [[ ! "$output" =~ "All operations completed successfully" ]]
    [[ ! "$output" =~ "CI Execution Summary" ]]
}

@test "CI mode: Execute multiple actions with comma" {
    run bash "$SHELL_BUN" --ci TestApp1 build,test "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
    [[ "$output" =~ "Testing TestApp1" ]]
    # Multiple actions should show summary
    [[ "$output" =~ "CI Execution Summary" ]]
    [[ "$output" =~ "All operations completed successfully" ]]
}

@test "CI mode: Execute all actions" {
    run bash "$SHELL_BUN" --ci TestApp1 all "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
    [[ "$output" =~ "Testing TestApp1" ]]
    [[ "$output" =~ "Cleaning TestApp1" ]]
    # Multiple actions should show summary
    [[ "$output" =~ "CI Execution Summary" ]]
    [[ "$output" =~ "All operations completed successfully" ]]
}

@test "CI mode: Wildcard app pattern" {
    run bash "$SHELL_BUN" --ci "Test*" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
    [[ "$output" =~ "Building TestApp2" ]]
    # Multiple actions should show summary
    [[ "$output" =~ "CI Execution Summary" ]]
    [[ "$output" =~ "All operations completed successfully" ]]
}

@test "CI mode: Substring app pattern" {
    run bash "$SHELL_BUN" --ci "App1" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building TestApp1" ]]
    # Single action should not show summary
    [[ ! "$output" =~ "CI Execution Summary" ]]
}

@test "CI mode: Wildcard action pattern" {
    run bash "$SHELL_BUN" --ci TestApp1 "test*" "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Testing TestApp1" ]]
    # Single action should not show summary
    [[ ! "$output" =~ "CI Execution Summary" ]]
}

@test "CI mode: Error on non-existent app" {
    run bash "$SHELL_BUN" --ci NonExistentApp build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No applications found matching pattern" ]]
}

@test "CI mode: Error on non-existent action" {
    run bash "$SHELL_BUN" --ci TestApp1 nonexistent "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No actions found" ]]
}

@test "CI mode: Handle command failure" {
    run bash "$SHELL_BUN" --ci FailApp fail_command "$TEST_FIXTURES/error.cfg"
    [ "$status" -eq 1 ]
    # Single action failure should not show summary
    [[ ! "$output" =~ "Failed operations" ]]
    [[ ! "$output" =~ "CI Execution Summary" ]]
}

@test "CI mode: Parallel execution" {
    run bash "$SHELL_BUN" --ci "Test*" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ Running.*actions.*in.*parallel ]]
    # Multiple actions should show summary
    [[ "$output" =~ "CI Execution Summary" ]]
    [[ "$output" =~ "All operations completed successfully" ]]
}

@test "CI mode: Require app parameter" {
    run bash "$SHELL_BUN" --ci "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Application name required" ]]
}

@test "CI mode: Require action parameter" {
    run bash "$SHELL_BUN" --ci TestApp1 "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Action(s) required" ]]
}

