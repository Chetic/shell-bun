#!/usr/bin/env python3

"""Test CI mode (non-interactive) functionality."""

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


def test_ci_mode_execute_single_action():
    """CI mode: Execute single action."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output
    # Single action should not show summary
    assert "All operations completed successfully" not in output
    assert "CI Execution Summary" not in output


def test_ci_mode_execute_multiple_actions_with_comma():
    """CI mode: Execute multiple actions with comma."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build,test", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output
    assert "Testing TestApp1" in output
    # Multiple actions should show summary
    assert "CI Execution Summary" in output
    assert "All operations completed successfully" in output


def test_ci_mode_execute_all_actions():
    """CI mode: Execute all actions."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "all", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output
    assert "Testing TestApp1" in output
    assert "Cleaning TestApp1" in output
    # Multiple actions should show summary
    assert "CI Execution Summary" in output
    assert "All operations completed successfully" in output


def test_ci_mode_wildcard_app_pattern():
    """CI mode: Wildcard app pattern."""
    status, output, _ = run_shell_bun([
        "--ci", "Test*", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output
    assert "Building TestApp2" in output
    # Multiple actions should show summary
    assert "CI Execution Summary" in output
    assert "All operations completed successfully" in output


def test_ci_mode_substring_app_pattern():
    """CI mode: Substring app pattern."""
    status, output, _ = run_shell_bun([
        "--ci", "App1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Building TestApp1" in output
    # Single action should not show summary
    assert "CI Execution Summary" not in output


def test_ci_mode_wildcard_action_pattern():
    """CI mode: Wildcard action pattern."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "test*", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Testing TestApp1" in output
    # Single action should not show summary
    assert "CI Execution Summary" not in output


def test_ci_mode_error_on_nonexistent_app():
    """CI mode: Error on non-existent app."""
    status, output, _ = run_shell_bun([
        "--ci", "NonExistentApp", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 1
    assert "No applications found matching pattern" in output


def test_ci_mode_error_on_nonexistent_action():
    """CI mode: Error on non-existent action."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "nonexistent", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 1
    assert "No actions found" in output


def test_ci_mode_handle_command_failure():
    """CI mode: Handle command failure."""
    status, output, _ = run_shell_bun([
        "--ci", "FailApp", "fail_command", str(TEST_FIXTURES / "error.cfg")
    ])
    assert status == 1
    # Single action failure should not show summary
    assert "Failed operations" not in output
    assert "CI Execution Summary" not in output


def test_ci_mode_parallel_execution():
    """CI mode: Parallel execution."""
    status, output, _ = run_shell_bun([
        "--ci", "Test*", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "Running" in output and "actions" in output and "parallel" in output
    # Multiple actions should show summary
    assert "CI Execution Summary" in output
    assert "All operations completed successfully" in output


def test_ci_mode_require_app_parameter():
    """CI mode: Require app parameter."""
    status, output, _ = run_shell_bun([
        "--ci", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status != 0
    assert "Application name required" in output or "error" in output.lower()


def test_ci_mode_require_action_parameter():
    """CI mode: Require action parameter."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status != 0
    assert "Action(s) required" in output or "error" in output.lower()

