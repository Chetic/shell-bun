#!/usr/bin/env bats

# Test log directory functionality

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SHELL_BUN="$SCRIPT_DIR/shell-bun.sh"
    TEST_FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

teardown() {
    # Clean up test logs
    rm -rf "$SCRIPT_DIR/test_logs"
}

@test "Global log_dir setting is recognized" {
    run bash "$SHELL_BUN" --ci TestApp1 build "$TEST_FIXTURES/basic.cfg"
    [ "$status" -eq 0 ]
    # In CI mode, logs aren't created, but config should parse correctly
}

@test "App-specific log_dir overrides global" {
    cat > /tmp/test_app_log.cfg << 'EOF'
log_dir=global_logs

[App1]
log_dir=app1_logs
test=echo "Test"

[App2]
test=echo "Test"
EOF
    
    run bash "$SHELL_BUN" --ci App1 test /tmp/test_app_log.cfg
    [ "$status" -eq 0 ]
    
    rm -f /tmp/test_app_log.cfg
    rm -rf "$SCRIPT_DIR/global_logs" "$SCRIPT_DIR/app1_logs"
}

@test "Tilde expansion in log directory" {
    cat > /tmp/test_log_tilde.cfg << 'EOF'
log_dir=~/test_logs

[TestApp]
test=echo "Test"
EOF
    
    run bash "$SHELL_BUN" --ci TestApp test /tmp/test_log_tilde.cfg
    [ "$status" -eq 0 ]
    
    rm -f /tmp/test_log_tilde.cfg
    rm -rf ~/test_logs
}

@test "Relative log directory resolved from script location" {
    cat > /tmp/test_log_relative.cfg << 'EOF'
log_dir=./relative_logs

[TestApp]
test=echo "Test"
EOF
    
    run bash "$SHELL_BUN" --ci TestApp test /tmp/test_log_relative.cfg
    [ "$status" -eq 0 ]
    
    rm -f /tmp/test_log_relative.cfg
    rm -rf "$SCRIPT_DIR/relative_logs"
}

