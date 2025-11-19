#!/usr/bin/env python3

"""Test configuration parsing functionality."""

import os
import subprocess
import sys
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


def test_parse_basic_configuration_file():
    """Parse basic configuration file."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output


def test_parse_configuration_with_multiple_apps():
    """Parse configuration with multiple apps."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp2", "deploy", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Deploying TestApp2" in output


def test_reject_configuration_with_no_apps():
    """Reject configuration with no apps."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "invalid.cfg")
    ])
    assert status == 1
    assert "No applications found" in output


def test_error_on_missing_configuration_file():
    """Error on missing configuration file."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", "/nonexistent/config.cfg"
    ])
    assert status == 1
    assert "Configuration file" in output and "not found" in output


def test_parse_global_log_dir_setting():
    """Parse global log_dir setting."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    # Script should load without error


def test_parse_container_command_setting():
    """Parse container command setting."""
    status, output, _ = run_shell_bun([
        "--ci", "ContainerApp", "hello", str(TEST_FIXTURES / "container.cfg")
    ])
    # Don't check status as docker may not be available
    assert "Container mode enabled" in output

