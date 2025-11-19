#!/usr/bin/env python3

"""Test pattern matching functionality."""

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


def test_exact_app_name_match():
    """Exact app name match."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp1" in output


def test_wildcard_at_start():
    """Wildcard at start: *App1."""
    status, output, _ = run_shell_bun([
        "--ci", "*App1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp1" in output


def test_wildcard_at_end():
    """Wildcard at end: Test*."""
    status, output, _ = run_shell_bun([
        "--ci", "Test*", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp" in output


def test_wildcard_in_middle():
    """Wildcard in middle: *App*."""
    status, output, _ = run_shell_bun([
        "--ci", "*App*", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp1" in output
    assert "TestApp2" in output


def test_case_insensitive_substring_match():
    """Case-insensitive substring match."""
    status, output, _ = run_shell_bun([
        "--ci", "testapp", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp" in output


def test_multiple_patterns_with_comma():
    """Multiple patterns with comma: TestApp1,TestApp2."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1,TestApp2", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "TestApp1" in output
    assert "TestApp2" in output


def test_exact_action_name_match():
    """Exact action name match."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "build" in output.lower()


def test_action_wildcard():
    """Action wildcard: test*."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "test*", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "test" in output.lower()


def test_multiple_actions():
    """Multiple actions: build,test."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "build,test", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "build" in output.lower()
    assert "test" in output.lower()


def test_all_actions_pattern():
    """All actions pattern."""
    status, output, _ = run_shell_bun([
        "--ci", "TestApp1", "all", str(TEST_FIXTURES / "basic.cfg")
    ])
    assert status == 0
    assert "build" in output.lower()
    assert "test" in output.lower()
    assert "clean" in output.lower()

