#!/usr/bin/env python3

"""Test container working directory functionality."""

import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# Get script directory
SCRIPT_DIR = Path(__file__).parent.parent.absolute()
SHELL_BUN = SCRIPT_DIR / "shell_bun.py"


def run_shell_bun(args):
    """Run shell-bun with given arguments."""
    cmd = [sys.executable, str(SHELL_BUN)] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def test_working_dir_should_work_correctly_with_container_command():
    """working_dir should work correctly with container command."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config for container working_dir
# Simulate Docker by running bash in a clean environment starting from /
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=/tmp
build=pwd
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "build", config_file
        ])
        
        assert status == 0
        assert "/tmp" in output
        assert "\n/\n" not in output
    finally:
        import os
        os.unlink(config_file)


def test_working_dir_with_container_should_cd_inside_container_not_on_host():
    """working_dir with container should cd inside container, not on host."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config for container working_dir
# Simulate Docker by running bash in a clean environment starting from /
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=/nonexistent_dir
build=pwd
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "build", config_file
        ])
        
        # Should fail because /nonexistent_dir doesn't exist in container
        assert status != 0
    finally:
        import os
        os.unlink(config_file)


def test_working_dir_relative_path_should_work_inside_container():
    """working_dir relative path should work inside container."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""# Test config for container working_dir with relative path
# Simulated container starts in / so tmp is a valid relative path (like Ubuntu container)
container=bash -c 'cd / && exec "$@"' bash

[TestApp]
working_dir=tmp
build=pwd
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "build", config_file
        ])
        
        assert status == 0
        assert "/tmp" in output
    finally:
        import os
        os.unlink(config_file)

