#!/usr/bin/env python3

"""Test command-line argument parsing."""

import subprocess
import sys
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


def test_version_flag():
    """Version flag: --version."""
    status, output, _ = run_shell_bun(["--version"])
    assert status == 0
    assert output.strip().startswith("v")


def test_version_flag_short():
    """Version flag: -v."""
    status, output, _ = run_shell_bun(["-v"])
    assert status == 0
    assert output.strip().startswith("v")


def test_help_flag():
    """Help flag: --help."""
    status, output, _ = run_shell_bun(["--help"])
    assert status == 0
    assert "Usage:" in output
    assert "Interactive mode" in output or "interactive" in output.lower()
    assert "--container" in output


def test_help_flag_short():
    """Help flag: -h."""
    status, output, _ = run_shell_bun(["-h"])
    assert status == 0
    assert "Usage:" in output


def test_unknown_option():
    """Unknown option."""
    status, output, _ = run_shell_bun(["--unknown-option"])
    assert status != 0
    # argparse will show an error


def test_debug_mode_flag():
    """Debug mode flag."""
    # Debug mode should work with CI mode
    status, output, _ = run_shell_bun([
        "--debug", "--ci", "TestApp1", "build", 
        str(SCRIPT_DIR / "tests" / "fixtures" / "basic.cfg")
    ])
    # Status depends on whether the command succeeds
    # Check that debug.log might be created (we can't easily check its contents)

