#!/usr/bin/env bats

# Test pattern matching functionality

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

@test "Exact app name match" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp1" ]]
}

@test "Wildcard at start: *App1" {
    run bash "$SHELL_BUN" --ci "*App1" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp1" ]]
}

@test "Wildcard at end: Test*" {
    run bash "$SHELL_BUN" --ci "Test*" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp" ]]
}

@test "Wildcard in middle: *App*" {
    run bash "$SHELL_BUN" --ci "*App*" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp1" ]]
    [[ "$output" =~ "TestApp2" ]]
}

@test "Case-insensitive substring match" {
    run bash "$SHELL_BUN" --ci "testapp" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp" ]]
}

@test "Multiple patterns with comma: TestApp1,TestApp2" {
    run bash "$SHELL_BUN" --ci "TestApp1,TestApp2" build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TestApp1" ]]
    [[ "$output" =~ "TestApp2" ]]
}

@test "Exact action name match" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "build" ]]
}

@test "Action wildcard: test*" {
    run bash "$SHELL_BUN" --ci TestApp1 "test*" "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test" ]]
}

@test "Multiple actions: build,test" {
    run bash "$SHELL_BUN" --ci TestApp1 "build,test" "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "build" ]]
    [[ "$output" =~ "test" ]]
}

@test "All actions pattern" {
    run bash "$SHELL_BUN" --ci TestApp1 all "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "build" ]]
    [[ "$output" =~ "test" ]]
    [[ "$output" =~ "clean" ]]
}

