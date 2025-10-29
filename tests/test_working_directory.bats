#!/usr/bin/env bats

# Test working directory functionality

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
    
    # Create test directories
    mkdir -p /tmp/test1
}

teardown() {
    # Clean up test directories
    rm -rf /tmp/test1
}

@test "Command executes in specified absolute working directory" {
    run bash "$SHELL_BUN" --ci App1 test "$TEST_FIXTURES/working_dir.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/tmp/test1" ]]
}

@test "Error on non-existent working directory" {
    # Modify config to use non-existent directory
    cat > /tmp/test_nonexistent.cfg << 'EOF'
[TestApp]
working_dir=/nonexistent/directory
test=echo "Should not run"
EOF
    
    run bash "$SHELL_BUN" --ci TestApp test /tmp/test_nonexistent.cfg
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Working directory" ]] && [[ "$output" =~ "does not exist" ]]
    
    rm -f /tmp/test_nonexistent.cfg
}

@test "Relative working directory resolved from script location" {
    # Create a relative directory from script location
    mkdir -p "$SCRIPT_DIR/relative_path"
    
    run bash "$SHELL_BUN" --ci App2 test "$TEST_FIXTURES/working_dir.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "relative_path" ]]
    
    rm -rf "$SCRIPT_DIR/relative_path"
}

@test "Tilde expansion in working directory" {
    # Create config with tilde
    cat > /tmp/test_tilde.cfg << 'EOF'
[TestApp]
working_dir=~/
test=pwd
EOF
    
    run bash "$SHELL_BUN" --ci TestApp test /tmp/test_tilde.cfg
    [ "$status" -eq 0 ]
    [[ "$output" =~ "$HOME" ]]
    
    rm -f /tmp/test_tilde.cfg
}

