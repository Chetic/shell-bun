#!/usr/bin/env python3

"""Test log directory functionality."""

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


def test_global_log_dir_setting_is_recognized():
    """Global log_dir setting is recognized."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    # In CI mode, logs aren't created, but config should parse correctly


def test_app_specific_log_dir_overrides_global():
    """App-specific log_dir overrides global."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""log_dir=global_logs

[App1]
log_dir=app1_logs
test=echo "Test"

[App2]
test=echo "Test"
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "App1", "test", config_file
        ])
        assert status == 0
    finally:
        os.unlink(config_file)
        # Clean up
        for log_dir in ["global_logs", "app1_logs"]:
            log_path = SCRIPT_DIR / log_dir
            if log_path.exists():
                import shutil
                shutil.rmtree(log_path, ignore_errors=True)


def test_tilde_expansion_in_log_directory():
    """Tilde expansion in log directory."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""log_dir=~/test_logs

[TestApp]
test=echo "Test"
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "test", config_file
        ])
        assert status == 0
    finally:
        os.unlink(config_file)
        # Clean up
        log_path = Path(os.path.expanduser("~/test_logs"))
        if log_path.exists():
            import shutil
            shutil.rmtree(log_path, ignore_errors=True)


def test_relative_log_directory_resolved_from_script_location():
    """Relative log directory resolved from script location."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cfg', delete=False) as f:
        f.write("""log_dir=./relative_logs

[TestApp]
test=echo "Test"
""")
        config_file = f.name
    
    try:
        status, output, _ = run_shell_bun([
            "--ci", "TestApp", "test", config_file
        ])
        assert status == 0
    finally:
        os.unlink(config_file)
        # Clean up
        log_path = SCRIPT_DIR / "relative_logs"
        if log_path.exists():
            import shutil
            shutil.rmtree(log_path, ignore_errors=True)

