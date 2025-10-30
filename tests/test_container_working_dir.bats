#!/usr/bin/env bats

setup() {
    export TEST_DIR="$BATS_TEST_DIRNAME"
    export SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
    export TEST_CONFIG="$TEST_DIR/fixtures/container_working_dir.cfg"
}

@test "working_dir should work correctly with container command" {
    # Create a test config with container and working_dir
    # Simulate container by using bash subprocess that starts in / (like a container)
    cat > "$TEST_CONFIG" << 'EOF'
# Test config for container working_dir
# Simulate Docker by running bash in a clean environment starting from /
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=/tmp
build=pwd
EOF

    # Run the command
    run "$SCRIPT_DIR/shell-bun.sh" --ci TestApp build "$TEST_CONFIG"
    
    echo "Exit code: $status"
    echo "Output: $output"
    
    # Should succeed
    [ "$status" -eq 0 ]
    
    # Output should contain /tmp, not /
    [[ "$output" == *"/tmp"* ]]
    
    # Output should NOT be just the root directory
    [[ "$output" != *$'\n/\n'* ]]
}

@test "working_dir with container should cd inside container, not on host" {
    # Create a test config that tries to cd to a directory that exists on host but not in container
    # Simulate container by using bash subprocess that starts in / (like a container)
    cat > "$TEST_CONFIG" << 'EOF'
# Test config for container working_dir
# Simulate Docker by running bash in a clean environment starting from /
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=/nonexistent_dir
build=pwd
EOF

    # Run the command
    run "$SCRIPT_DIR/shell-bun.sh" --ci TestApp build "$TEST_CONFIG"
    
    echo "Exit code: $status"
    echo "Output: $output"
    
    # Should fail because /nonexistent_dir doesn't exist in container
    [ "$status" -ne 0 ]
}

@test "working_dir relative path should work inside container" {
    # Create a test config with relative working_dir
    # Simulated container starts in / so tmp is a valid relative path (like Ubuntu container)
    cat > "$TEST_CONFIG" << 'EOF'
# Test config for container working_dir with relative path
# Simulate Docker by running bash in a clean environment starting from /
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=tmp
build=pwd
EOF

    # Run the command
    run "$SCRIPT_DIR/shell-bun.sh" --ci TestApp build "$TEST_CONFIG"
    
    echo "Exit code: $status"
    echo "Output: $output"
    
    # Should succeed
    [ "$status" -eq 0 ]
    
    # Output should show /tmp (when cd'ing to 'tmp' from /)
    [[ "$output" == *"/tmp"* ]]
}

teardown() {
    # Clean up test config
    if [ -f "$TEST_CONFIG" ]; then
        rm "$TEST_CONFIG"
    fi
}

