#!/usr/bin/env bats

setup() {
    export TEST_DIR="$BATS_TEST_DIRNAME"
    export SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
    export TEST_CONFIG="$TEST_DIR/fixtures/container_override.cfg"
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

teardown() {
    if [ -f "$TEST_CONFIG" ]; then
        rm "$TEST_CONFIG"
    fi
}
