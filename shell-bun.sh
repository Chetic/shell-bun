#!/bin/bash

#
# Shell-Bun - Interactive build environment script
# Copyright (c) 2025, Fredrik Reveny
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Shell-Bun - Interactive build environment script
# Usage: ./shell-bun.sh [config-file]
# Usage: ./shell-bun.sh --debug [config-file]

# Check if we're running with bash 4.0+ (required for associative arrays)
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0 or higher for associative array support."
    echo "Your Bash version: $BASH_VERSION"
    exit 1
fi

set -uo pipefail

# Debug mode and CI mode
DEBUG_MODE=0
CI_MODE=0
CI_APP=""
CI_ACTIONS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=1
            shift
            ;;
        --ci)
            CI_MODE=1
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                CI_APP="$1"
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                    CI_ACTIONS="$1"
                    shift
                fi
            fi
            ;;
        --help|-h)
            echo "Shell-Bun - Interactive build environment script"
            echo ""
            echo "Usage:"
            echo "  $0 [options] [config-file]"
            echo ""
            echo "Interactive mode (default):"
            echo "  $0                          # Use default config (shell-bun.cfg)"
            echo "  $0 my-config.txt           # Use custom config file"
            echo "  $0 --debug                 # Enable debug logging"
            echo ""
            echo "Non-interactive mode (CI/CD):"
            echo "  $0 --ci APP ACTION         # Run specific action for app"
            echo "  $0 --ci APP ACTION1,ACTION2 # Run multiple actions"
            echo "  $0 --ci APP all            # Run all available build actions for app"
            echo ""
            echo "Available actions: build_host, build_target, run_host, clean"
            echo ""
            echo "Examples:"
            echo "  $0 --ci MyWebApp build_host"
            echo "  $0 --ci APIServer build_host,run_host"
            echo "  $0 --ci Frontend all"
            echo "  $0 --ci --debug MyApp build_host my-config.txt"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            CONFIG_FILE="$1"
            shift
            ;;
    esac
done

# Set default config file if not specified
CONFIG_FILE="${CONFIG_FILE:-shell-bun.cfg}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Global variables
declare -a APPS=()
declare -A APP_BUILD_HOST=()
declare -A APP_BUILD_TARGET=()
declare -A APP_RUN_HOST=()
declare -A APP_CLEAN=()
declare -A APP_WORKING_DIR=()
declare -a SELECTED_ITEMS=()

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Debug logging function
debug_log() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        echo "[DEBUG] $1" >> debug.log
    fi
}

# Function to log execution status
log_execution() {
    local app="$1"
    local action="$2"
    local status="$3" # start, success, error
    
    case "$status" in
        "start")
            print_color "$CYAN" "🚀 Starting: $app - $action"
            ;;
        "success")
            print_color "$GREEN" "✅ Completed: $app - $action"
            ;;
        "error")
            print_color "$RED" "❌ Failed: $app - $action"
            ;;
    esac
}

# Function to parse configuration file
parse_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color "$RED" "Error: Configuration file '$CONFIG_FILE' not found!"
        echo "Please create a configuration file or specify a different one."
        echo "Usage: $0 [config-file]"
        exit 1
    fi

    local current_app=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            # New application section
            current_app="${BASH_REMATCH[1]}"
            APPS+=("$current_app")
        elif [[ -n "$current_app" && "$line" =~ ^([^=]+)=(.*)$ ]]; then
            # Configuration directive
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            case "$key" in
                "build_host")
                    APP_BUILD_HOST["$current_app"]="$value"
                    ;;
                "build_target")
                    APP_BUILD_TARGET["$current_app"]="$value"
                    ;;
                "run_host")
                    APP_RUN_HOST["$current_app"]="$value"
                    ;;
                "clean")
                    APP_CLEAN["$current_app"]="$value"
                    ;;
                "working_dir")
                    APP_WORKING_DIR["$current_app"]="$value"
                    ;;
                *)
                    print_color "$YELLOW" "Warning: Unknown directive '$key' for app '$current_app'"
                    ;;
            esac
        fi
    done < "$CONFIG_FILE"
    
    if [[ ${#APPS[@]} -eq 0 ]]; then
        print_color "$RED" "Error: No applications found in configuration file!"
        exit 1
    fi
}

# Function to show application details
show_app_details() {
    local app="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local working_dir="${APP_WORKING_DIR[$app]:-}"
    
    if [[ -z "$working_dir" ]]; then
        working_dir="$script_dir (default)"
    else
        # Expand tilde and relative paths for display
        working_dir="${working_dir/#\~/$HOME}"
        if [[ ! "$working_dir" =~ ^/ ]]; then
            working_dir="$script_dir/$working_dir"
        fi
    fi
    
    echo
    print_color "$CYAN" "=== $app ==="
    echo "Build (Host):   ${APP_BUILD_HOST[$app]:-'Not configured'}"
    echo "Build (Target): ${APP_BUILD_TARGET[$app]:-'Not configured'}"
    echo "Run (Host):     ${APP_RUN_HOST[$app]:-'Not configured'}"
    echo "Clean:          ${APP_CLEAN[$app]:-'Not configured'}"
    echo "Working Dir:    $working_dir"
    echo
}

# Function to execute command
execute_command() {
    local app="$1"
    local command_type="$2"
    local command=""
    local action_name=""
    
    case "$command_type" in
        "build_host")
            command="${APP_BUILD_HOST[$app]:-}"
            action_name="Build (Host)"
            ;;
        "build_target")
            command="${APP_BUILD_TARGET[$app]:-}"
            action_name="Build (Target)"
            ;;
        "run_host")
            command="${APP_RUN_HOST[$app]:-}"
            action_name="Run (Host)"
            ;;
        "clean")
            command="${APP_CLEAN[$app]:-}"
            action_name="Clean"
            ;;
    esac
    
    if [[ -z "$command" ]]; then
        log_execution "$app" "$action_name" "error"
        print_color "$RED" "Error: No command configured for $command_type in $app"
        return 1
    fi
    
    # Get working directory - default to script directory if not specified
    local working_dir="${APP_WORKING_DIR[$app]:-}"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -z "$working_dir" ]]; then
        working_dir="$script_dir"
    fi
    
    # Expand tilde in working_dir if present
    working_dir="${working_dir/#\~/$HOME}"
    
    # Make relative paths relative to script directory
    if [[ ! "$working_dir" =~ ^/ ]]; then
        working_dir="$script_dir/$working_dir"
    fi
    
    # Check if working directory exists
    if [[ ! -d "$working_dir" ]]; then
        log_execution "$app" "$action_name" "error"
        print_color "$RED" "Error: Working directory '$working_dir' does not exist for $app"
        return 1
    fi
    
    log_execution "$app" "$action_name" "start"
    
    # Execute the command in a subshell with proper working directory
    # Capture both stdout and stderr for error reporting
    local output
    local exit_code
    output=$(cd "$working_dir" && bash -c "$command" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_execution "$app" "$action_name" "success"
        return 0
    else
        log_execution "$app" "$action_name" "error"
        print_color "$RED" "Command failed with exit code $exit_code"
        if [[ -n "$output" && $DEBUG_MODE -eq 1 ]]; then
            print_color "$RED" "Error output: $output"
        fi
        return 1
    fi
}

# Function to execute a single command with summary
execute_single() {
    local app="$1"
    local action="$2"
    local command_type="$3"
    
    print_color "$BLUE" "📦 Executing: $app - $action"
    echo
    
    local success_count=0
    local failure_count=0
    
    if execute_command "$app" "$command_type"; then
        success_count=1
    else
        failure_count=1
    fi
    
    echo
    print_color "$BOLD" "📊 Execution Summary:"
    if [[ $success_count -gt 0 ]]; then
        print_color "$GREEN" "✅ Successful: $success_count"
    fi
    if [[ $failure_count -gt 0 ]]; then
        print_color "$RED" "❌ Failed: $failure_count"
    fi
    echo
    echo "Press Enter to continue..."
    read
}

# Function to execute multiple commands in parallel
execute_parallel() {
    local -a pids=()
    local -a commands=()
    local -a command_names=()
    local total=${#SELECTED_ITEMS[@]}
    
    if [[ $total -eq 0 ]]; then
        print_color "$YELLOW" "No items selected for execution."
        return
    fi
    
    print_color "$BLUE" "📦 Executing $total selected items in parallel..."
    echo
    
    # Start all commands in background
    for item in "${SELECTED_ITEMS[@]}"; do
        if [[ "$item" =~ ^(.+)\ -\ Show\ Details$ ]]; then
            # Skip details items
            continue
        elif [[ "$item" =~ ^(.+)\ -\ (.+)$ ]]; then
            local app="${BASH_REMATCH[1]}"
            local action="${BASH_REMATCH[2]}"
            
            case "$action" in
                "Build (Host)")
                    execute_command "$app" "build_host" &
                    ;;
                "Build (Target)")
                    execute_command "$app" "build_target" &
                    ;;
                "Run (Host)")
                    execute_command "$app" "run_host" &
                    ;;
                "Clean")
                    execute_command "$app" "clean" &
                    ;;
            esac
            pids+=($!)
            command_names+=("$item")
        fi
    done
    
    # Wait for all background processes and track which ones failed
    local success_count=0
    local failure_count=0
    local -a failed_commands=()
    
    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local cmd_name="${command_names[$i]}"
        if wait "$pid"; then
            ((success_count++))
        else
            ((failure_count++))
            failed_commands+=("$cmd_name")
        fi
    done
    
    echo
    print_color "$BOLD" "📊 Execution Summary:"
    print_color "$GREEN" "✅ Successful: $success_count"
    if [[ $failure_count -gt 0 ]]; then
        print_color "$RED" "❌ Failed: $failure_count"
        if [[ ${#failed_commands[@]} -gt 0 ]]; then
            print_color "$RED" "Failed commands:"
            for failed_cmd in "${failed_commands[@]}"; do
                print_color "$RED" "  - $failed_cmd"
            done
        fi
    fi
    echo
    echo "Press Enter to continue..."
    read
}

# Function to check if item is selected
is_selected() {
    local item="$1"
    for selected_item in "${SELECTED_ITEMS[@]}"; do
        [[ "$selected_item" == "$item" ]] && return 0
    done
    return 1
}

# Function to toggle selection
toggle_selection() {
    local item="$1"
    local -a new_selected=()
    local found=false
    
    debug_log "toggle_selection called with: '$item'"
    debug_log "Current SELECTED_ITEMS: ${SELECTED_ITEMS[*]}"
    
    for selected_item in "${SELECTED_ITEMS[@]}"; do
        if [[ "$selected_item" == "$item" ]]; then
            found=true
            debug_log "Found existing selection, removing: '$selected_item'"
        else
            new_selected+=("$selected_item")
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        new_selected+=("$item")
        debug_log "Adding new selection: '$item'"
    fi
    
    SELECTED_ITEMS=("${new_selected[@]}")
    debug_log "Final SELECTED_ITEMS: ${SELECTED_ITEMS[*]}"
}

# Function to select all actionable items
select_all() {
    SELECTED_ITEMS=()
    for app in "${APPS[@]}"; do
        [[ -n "${APP_BUILD_HOST[$app]:-}" ]] && SELECTED_ITEMS+=("$app - Build (Host)")
        [[ -n "${APP_BUILD_TARGET[$app]:-}" ]] && SELECTED_ITEMS+=("$app - Build (Target)")
        [[ -n "${APP_RUN_HOST[$app]:-}" ]] && SELECTED_ITEMS+=("$app - Run (Host)")
        [[ -n "${APP_CLEAN[$app]:-}" ]] && SELECTED_ITEMS+=("$app - Clean")
    done
}

# Function to clear all selections
select_none() {
    SELECTED_ITEMS=()
}

# Function to select all currently filtered actionable items
select_filtered() {
    local -a filtered_items=("$@")
    
    for item in "${filtered_items[@]}"; do
        # Skip "Show Details" items and only select actionable items
        if [[ ! "$item" =~ -\ Show\ Details$ ]]; then
            # Check if item is not already selected
            if ! is_selected "$item"; then
                SELECTED_ITEMS+=("$item")
                debug_log "Added to selection: '$item'"
            fi
        fi
    done
}

# Function to deselect all currently filtered items
deselect_filtered() {
    local -a filtered_items=("$@")
    local -a new_selected=()
    
    # Keep only items that are NOT in the filtered list
    for selected_item in "${SELECTED_ITEMS[@]}"; do
        local found_in_filtered=false
        for filtered_item in "${filtered_items[@]}"; do
            if [[ "$selected_item" == "$filtered_item" ]]; then
                found_in_filtered=true
                debug_log "Removing from selection: '$selected_item'"
                break
            fi
        done
        
        if [[ "$found_in_filtered" == "false" ]]; then
            new_selected+=("$selected_item")
        fi
    done
    
    SELECTED_ITEMS=("${new_selected[@]}")
}

# Function to display unified menu
show_unified_menu() {
    local -a menu_items=()
    local selected=0
    local filter=""
    local prev_filter=""
    local first_draw=true
    local need_full_clear=false
    
    # Build menu items
    for app in "${APPS[@]}"; do
        [[ -n "${APP_BUILD_HOST[$app]:-}" ]] && menu_items+=("$app - Build (Host)")
        [[ -n "${APP_BUILD_TARGET[$app]:-}" ]] && menu_items+=("$app - Build (Target)")
        [[ -n "${APP_RUN_HOST[$app]:-}" ]] && menu_items+=("$app - Run (Host)")
        [[ -n "${APP_CLEAN[$app]:-}" ]] && menu_items+=("$app - Clean")
        menu_items+=("$app - Show Details")
    done
    
    # Hide cursor to prevent flickering
    printf '\033[?25l'
    
    # Ensure cursor is shown on exit
    trap 'printf "\033[?25h"' EXIT
    
    while true; do
        # Check if we need a full clear (only for major changes, not filter typing)
        if [[ "$first_draw" == "true" ]] || [[ "$need_full_clear" == "true" ]]; then
            clear
            first_draw=false
            need_full_clear=false
        else
            # Move cursor to home position (top-left corner)
            printf '\033[H'
        fi
        
        # Track if filter changed for content clearing
        local filter_changed=false
        if [[ "$filter" != "$prev_filter" ]]; then
            filter_changed=true
        fi
        prev_filter="$filter"
        print_color "$BLUE" "╔════════════════════════════════════════════════╗"
        print_color "$BLUE" "║           Shell-Bun by Fredrik Reveny          ║"
        print_color "$BLUE" "╚════════════════════════════════════════════════╝"
        echo
        print_color "$CYAN" "Navigation: ↑/↓ arrows | PgUp/PgDn: jump 10 lines | Type: filter | Space: select | Enter: execute | ESC: quit"
        print_color "$CYAN" "Shortcuts: '+': select visible | '-': deselect visible | Enter: run current or selected"
        echo
        
        # Clear content area if filter changed or selections changed (but not full screen to avoid flicker)
        if [[ "$filter_changed" == "true" ]] || [[ "$need_full_clear" == "true" && "$first_draw" == "false" ]]; then
            printf '\033[J'  # Clear from cursor to end of screen
        fi
        
        if [[ -n "$filter" ]]; then
            print_color "$YELLOW" "Filter: $filter"
        else
            print_color "$DIM" "Filter: (type to search)"
        fi
        
        if [[ ${#SELECTED_ITEMS[@]} -gt 0 ]]; then
            print_color "$GREEN" "Selected: ${#SELECTED_ITEMS[@]} items"
        else
            print_color "$DIM" "Selected: none"
        fi
        echo
        
        # Filter and display matching commands
        local -a filtered=()
        local display_index=0
        
        for item in "${menu_items[@]}"; do
            if [[ -z "$filter" ]] || [[ "${item,,}" == *"${filter,,}"* ]]; then
                filtered+=("$item")
            fi
        done
        
        # Adjust selected index if it's out of bounds
        if [[ $selected -ge ${#filtered[@]} ]] && [[ ${#filtered[@]} -gt 0 ]]; then
            selected=$((${#filtered[@]} - 1))
        fi
        if [[ $selected -lt 0 ]]; then
            selected=0
        fi
        
        # Display filtered items
        for i in "${!filtered[@]}"; do
            local item="${filtered[$i]}"
            local prefix="  "
            local suffix=""
            local is_currently_selected=false
            local is_highlighted=false
            local is_show_details=false
            
            # Check if this is a "Show Details" item
            if [[ "$item" =~ -\ Show\ Details$ ]]; then
                is_show_details=true
            fi
            
            # Check if selected for execution
            if is_selected "$item"; then
                suffix=" [✓]"
                is_currently_selected=true
            fi
            
            # Check if currently highlighted
            if [[ $i -eq $selected ]] && [[ ${#filtered[@]} -gt 0 ]]; then
                prefix="► "
                is_highlighted=true
            fi
            
            # Display with appropriate colors
            if [[ "$is_currently_selected" == "true" && "$is_highlighted" == "true" ]]; then
                # Selected AND highlighted: bold green with bright arrow
                print_color "$BOLD$GREEN" "${prefix}${item}${suffix}"
            elif [[ "$is_currently_selected" == "true" ]]; then
                # Selected but not highlighted: green with checkmark
                print_color "$GREEN" "${prefix}${item}${suffix}"
            elif [[ "$is_highlighted" == "true" && "$is_show_details" == "true" ]]; then
                # Highlighted "Show Details": purple/magenta with arrow
                print_color "$PURPLE" "${prefix}${item}${suffix}"
            elif [[ "$is_highlighted" == "true" ]]; then
                # Highlighted but not selected: cyan with arrow
                print_color "$CYAN" "${prefix}${item}${suffix}"
            elif [[ "$is_show_details" == "true" ]]; then
                # "Show Details" items: dimmed when not highlighted
                print_color "$DIM" "${prefix}${item}${suffix}"
            else
                # Normal items: default color
                echo "  ${item}${suffix}"
            fi
        done
        
        if [[ ${#filtered[@]} -eq 0 ]]; then
            print_color "$RED" "No matches found"
        fi
        
        # Clear any remaining lines from previous draws to prevent artifacts
        printf '\033[J'
        
        # Read user input with enhanced key detection
        unset key
        IFS= read -rsn1 key 2>/dev/null || continue
        
        # Advanced debugging for WSL key detection issues
        key_hex=$(printf '%02x' "'$key" 2>/dev/null || echo 'empty')
        key_oct=$(printf '%03o' "'$key" 2>/dev/null || echo 'empty')
        key_len=${#key}
        debug_log "=== KEY ANALYSIS ==="
        debug_log "Key string: '$key'"
        debug_log "Key length: $key_len"
        debug_log "Key hex: $key_hex"
        debug_log "Key octal: $key_oct"
        
        # Try to read additional characters to distinguish keys
        additional_chars=""
        if [[ "$key_hex" == "00" ]]; then
            debug_log "NULL character detected - checking for additional data"
            # Try to read more characters with a short timeout
            for i in {1..3}; do
                extra_char=""
                read -rsn1 -t 0.01 extra_char 2>/dev/null || break
                if [[ -n "$extra_char" ]]; then
                    additional_chars="$additional_chars$extra_char"
                    debug_log "Additional char $i: '$(printf '%02x' "'$extra_char")'"
                fi
            done
            debug_log "Additional characters: '$additional_chars' (length: ${#additional_chars})"
        fi
        
        # Debug logging
        local ascii_val=$(printf '%d' "'$key" 2>/dev/null || echo 'N/A')
        debug_log "Key pressed: '$key' (ASCII: $ascii_val)"
        debug_log "Current filter: '$filter'"
        debug_log "Selected items count: ${#SELECTED_ITEMS[@]}"
        
        # Special debug for common problematic keys
        case "$ascii_val" in
            9) debug_log "Detected TAB character (ASCII 9)" ;;
            10) debug_log "Detected LINE FEED (ASCII 10)" ;;
            13) debug_log "Detected CARRIAGE RETURN (ASCII 13)" ;;
            0) debug_log "Detected NULL character (ASCII 0)" ;;
            32) debug_log "Detected SPACE character (ASCII 32)" ;;
        esac
        
        # NOTE: Avoid using alphabet characters (a-z, A-Z) as hotkeys to prevent 
        # conflicts with fuzzy search typing. Use symbols, function keys, or special keys instead.
        
        # WSL-specific handling: Both Space and Enter send ASCII 0, need to distinguish
        action_taken=false
        
        case "$key" in
            $'\x1b') # Escape key or arrow keys
                debug_log "Detected ESC sequence"
                # Read the next part to distinguish between ESC and arrow keys
                read -rsn2 -t 0.1 arrows 2>/dev/null
                debug_log "Arrow sequence: '$arrows'"
                if [[ "$arrows" == "[A" ]]; then
                    # Up arrow
                    debug_log "Up arrow pressed"
                    if [[ $selected -gt 0 ]]; then
                        ((selected--))
                    fi
                elif [[ "$arrows" == "[B" ]]; then
                    # Down arrow
                    debug_log "Down arrow pressed"
                    if [[ $selected -lt $((${#filtered[@]} - 1)) ]] && [[ ${#filtered[@]} -gt 0 ]]; then
                        ((selected++))
                    fi
                elif [[ "$arrows" == "[5" ]]; then
                    # Page Up - read the final ~ character
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        debug_log "Page Up pressed"
                        # Jump up by 10 lines
                        new_selected=$((selected - 10))
                        if [[ $new_selected -lt 0 ]]; then
                            selected=0
                        else
                            selected=$new_selected
                        fi
                    fi
                elif [[ "$arrows" == "[6" ]]; then
                    # Page Down - read the final ~ character
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        debug_log "Page Down pressed"
                        # Jump down by 10 lines
                        new_selected=$((selected + 10))
                        if [[ $new_selected -ge ${#filtered[@]} ]] && [[ ${#filtered[@]} -gt 0 ]]; then
                            selected=$((${#filtered[@]} - 1))
                        else
                            selected=$new_selected
                        fi
                    fi
                elif [[ "$arrows" == "[3" ]]; then
                    # Potential Ctrl+Backspace sequence - read final character
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        debug_log "Ctrl+Backspace (ESC sequence) pressed - clearing filter"
                        filter=""
                        selected=0
                        need_full_clear=true
                    fi
                else
                    # Plain ESC key or unknown sequence - quit
                    debug_log "ESC key pressed - quitting"
                    # Clear screen and restore cursor before exiting
                    printf '\033[?25h'  # Show cursor
                    clear
                    print_color "$YELLOW" "Goodbye!"
                    exit 0
                fi
                action_taken=true
                ;;
            $'\0') # Null character - in WSL this is actually Enter!
                debug_log "NULL character detected - treating as ENTER in WSL"
                if [[ ${#filtered[@]} -gt 0 ]]; then
                    local selection="${filtered[$selected]}"
                    debug_log "Selected item: '$selection'"
                    if [[ "$selection" =~ ^(.+)\ -\ Show\ Details$ ]]; then
                        debug_log "Showing details for app"
                        local app="${BASH_REMATCH[1]}"
                        clear
                        show_app_details "$app"
                        echo "Press Enter to continue..."
                        read
                        need_full_clear=true
                    else
                        # Check if there are selected items
                        if [[ ${#SELECTED_ITEMS[@]} -gt 0 ]]; then
                            debug_log "Running selected items (${#SELECTED_ITEMS[@]} items)"
                            execute_parallel
                            need_full_clear=true
                        else
                            # No selections - execute the currently highlighted command
                            debug_log "No selections - executing highlighted command with summary"
                            if [[ "$selection" =~ ^(.+)\ -\ (.+)$ ]]; then
                                local app="${BASH_REMATCH[1]}"
                                local action="${BASH_REMATCH[2]}"
                                
                                case "$action" in
                                    "Build (Host)")
                                        execute_single "$app" "$action" "build_host"
                                        ;;
                                    "Build (Target)")
                                        execute_single "$app" "$action" "build_target"
                                        ;;
                                    "Run (Host)")
                                        execute_single "$app" "$action" "run_host"
                                        ;;
                                    "Clean")
                                        execute_single "$app" "$action" "clean"
                                        ;;
                                esac
                                need_full_clear=true
                            fi
                        fi
                    fi
                fi
                action_taken=true
                ;;
            ' ') # Space bar - toggle selection (if we get a real space)
                debug_log "Real SPACE character detected"
                if [[ ${#filtered[@]} -gt 0 ]]; then
                    local selection="${filtered[$selected]}"
                    debug_log "Current selection: '$selection'"
                    if [[ ! "$selection" =~ -\ Show\ Details$ ]]; then
                        debug_log "Toggling selection for: '$selection'"
                        toggle_selection "$selection"
                        debug_log "After toggle, selected items: ${#SELECTED_ITEMS[@]}"
                        need_full_clear=true
                    else
                        debug_log "Cannot select 'Show Details' item"
                    fi
                else
                    debug_log "No filtered items available"
                fi
                action_taken=true
                ;;
            $'\n'|$'\r') # Enter key - execute highlighted item or selected items
                debug_log "Real ENTER character detected"
                if [[ ${#filtered[@]} -gt 0 ]]; then
                    local selection="${filtered[$selected]}"
                    debug_log "Selected item: '$selection'"
                    if [[ "$selection" =~ ^(.+)\ -\ Show\ Details$ ]]; then
                        debug_log "Showing details for app"
                        local app="${BASH_REMATCH[1]}"
                        clear
                        show_app_details "$app"
                        echo "Press Enter to continue..."
                        read
                        need_full_clear=true
                    else
                        # Check if there are selected items
                        if [[ ${#SELECTED_ITEMS[@]} -gt 0 ]]; then
                            debug_log "Running selected items (${#SELECTED_ITEMS[@]} items)"
                            execute_parallel
                            need_full_clear=true
                        else
                            # No selections - execute the currently highlighted command
                            debug_log "No selections - executing highlighted command with summary"
                            if [[ "$selection" =~ ^(.+)\ -\ (.+)$ ]]; then
                                local app="${BASH_REMATCH[1]}"
                                local action="${BASH_REMATCH[2]}"
                                
                                case "$action" in
                                    "Build (Host)")
                                        execute_single "$app" "$action" "build_host"
                                        ;;
                                    "Build (Target)")
                                        execute_single "$app" "$action" "build_target"
                                        ;;
                                    "Run (Host)")
                                        execute_single "$app" "$action" "run_host"
                                        ;;
                                    "Clean")
                                        execute_single "$app" "$action" "clean"
                                        ;;
                                esac
                                need_full_clear=true
                            fi
                        fi
                    fi
                fi
                action_taken=true
                ;;
            '+') # Plus - select all filtered items
                debug_log "Plus key pressed - selecting all filtered items"
                select_filtered "${filtered[@]}"
                need_full_clear=true
                action_taken=true
                ;;
            '-') # Minus - deselect filtered items
                debug_log "Minus key pressed - deselecting filtered items"
                deselect_filtered "${filtered[@]}"
                need_full_clear=true
                action_taken=true
                ;;
            $'\x7f'|$'\x08') # Backspace
                debug_log "Backspace pressed"
                filter="${filter%?}"
                selected=0
                action_taken=true
                ;;
            $'\x17') # Ctrl+Backspace (Ctrl+W) - clear entire filter
                debug_log "Ctrl+Backspace pressed - clearing filter"
                filter=""
                selected=0
                need_full_clear=true
                action_taken=true
                ;;
            $'\x1f') # Ctrl+Backspace (alternative sequence) - clear entire filter
                debug_log "Ctrl+Backspace (alt) pressed - clearing filter"
                filter=""
                selected=0
                need_full_clear=true
                action_taken=true
                ;;


        esac
        
        # If no action was taken by special keys, handle as filter input
        if [[ "$action_taken" == "false" ]]; then
            debug_log "No special action - checking if character should be added to filter"
            debug_log "Other character: '$key' (hex: $key_hex)"
            # Only add printable characters (excluding our special keys)
            if [[ "$key" =~ [[:print:]] && "$key" != " " && "$key" != "+" && "$key" != "-" ]]; then
                debug_log "Adding to filter: '$key'"
                filter="$filter$key"
                selected=0
            else
                debug_log "Character excluded from filter: '$key'"
            fi
        fi
    done
}

# Function to execute commands in CI mode (non-interactive)
execute_ci_mode() {
    local app="$1"
    local actions="$2"
    
    # Check if app exists
    local app_found=false
    for existing_app in "${APPS[@]}"; do
        if [[ "$existing_app" == "$app" ]]; then
            app_found=true
            break
        fi
    done
    
    if [[ "$app_found" == "false" ]]; then
        echo "Error: Application '$app' not found in configuration"
        echo "Available applications: ${APPS[*]}"
        exit 1
    fi
    
    # Parse actions
    local -a action_list=()
    if [[ "$actions" == "all" ]]; then
        # Add all available actions for this app
        [[ -n "${APP_BUILD_HOST[$app]:-}" ]] && action_list+=("build_host")
        [[ -n "${APP_BUILD_TARGET[$app]:-}" ]] && action_list+=("build_target")
    else
        # Split comma-separated actions
        IFS=',' read -ra action_list <<< "$actions"
    fi
    
    if [[ ${#action_list[@]} -eq 0 ]]; then
        echo "Error: No valid actions specified or available for '$app'"
        echo "Available actions: build_host, build_target, run_host, clean"
        exit 1
    fi
    
    echo "Shell-Bun CI Mode: Executing $app"
    echo "Actions: ${action_list[*]}"
    echo "Config: $CONFIG_FILE"
    echo "----------------------------------------"
    
    local success_count=0
    local failure_count=0
    local -a failed_actions=()
    
    # Execute each action
    for action in "${action_list[@]}"; do
        case "$action" in
            "build_host"|"build_target"|"run_host"|"clean")
                if execute_command "$app" "$action"; then
                    ((success_count++))
                else
                    ((failure_count++))
                    failed_actions+=("$action")
                fi
                ;;
            *)
                echo "Error: Unknown action '$action'"
                echo "Available actions: build_host, build_target, run_host, clean"
                exit 1
                ;;
        esac
    done
    
    echo "----------------------------------------"
    echo "CI Execution Summary:"
    echo "✅ Successful: $success_count"
    if [[ $failure_count -gt 0 ]]; then
        echo "❌ Failed: $failure_count"
        echo "Failed actions: ${failed_actions[*]}"
        exit 1
    else
        echo "🎉 All actions completed successfully"
        exit 0
    fi
}

# Main function
main() {
    # Parse the configuration file first
    print_color "$BLUE" "Loading configuration from: $CONFIG_FILE"
    parse_config
    
    # Handle CI mode (non-interactive)
    if [[ $CI_MODE -eq 1 ]]; then
        if [[ -z "$CI_APP" ]]; then
            echo "Error: Application name required for CI mode"
            echo "Available applications: ${APPS[*]}"
            echo "Use --help for usage information"
            exit 1
        fi
        
        if [[ -z "$CI_ACTIONS" ]]; then
            echo "Error: Action(s) required for CI mode"
            echo "Available actions: build_host, build_target, run_host, clean"
            echo "Use --help for usage information"
            exit 1
        fi
        
        execute_ci_mode "$CI_APP" "$CI_ACTIONS"
        # execute_ci_mode will exit the script
    fi
    
    # Interactive mode - check if we're in a terminal that supports colors and arrow keys
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        print_color "$RED" "Error: This script requires an interactive terminal for interactive mode"
        print_color "$YELLOW" "Use --ci mode for non-interactive execution"
        echo "Example: $0 --ci MyApp build_host"
        exit 1
    fi
    
    print_color "$GREEN" "Found ${#APPS[@]} applications"
    if [[ ${#APPS[@]} -gt 0 ]]; then
        echo "Applications: ${APPS[*]}"
    fi
    echo
    
    show_unified_menu
}

# Run main function
main "$@" 