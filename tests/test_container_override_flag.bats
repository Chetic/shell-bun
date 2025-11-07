#!/usr/bin/env bats

setup() {
    export TEST_DIR="$BATS_TEST_DIRNAME"
    export SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
    export TEST_CONFIG="$TEST_DIR/fixtures/container_override.cfg"
    export SHELL_BUN_CONTAINER_MARKER_FILE="$BATS_TEST_TMPDIR/containerenv"
    export CONTAINER_ENV_PATH="$SHELL_BUN_CONTAINER_MARKER_FILE"
}

create_container_env_marker() {
    : > "$CONTAINER_ENV_PATH"
}

restore_container_env_marker() {
    rm -f "$CONTAINER_ENV_PATH"
}

@test "--container overrides container command from config" {
    cat > "$TEST_CONFIG" <<'CONFIG'
# Test config to ensure --container CLI flag can override the configured container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
CONFIG

    run "$SCRIPT_DIR/shell-bun.sh" --container "env CONTAINER_SOURCE=cli" --ci TestApp build "$TEST_CONFIG"

    echo "Exit code: $status"
    echo "Output: $output"

    [ "$status" -eq 0 ]
    [[ "$output" == *"container source: cli"* ]]
}

@test "--container accepts an empty override to run on the host" {
    cat > "$TEST_CONFIG" <<'CONFIG'
# Config uses a failing container command that should be bypassed by an empty override
container=/bin/false

[TestApp]
build=echo host-run
CONFIG

    run "$SCRIPT_DIR/shell-bun.sh" --container "" --ci TestApp build "$TEST_CONFIG"

    echo "Exit code: $status"
    echo "Output: $output"

    [ "$status" -eq 0 ]
    [[ "$output" == *"host-run"* ]]
}

@test "configured container is ignored when /run/.containerenv exists" {
    cat > "$TEST_CONFIG" <<'CONFIG'
# Test config to ensure the configured container command is ignored inside a container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
CONFIG

    create_container_env_marker

    run "$SCRIPT_DIR/shell-bun.sh" --ci TestApp build "$TEST_CONFIG"

    echo "Exit code: $status"
    echo "Output: $output"

    restore_container_env_marker

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected $CONTAINER_ENV_PATH - ignoring configured container command"* ]]
    [[ "$output" == *"container source: none"* ]]
}

@test "--container override still applies when /run/.containerenv exists" {
    cat > "$TEST_CONFIG" <<'CONFIG'
# Test config to ensure CLI override still wins inside a container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
CONFIG

    create_container_env_marker

    run "$SCRIPT_DIR/shell-bun.sh" --container "env CONTAINER_SOURCE=cli" --ci TestApp build "$TEST_CONFIG"

    echo "Exit code: $status"
    echo "Output: $output"

    restore_container_env_marker

    [ "$status" -eq 0 ]
    [[ "$output" == *"container source: cli"* ]]
    [[ "$output" != *"Detected $CONTAINER_ENV_PATH - ignoring configured container command"* ]]
}

teardown() {
    if [ -f "$TEST_CONFIG" ]; then
        rm "$TEST_CONFIG"
    fi
    restore_container_env_marker
}
