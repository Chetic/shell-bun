#!/usr/bin/env bash

#
# Shell-Bun Test Runner
# Runs all BATS tests for shell-bun.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_color "$BLUE" "╔══════════════════════════════════════════════════════════╗"
print_color "$BLUE" "║              Shell-Bun Test Suite Runner                ║"
print_color "$BLUE" "╚══════════════════════════════════════════════════════════╝"
echo

# Check for BATS installation
if ! command -v bats &> /dev/null; then
    print_color "$YELLOW" "BATS is not installed. Installing BATS..."
    
    # Check if we have npm
    if command -v npm &> /dev/null; then
        print_color "$BLUE" "Installing BATS via npm..."
        npm install -g bats
    elif command -v brew &> /dev/null; then
        print_color "$BLUE" "Installing BATS via Homebrew..."
        brew install bats-core
    elif command -v apt-get &> /dev/null; then
        print_color "$BLUE" "Installing BATS via apt..."
        sudo apt-get update && sudo apt-get install -y bats
    else
        print_color "$RED" "Cannot install BATS automatically."
        echo "Please install BATS manually:"
        echo "  - macOS: brew install bats-core"
        echo "  - Ubuntu/Debian: sudo apt-get install bats"
        echo "  - npm: npm install -g bats"
        echo "  - Or from source: https://github.com/bats-core/bats-core"
        exit 1
    fi
fi

# Verify BATS installation
if ! command -v bats &> /dev/null; then
    print_color "$RED" "BATS installation failed. Please install manually."
    exit 1
fi

BATS_VERSION=$(bats --version 2>/dev/null || echo "unknown")
print_color "$GREEN" "✓ BATS found: $BATS_VERSION"
echo

# Check Bash version
BASH_MAJOR_VERSION="${BASH_VERSION%%.*}"
if [[ "$BASH_MAJOR_VERSION" -lt 4 ]]; then
    print_color "$RED" "Error: This test suite requires Bash 4.0 or higher."
    print_color "$RED" "Your Bash version: $BASH_VERSION"
    exit 1
fi
print_color "$GREEN" "✓ Bash version: $BASH_VERSION"
echo

# Change to project root
cd "$PROJECT_ROOT"

# Count test files
TEST_FILES=("$SCRIPT_DIR"/*.bats)
TEST_COUNT=${#TEST_FILES[@]}

print_color "$BLUE" "Running $TEST_COUNT test suite(s)..."
echo

# Parse command line arguments
VERBOSE=0
SPECIFIC_TEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -t|--test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose       Show verbose output"
            echo "  -t, --test NAME     Run specific test file (e.g., config_parsing)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                        # Run all tests"
            echo "  $0 -v                     # Run all tests with verbose output"
            echo "  $0 -t ci_mode             # Run only CI mode tests"
            exit 0
            ;;
        *)
            print_color "$RED" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run tests
if [[ -n "$SPECIFIC_TEST" ]]; then
    # Run specific test file
    TEST_FILE="$SCRIPT_DIR/test_${SPECIFIC_TEST}.bats"
    if [[ ! -f "$TEST_FILE" ]]; then
        print_color "$RED" "Test file not found: $TEST_FILE"
        echo "Available tests:"
        for file in "${TEST_FILES[@]}"; do
            basename "$file" | sed 's/test_//;s/.bats$//'
        done
        exit 1
    fi
    
    print_color "$BLUE" "Running: $(basename "$TEST_FILE")"
    if [[ $VERBOSE -eq 1 ]]; then
        bats --verbose-run "$TEST_FILE"
    else
        bats "$TEST_FILE"
    fi
    TEST_RESULT=$?
else
    # Run all tests
    if [[ $VERBOSE -eq 1 ]]; then
        bats --verbose-run "$SCRIPT_DIR"/*.bats
    else
        bats "$SCRIPT_DIR"/*.bats
    fi
    TEST_RESULT=$?
fi

echo
if [[ $TEST_RESULT -eq 0 ]]; then
    print_color "$GREEN" "╔══════════════════════════════════════════════════════════╗"
    print_color "$GREEN" "║              ✓ All tests passed!                         ║"
    print_color "$GREEN" "╚══════════════════════════════════════════════════════════╝"
    exit 0
else
    print_color "$RED" "╔══════════════════════════════════════════════════════════╗"
    print_color "$RED" "║              ✗ Some tests failed                         ║"
    print_color "$RED" "╚══════════════════════════════════════════════════════════╝"
    exit 1
fi

