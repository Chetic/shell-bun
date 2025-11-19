#!/usr/bin/env python3

"""Test working directory functionality."""

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


def run_shell_bun(args):
    """Run shell-bun with given arguments."""
    cmd = [sys.executable, str(SHELL_BUN)] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def test_command_executes_in_specified_absolute_working_directory():
    """Command executes in specified absolute working directory."""
    # Create test directory
    test_dir = Path("/tmp/test1")
    test_dir.mkdir(exist_ok=True)
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "App1", "test", str(TEST_FIXTURES / "working_dir.cfg")
        ])
        assert status == 0
        assert "/tmp/test1" in output
    finally:
        # Clean up
        if test_dir.exists():
            test_dir.rmdir()


def test_error_on_nonexistent_working_directory():
    """Error on non-existent working directory."""
    # Create config with non-existent directory
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""[TestApp]
working_dir=/nonexistent/directory
test=echo "Should not run"
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "test", config_file
        ])
        assert status == 1
        assert "Working directory" in output and "does not exist" in output
    finally:
        os.unlink(config_file)


def test_relative_working_directory_resolved_from_script_location():
    """Relative working directory resolved from script location."""
    # Create a relative directory from script location
    relative_path = SCRIPT_DIR / "relative_path"
    relative_path.mkdir(exist_ok=True)
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "App2", "test", str(TEST_FIXTURES / "working_dir.cfg")
        ])
        assert status == 0
        assert "relative_path" in output
    finally:
        # Clean up
        if relative_path.exists():
            relative_path.rmdir()


def test_tilde_expansion_in_working_directory():
    """Tilde expansion in working directory."""
    # Create config with tilde
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write(f"""[TestApp]
working_dir=~/
test=pwd
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "test", config_file
        ])
        assert status == 0
        assert os.path.expanduser("~/") in output or os.environ.get("HOME") in output
    finally:
        os.unlink(config_file)

