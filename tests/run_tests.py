#!/usr/bin/env python3

#
# Shell-Bun Test Runner
# Runs all pytest tests for shell_bun.py
#

import sys
import subprocess
from pathlib import Path

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    BOLD = '\033[1m'
    NC = '\033[0m'  # No Color


def print_color(color, message):
    """Print colored output."""
    print(f"{color}{message}{Colors.NC}")


def main():
    """Main test runner."""
    # Get script directory
    script_dir = Path(__file__).parent.absolute()
    project_root = script_dir.parent
    
    print_color(Colors.BLUE, "╔══════════════════════════════════════════════════════════╗")
    print_color(Colors.BLUE, "║              Shell-Bun Test Suite Runner                ║")
    print_color(Colors.BLUE, "╚══════════════════════════════════════════════════════════╝")
    print()
    
    # Check for pytest
    try:
        import pytest
        pytest_version = pytest.__version__
        print_color(Colors.GREEN, f"✓ pytest found: {pytest_version}")
    except ImportError:
        print_color(Colors.YELLOW, "pytest is not installed. Installing pytest...")
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", "pytest"], check=True)
            import pytest
            print_color(Colors.GREEN, "✓ pytest installed successfully")
        except subprocess.CalledProcessError:
            print_color(Colors.RED, "Cannot install pytest automatically.")
            print("Please install pytest manually:")
            print("  pip install pytest")
            sys.exit(1)
    
    print()
    
    # Change to project root
    import os
    os.chdir(project_root)
    
    # Count test files
    test_files = list(script_dir.glob("test_*.py"))
    test_count = len(test_files)
    
    print_color(Colors.BLUE, f"Running {test_count} test suite(s)...")
    print()
    
    # Parse command line arguments
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    specific_test = None
    
    if "-t" in sys.argv or "--test" in sys.argv:
        idx = sys.argv.index("-t") if "-t" in sys.argv else sys.argv.index("--test")
        if idx + 1 < len(sys.argv):
            specific_test = sys.argv[idx + 1]
    
    if "-h" in sys.argv or "--help" in sys.argv:
        print("Usage: python run_tests.py [options]")
        print()
        print("Options:")
        print("  -v, --verbose       Show verbose output")
        print("  -t, --test NAME     Run specific test file (e.g., ci_mode)")
        print("  -h, --help          Show this help message")
        print()
        print("Examples:")
        print("  python run_tests.py                        # Run all tests")
        print("  python run_tests.py -v                     # Run all tests with verbose output")
        print("  python run_tests.py -t ci_mode             # Run only CI mode tests")
        sys.exit(0)
    
    # Build pytest command
    pytest_args = []
    if verbose:
        pytest_args.append("-v")
    else:
        pytest_args.append("-q")
    
    if specific_test:
        test_file = script_dir / f"test_{specific_test}.py"
        if not test_file.exists():
            print_color(Colors.RED, f"Test file not found: {test_file}")
            print("Available tests:")
            for file in test_files:
                name = file.stem.replace("test_", "")
                print(f"  {name}")
            sys.exit(1)
        pytest_args.append(str(test_file))
    else:
        pytest_args.append(str(script_dir))
    
    # Run tests
    try:
        result = subprocess.run([sys.executable, "-m", "pytest"] + pytest_args)
        test_result = result.returncode
    except KeyboardInterrupt:
        print_color(Colors.YELLOW, "\nTests interrupted by user")
        sys.exit(1)
    
    print()
    if test_result == 0:
        print_color(Colors.GREEN, "╔══════════════════════════════════════════════════════════╗")
        print_color(Colors.GREEN, "║              ✓ All tests passed!                         ║")
        print_color(Colors.GREEN, "╚══════════════════════════════════════════════════════════╝")
        sys.exit(0)
    else:
        print_color(Colors.RED, "╔══════════════════════════════════════════════════════════╗")
        print_color(Colors.RED, "║              ✗ Some tests failed                         ║")
        print_color(Colors.RED, "╚══════════════════════════════════════════════════════════╝")
        sys.exit(1)


if __name__ == "__main__":
    main()

