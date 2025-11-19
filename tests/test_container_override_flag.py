#!/usr/bin/env python3

"""Test container override flag functionality."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# Get script directory
SCRIPT_DIR = Path(__file__).parent.parent.absolute()
SHELL_BUN = SCRIPT_DIR / "shell_bun.py"
TEST_FIXTURES = SCRIPT_DIR / "tests" / "fixtures"


def run_shell_bun(args, env=None):
    """Run shell-bun with given arguments."""
    cmd = [sys.executable, str(SHELL_BUN)] + args
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return result.returncode, result.stdout, result.stderr


def test_container_overrides_container_command_from_config():
    """--container overrides container command from config."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config to ensure --container CLI flag can override the configured container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--container", "env CONTAINER_SOURCE=cli", "--ci", "TestApp", "build", config_file
        ])
        assert status == 0
        assert "container source: cli" in output
    finally:
        os.unlink(config_file)


def test_container_accepts_empty_override_to_run_on_host():
    """--container accepts an empty override to run on the host."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Config uses a failing container command that should be bypassed by an empty override
container=/bin/false

[TestApp]
build=echo host-run
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--container", "", "--ci", "TestApp", "build", config_file
        ])
        assert status == 0
        assert "host-run" in output
    finally:
        os.unlink(config_file)


def test_configured_container_is_ignored_when_containerenv_exists():
    """Configured container is ignored when /run/.containerenv exists."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config to ensure the configured container command is ignored inside a container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
""")
        config_file = f.name
    
    # Create container env marker
    container_env_path = "/tmp/test_containerenv"
    try:
        with open(container_env_path, 'w') as f:
            f.write("")
        
        env = os.environ.copy()
        env["SHELL_BUN_CONTAINER_MARKER_FILE"] = container_env_path
        
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "build", config_file
        ], env=env)
        
        assert status == 0
        assert f"Detected {container_env_path}" in output
        assert "container source: none" in output
    finally:
        os.unlink(config_file)
        if os.path.exists(container_env_path):
            os.unlink(container_env_path)


def test_container_override_still_applies_when_containerenv_exists():
    """--container override still applies when /run/.containerenv exists."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config to ensure CLI override still wins inside a container
container=env CONTAINER_SOURCE=config

[TestApp]
build=echo "container source: ${CONTAINER_SOURCE:-none}"
""")
        config_file = f.name
    
    # Create container env marker
    container_env_path = "/tmp/test_containerenv"
    try:
        with open(container_env_path, 'w') as f:
            f.write("")
        
        env = os.environ.copy()
        env["SHELL_BUN_CONTAINER_MARKER_FILE"] = container_env_path
        
        status, output, _ = run_shell_bun([
            "--container", "env CONTAINER_SOURCE=cli", "--ci", "TestApp", "build", config_file
        ], env=env)
        
        assert status == 0
        assert "container source: cli" in output
        assert f"Detected {container_env_path}" not in output
    finally:
        os.unlink(config_file)
        if os.path.exists(container_env_path):
            os.unlink(container_env_path)

