#!/usr/bin/env bash

#
# Shell-Bun - Interactive build environment script
# Version: 1.4.0
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

# Version information
VERSION="1.4.0"

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
CLI_CONTAINER_OVERRIDE=0
CLI_CONTAINER_COMMAND=""

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
            if [[ $# -gt 0 && ! "$1" =~ ^-- && ! "$1" =~ \.cfg$ ]]; then
                CI_APP="$1"
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^-- && ! "$1" =~ \.cfg$ ]]; then
                    CI_ACTIONS="$1"
                    shift
                fi
            fi
            ;;
        --container)
            if [[ $# -lt 2 ]]; then
                echo "Error: --container requires a command argument (use --container <cmd> or --container=<cmd>)"
                exit 1
            fi
            CLI_CONTAINER_OVERRIDE=1
            CLI_CONTAINER_COMMAND="$2"
            shift 2
            ;;
        --container=*)
            CLI_CONTAINER_OVERRIDE=1
            CLI_CONTAINER_COMMAND="${1#--container=}"
            shift
            ;;
        --help|-h)
            echo "Shell-Bun v$VERSION - Interactive build environment script"
            echo "Copyright (c) 2025, Fredrik Reveny"
            echo ""
            echo "Usage:"
            echo "  $0 [options] [config-file]"
            echo ""
            echo "Interactive mode (default):"
            echo "  $0                         # Use default config (shell-bun.cfg)"
            echo "  $0 my-config.txt           # Use custom config file"
            echo "  $0 --debug                 # Enable debug logging"
            echo "  $0 --container \"podman exec ...\"   # Override container command"
            echo ""
            echo "Non-interactive mode (CI/CD) with fuzzy pattern matching:"
            echo "  $0 --ci APP_PATTERN ACTION_PATTERN   # Run actions matching patterns"
            echo ""
            echo "App pattern examples:"
            echo "  MyWebApp                    # Exact app name"
            echo "  *Web*                       # Wildcard: any app containing 'Web'"
            echo "  API*                        # Wildcard: apps starting with 'API'"
            echo "  web                         # Substring: apps containing 'web'"
            echo "  MyWebApp,API*,mobile        # Multiple: comma-separated patterns"
            echo ""
            echo "Action pattern examples:"
            echo "  build_host                  # Exact action name"
            echo "  build*                      # Wildcard: actions starting with 'build'"
            echo "  *host                       # Wildcard: actions ending with 'host'"
            echo "  test*,deploy                # Multiple specific actions"
            echo "  unit                        # Substring: actions containing 'unit'"
            echo "  all                         # All available actions"
            echo ""
            echo "Actions are completely user-defined in your config file"
            echo ""
            echo "Examples:"
            echo "  $0 --ci MyWebApp build             # Run build action"
            echo "  $0 --ci \"*Web*\" test*              # Run test actions on Web apps"
            echo "  $0 --ci \"API*,Frontend\" all        # Run all actions on API and Frontend"
            echo "  $0 --ci mobile deploy,test         # Multiple actions for mobile apps"
            echo "  $0 --ci \"*\" unit_test my.cfg       # Run unit_test on all apps with custom config"
            exit 0
            ;;
        --version|-v)
            echo "v$VERSION"
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
declare -A APP_ACTIONS=()      # Key: "app:action", Value: "command"
declare -A APP_ACTION_LIST=()  # Key: "app", Value: "space-separated list of actions"
declare -A APP_WORKING_DIR=()
declare -A APP_LOG_DIR=()      # Key: "app", Value: "log directory path"
declare -a SELECTED_ITEMS=()
declare -a EXECUTION_RESULTS=() # Track execution results for log viewing
GLOBAL_LOG_DIR=""              # Global log directory from config
CONFIG_CONTAINER_COMMAND=""    # Container command defined in config (if any)
CONTAINER_COMMAND=""           # Effective container command after CLI overrides

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

# Function to generate log file path
generate_log_file_path() {
    local app="$1"
    local action="$2"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Get log directory - check app-specific first, then global, then default
    local log_dir="${APP_LOG_DIR[$app]:-}"
    if [[ -z "$log_dir" && -n "$GLOBAL_LOG_DIR" ]]; then
        log_dir="$GLOBAL_LOG_DIR"
    elif [[ -z "$log_dir" ]]; then
        log_dir="$script_dir/logs"
    fi
    
    # Expand tilde in log_dir if present
    log_dir="${log_dir/#\~/$HOME}"
    
    # Make relative paths relative to script directory
    if [[ ! "$log_dir" =~ ^/ ]]; then
        log_dir="$script_dir/$log_dir"
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$log_dir" 2>/dev/null || {
        echo "Warning: Cannot create log directory '$log_dir', using script directory"
        log_dir="$script_dir"
    }
    
    # Generate log file name: timestamp_app_action.log
    local log_file="$log_dir/${timestamp}_${app}_${action}.log"
    echo "$log_file"
}

# Function to log execution status
log_execution() {
    local app="$1"
    local action="$2"
    local status="$3" # start, success, error
    local command="${4:-}" # optional command to display
    
    case "$status" in
        "start")
            if [[ -n "$command" ]]; then
                print_color "$CYAN" "🚀 Starting: $app - $action: ${DIM}$command${NC}${CYAN}"
            else
                print_color "$CYAN" "🚀 Starting: $app - $action"
            fi
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
    CONFIG_CONTAINER_COMMAND=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            # New application section
            current_app="${BASH_REMATCH[1]}"
            APPS+=("$current_app")
            APP_ACTION_LIST["$current_app"]=""
        elif [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            # Configuration directive
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Strip whitespace from key
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ -z "$current_app" && "$key" == "log_dir" ]]; then
                # Global log_dir setting (outside any app section)
                GLOBAL_LOG_DIR="$value"
            elif [[ -z "$current_app" && "$key" == "container" ]]; then
                # Global container command (outside any app section)
                CONFIG_CONTAINER_COMMAND="$value"
            elif [[ -n "$current_app" && "$key" == "working_dir" ]]; then
                # Special handling for working_dir
                APP_WORKING_DIR["$current_app"]="$value"
            elif [[ -n "$current_app" && "$key" == "log_dir" ]]; then
                # Special handling for log_dir (per-app override)
                APP_LOG_DIR["$current_app"]="$value"
            elif [[ -n "$current_app" ]]; then
                # Generic action - store the command and add to action list
                APP_ACTIONS["$current_app:$key"]="$value"
                
                # Add to action list if not already present
                local current_actions="${APP_ACTION_LIST[$current_app]}"
                if [[ -z "$current_actions" ]]; then
                    APP_ACTION_LIST["$current_app"]="$key"
                elif [[ "$current_actions" != *"$key"* ]]; then
                    APP_ACTION_LIST["$current_app"]="$current_actions $key"
                fi
            fi
        fi
    done < "$CONFIG_FILE"
    
    if [[ $CLI_CONTAINER_OVERRIDE -eq 1 ]]; then
        CONTAINER_COMMAND="$CLI_CONTAINER_COMMAND"
    else
        CONTAINER_COMMAND="$CONFIG_CONTAINER_COMMAND"
    fi

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
    local log_dir="${APP_LOG_DIR[$app]:-}"
    
    if [[ -z "$working_dir" ]]; then
        working_dir="$script_dir (default)"
    else
        # Expand tilde and relative paths for display
        working_dir="${working_dir/#\~/$HOME}"
        if [[ ! "$working_dir" =~ ^/ ]]; then
            working_dir="$script_dir/$working_dir"
        fi
    fi
    
    # Determine effective log directory
    if [[ -n "$log_dir" ]]; then
        # App-specific log directory
        log_dir="${log_dir/#\~/$HOME}"
        if [[ ! "$log_dir" =~ ^/ ]]; then
            log_dir="$script_dir/$log_dir"
        fi
        log_dir="$log_dir (app-specific)"
    elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
        # Global log directory
        log_dir="$GLOBAL_LOG_DIR"
        log_dir="${log_dir/#\~/$HOME}"
        if [[ ! "$log_dir" =~ ^/ ]]; then
            log_dir="$script_dir/$log_dir"
        fi
        log_dir="$log_dir (global)"
    else
        # Default
        log_dir="$script_dir/logs (default)"
    fi
    
    echo
    print_color "$CYAN" "=== $app ==="
    echo "Working Dir:    $working_dir"
    echo "Log Dir:        $log_dir"
    
    # Show container configuration
    if [[ -n "$CONTAINER_COMMAND" ]]; then
        if [[ $CLI_CONTAINER_OVERRIDE -eq 1 ]]; then
            echo "Container:      $CONTAINER_COMMAND (overridden via --container)"
        else
            echo "Container:      $CONTAINER_COMMAND"
        fi
    elif [[ $CLI_CONTAINER_OVERRIDE -eq 1 ]]; then
        echo "Container:      (overridden via --container to run on host)"
    else
        echo "Container:      (none - runs on host)"
    fi
    
    echo
    print_color "$YELLOW" "Available Actions:"
    
    # Get all actions for this app
    local actions="${APP_ACTION_LIST[$app]:-}"
    if [[ -z "$actions" ]]; then
        echo "  No actions configured"
    else
        # Display each action and its command
        for action in $actions; do
            local command="${APP_ACTIONS[$app:$action]:-}"
            echo
            print_color "$CYAN" "  $action:"
            echo "    Command: $command"
            
            # Show how it will be executed (with or without container)
            if [[ -n "$CONTAINER_COMMAND" ]]; then
                local working_dir_for_display="${APP_WORKING_DIR[$app]:-}"
                if [[ -n "$working_dir_for_display" ]]; then
                    local container_cmd="cd $(printf '%q' "$working_dir_for_display") && $command"
                    local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                    echo "    Full cmd: $CONTAINER_COMMAND bash -lc $escaped_container_cmd"
                else
                    local escaped_command="$(printf '%q' "$command")"
                    echo "    Full cmd: $CONTAINER_COMMAND bash -lc $escaped_command"
                fi
            else
                echo "    Full cmd: bash -c $(printf '%q' "$command")"
            fi
        done
    fi
    echo
}

# Function to execute command
execute_command() {
    local app="$1"
    local action="$2"
    local show_output="${3:-false}"  # New parameter: whether to show output in terminal
    local log_file_var="$4"          # Variable name to store log file path
    local command="${APP_ACTIONS[$app:$action]:-}"
    local action_name="$action"
    
    if [[ -z "$command" ]]; then
        log_execution "$app" "$action_name" "error"
        print_color "$RED" "Error: No command configured for '$action' in $app"
        return 1
    fi
    
    # Get working directory - default to script directory if not specified
    local working_dir="${APP_WORKING_DIR[$app]:-}"
    local working_dir_for_container="$working_dir"  # Store original for container use
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # When using container, working_dir is relative to the container's starting point
    # When not using container, working_dir is relative to the script directory
    if [[ -n "$CONTAINER_COMMAND" ]]; then
        # Container mode: use working_dir as-is (relative to container's starting point)
        # If no working_dir specified, don't cd at all in the container
        if [[ -z "$working_dir_for_container" ]]; then
            working_dir_for_container=""
        fi
    else
        # Non-container mode: resolve paths relative to script directory
        if [[ -z "$working_dir" ]]; then
            working_dir="$script_dir"
        fi
        
        # Expand tilde in working_dir if present
        working_dir="${working_dir/#\~/$HOME}"
        
        # Make relative paths relative to script directory
        if [[ ! "$working_dir" =~ ^/ ]]; then
            working_dir="$script_dir/$working_dir"
        fi
        
        # Check if working directory exists (only for non-container mode)
        if [[ ! -d "$working_dir" ]]; then
            log_execution "$app" "$action_name" "error"
            print_color "$RED" "Error: Working directory '$working_dir' does not exist for $app"
            return 1
        fi
    fi
    
    # Generate log file path (unless in CI mode)
    local log_file=""
    if [[ $CI_MODE -eq 0 ]]; then
        log_file=$(generate_log_file_path "$app" "$action")
        # Store log file path in the provided variable name
        if [[ -n "$log_file_var" ]]; then
            declare -g "$log_file_var=$log_file"
        fi
    fi
    
    # Build the full command that will be executed (for display purposes)
    local full_command_display
    local escaped_command="$(printf '%q' "$command")"
    if [[ -n "$CONTAINER_COMMAND" ]]; then
        if [[ -n "$working_dir_for_container" ]]; then
            local container_cmd="cd $(printf '%q' "$working_dir_for_container") && $command"
            local escaped_container_cmd="$(printf '%q' "$container_cmd")"
            full_command_display="$CONTAINER_COMMAND bash -lc $escaped_container_cmd"
        else
            full_command_display="$CONTAINER_COMMAND bash -lc $escaped_command"
        fi
    else
        full_command_display="bash -c $escaped_command"
    fi
    
    log_execution "$app" "$action_name" "start" "$full_command_display"
    
    # Execute the command in a subshell with proper working directory
    local exit_code
    local escaped_command="$(printf '%q' "$command")"

    if [[ $CI_MODE -eq 1 ]]; then
        # CI mode: just print to terminal
        if [[ -n "$CONTAINER_COMMAND" ]]; then
            # Container mode: cd inside the container
            if [[ -n "$working_dir_for_container" ]]; then
                local container_cmd="cd $(printf '%q' "$working_dir_for_container") && $command"
                local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_container_cmd")
            else
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_command")
            fi
        else
            (cd "$working_dir" && bash -c "$command")
        fi
        exit_code=$?
    elif [[ "$show_output" == "true" ]]; then
        # Interactive single execution: show output and log to file
        if [[ -n "$CONTAINER_COMMAND" ]]; then
            # Container mode: cd inside the container
            if [[ -n "$working_dir_for_container" ]]; then
                local container_cmd="cd $(printf '%q' "$working_dir_for_container") && $command"
                local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_container_cmd" 2>&1 | tee "$log_file")
            else
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_command" 2>&1 | tee "$log_file")
            fi
            exit_code=${PIPESTATUS[0]}
        else
            (cd "$working_dir" && bash -c "$command" 2>&1 | tee "$log_file")
            exit_code=${PIPESTATUS[0]}
        fi
    else
        # Interactive parallel execution: only log to file
        if [[ -n "$CONTAINER_COMMAND" ]]; then
            # Container mode: cd inside the container
            if [[ -n "$working_dir_for_container" ]]; then
                local container_cmd="cd $(printf '%q' "$working_dir_for_container") && $command"
                local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_container_cmd" > "$log_file" 2>&1)
            else
                (bash -c "$CONTAINER_COMMAND bash -lc $escaped_command" > "$log_file" 2>&1)
            fi
        else
            (cd "$working_dir" && bash -c "$command" > "$log_file" 2>&1)
        fi
        exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_execution "$app" "$action_name" "success"
        return 0
    else
        log_execution "$app" "$action_name" "error"
        if [[ $CI_MODE -eq 1 ]]; then
            print_color "$RED" "Command failed with exit code $exit_code"
        fi
        return 1
    fi
}

# Function to execute a single command
execute_single() {
    local app="$1"
    local action="$2"
    
    print_color "$BLUE" "📦 Executing: $app - $action"
    echo
    
    local log_file=""
    execute_command "$app" "$action" "true" "log_file"
    
    echo
    echo "Press Enter to continue..."
    read
}

# Function to show log viewer menu
show_log_viewer() {
    local -a results=("$@")
    
    if [[ ${#results[@]} -eq 0 ]]; then
        return
    fi
    
    # Sort results: failed first, then successful
    local -a failed_results=()
    local -a success_results=()
    
    for result in "${results[@]}"; do
        if [[ "$result" =~ ^FAILED: ]]; then
            failed_results+=("$result")
        else
            success_results+=("$result")
        fi
    done
    
    local -a sorted_results=()
    sorted_results+=("${failed_results[@]}")
    sorted_results+=("${success_results[@]}")
    
    local selected=0
    local first_draw=true # For initial clear
    
    # Scrolling and viewport variables
    local terminal_height
    terminal_height=$(tput lines 2>/dev/null || echo 24) # Default to 24 if tput fails
    # Estimate lines for header/footer: 
    # 1 for "Select a log file..."
    # 1 for blank line
    # 1 for help text "Use ↑/↓ arrows..."
    # 2 for scroll indicators (potential)
    # = 6 lines
    local header_footer_lines=6 
    local min_menu_items_display=3 
    
    local menu_max_display_lines=$((terminal_height - header_footer_lines - 1)) # -1 to leave a blank line at the bottom
    if [[ $menu_max_display_lines -lt $min_menu_items_display ]]; then
        menu_max_display_lines=$min_menu_items_display
    fi
    local view_offset=0 # Starting index of the visible part of the sorted_results

    # Hide cursor to prevent flickering
    printf '\033[?25l'
    # Ensure cursor is shown on exit (also done in show_unified_menu, good practice here too)
    trap 'printf "\033[?25h"' EXIT

    local log_viewer_static_header_height=2 # "Select a log file..." + echo
    local dynamic_content_start_line=$((log_viewer_static_header_height + 1)) # Should be 3

    while true; do
        if [[ "$first_draw" == "true" ]]; then
            clear
            printf '\033[H' # Cursor to home

            # Print static header for log viewer
            print_color "$CYAN" "📋 Select a log file to view (q to quit):"
            echo

            first_draw=false
        else
            # Partial refresh for log viewer
            local start_line=${dynamic_content_start_line}
            if [[ -z "$start_line" || "$start_line" -le 0 ]]; then start_line=1; fi
            if [[ "$start_line" -gt "$terminal_height" ]]; then start_line=$terminal_height; fi

            local last_line_to_clear=$((terminal_height - 1)) # Assuming reserved_bottom_line is 1
            if [[ "$last_line_to_clear" -lt "$start_line" ]]; then last_line_to_clear=$start_line; fi
            if [[ "$last_line_to_clear" -gt "$terminal_height" ]]; then last_line_to_clear=$terminal_height; fi

            for ((line_idx = start_line; line_idx <= last_line_to_clear; line_idx++)); do
                printf $'\\033['"${line_idx}"$';1H' # Move to start of the line
                printf $'\\033[2K'                # Clear entire line
            done
            printf $'\\033['"${start_line}"$';1H'     # Reset cursor to start of dynamic content area
        fi
        
        local num_logs=${#sorted_results[@]}

        # Adjust 'selected' index to be within bounds
        if [[ $num_logs -eq 0 ]]; then
            selected=0
        else
            if [[ $selected -ge $num_logs ]]; then
                selected=$((num_logs - 1))
            fi
            if [[ $selected -lt 0 ]]; then
                selected=0
            fi
        fi

        # Calculate view_offset
        if [[ $num_logs -le $menu_max_display_lines ]]; then
            view_offset=0
        else
            if [[ $selected -lt $view_offset ]]; then
                view_offset=$selected
            elif [[ $selected -ge $((view_offset + menu_max_display_lines)) ]]; then
                view_offset=$((selected - menu_max_display_lines + 1))
            fi

            if [[ $view_offset -lt 0 ]]; then
                view_offset=0
            fi
            if [[ $((view_offset + menu_max_display_lines)) -gt $num_logs ]]; then
                view_offset=$((num_logs - menu_max_display_lines))
                if [[ $view_offset -lt 0 ]]; then view_offset=0; fi
            fi
        fi

        # Display filtered items within the viewport
        if [[ $menu_max_display_lines -gt 0 ]]; then
            local display_loop_end_index=$((view_offset + menu_max_display_lines - 1))
            if [[ $display_loop_end_index -ge $num_logs ]]; then
                display_loop_end_index=$((num_logs - 1))
            fi

            for (( i=view_offset; i <= display_loop_end_index && i < num_logs; i++ )); do
                local result="${sorted_results[$i]}"
                local prefix="  "
                
                if [[ $i -eq $selected ]]; then
                    prefix="► "
                fi
                
                if [[ "$result" =~ ^FAILED: ]]; then
                    print_color "$RED" "${prefix}${result}"
                else
                    print_color "$GREEN" "${prefix}${result}"
                fi
            done
        fi
        
        if [[ $num_logs -eq 0 ]]; then # Should not happen given initial check, but good for safety
            print_color "$YELLOW" "No log files to display."
        fi

        # Display "items below" indicator
        local items_actually_shown=0
        if [[ $num_logs -gt 0 ]]; then
            items_actually_shown=$((display_loop_end_index - view_offset + 1))
        fi
        if [[ $num_logs -gt 0 && $((view_offset + items_actually_shown)) -lt $num_logs ]]; then
            local items_below=$((num_logs - (view_offset + items_actually_shown)))
            print_color "$DIM" "  ... $((items_below)) more log(s) below ..."
        else
            if [[ $num_logs -gt $menu_max_display_lines ]]; then echo ""; fi
        fi
        
        echo
        print_color "$DIM" "Use ↑/↓ arrows, PgUp/PgDn, Enter to view, q to menu, ESC to exit"
        
        # Read user input
        read -rsn1 key 2>/dev/null
        
        case "$key" in
            $'\x1b') # Escape key or arrow keys
                read -rsn2 -t 0.1 arrows 2>/dev/null
                if [[ "$arrows" == "[A" ]]; then # Up arrow
                    if [[ $selected -gt 0 ]]; then ((selected--)); fi
                elif [[ "$arrows" == "[B" ]]; then # Down arrow
                    if [[ $selected -lt $((num_logs - 1)) ]]; then ((selected++)); fi
                elif [[ "$arrows" == "[5" ]]; then # Page Up
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        if [[ $num_logs -gt 0 ]]; then
                            selected=$((selected - menu_max_display_lines))
                            if [[ $selected -lt 0 ]]; then selected=0; fi
                        fi
                    fi
                elif [[ "$arrows" == "[6" ]]; then # Page Down
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        if [[ $num_logs -gt 0 ]]; then
                            selected=$((selected + menu_max_display_lines))
                            if [[ $selected -ge $num_logs ]]; then selected=$((num_logs - 1)); fi
                        fi
                    fi
                else # Plain ESC key
                    printf '\033[?25h'
                    clear
                    print_color "$YELLOW" "Goodbye!"
                    exit 0
                fi
                ;;
            $'\n'|$'\r'|$'\0') # Enter key
                if [[ ${#sorted_results[@]} -gt 0 ]]; then
                    local selected_result="${sorted_results[$selected]}"
                    local log_file=""
                    
                    if [[ "$selected_result" =~ ^(FAILED|SUCCESS):\ (.+)\ -\ (.+)\ \((.+)\)$ ]]; then
                        log_file="${BASH_REMATCH[4]}"
                        
                        if [[ -f "$log_file" ]]; then
                            # Use less with +G to go to the end of the file
                            less +G "$log_file"
                        else
                            print_color "$RED" "Log file not found: $log_file"
                            echo "Press Enter to continue..."
                            read
                        fi
                    fi
                fi
                ;;
            'q'|'Q')
                # Return to main menu
                break
                ;;
        esac
    done
}

# Function to execute multiple commands in parallel
execute_parallel() {
    local -a pids=()
    local -a commands=()
    local -a command_names=()
    local -a log_files=()
    local total=${#SELECTED_ITEMS[@]}
    
    if [[ $total -eq 0 ]]; then
        print_color "$YELLOW" "No items selected for execution."
        return
    fi
    
    print_color "$BLUE" "📦 Executing $total selected items in parallel..."
    echo
    
    # Clear previous execution results
    EXECUTION_RESULTS=()
    
    # Generate log files before starting background processes
    local counter=0
    for item in "${SELECTED_ITEMS[@]}"; do
        if [[ "$item" =~ ^(.+)\ -\ Show\ Details$ ]]; then
            # Skip details items
            continue
        elif [[ "$item" =~ ^(.+)\ -\ (.+)$ ]]; then
            local app="${BASH_REMATCH[1]}"
            local action="${BASH_REMATCH[2]}"
            
            # Get and display the command
            local command="${APP_ACTIONS[$app:$action]:-}"
            
            # Build the full command that will be executed (for display purposes)
            local working_dir_for_display="${APP_WORKING_DIR[$app]:-}"
            local full_command_display
            local escaped_command="$(printf '%q' "$command")"
            if [[ -n "$CONTAINER_COMMAND" ]]; then
                if [[ -n "$working_dir_for_display" ]]; then
                    local container_cmd="cd $(printf '%q' "$working_dir_for_display") && $command"
                    local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                    full_command_display="$CONTAINER_COMMAND bash -lc $escaped_container_cmd"
                else
                    full_command_display="$CONTAINER_COMMAND bash -lc $escaped_command"
                fi
            else
                full_command_display="bash -c $escaped_command"
            fi
            
            log_execution "$app" "$action" "start" "$full_command_display"
            
            # Generate log file path
            local log_file=$(generate_log_file_path "$app" "$action")
            log_files+=("$log_file")
            
            # Start command in background, redirecting to log file
            (
                # Get working directory
                local working_dir="${APP_WORKING_DIR[$app]:-}"
                local working_dir_for_container="$working_dir"  # Store original for container use
                local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                
                # When using container, working_dir is relative to the container's starting point
                # When not using container, working_dir is relative to the script directory
                if [[ -n "$CONTAINER_COMMAND" ]]; then
                    # Container mode: use working_dir as-is (relative to container's starting point)
                    # If no working_dir specified, don't cd at all in the container
                    if [[ -z "$working_dir_for_container" ]]; then
                        working_dir_for_container=""
                    fi
                else
                    # Non-container mode: resolve paths relative to script directory
                    if [[ -z "$working_dir" ]]; then
                        working_dir="$script_dir"
                    fi
                    
                    # Expand tilde in working_dir if present
                    working_dir="${working_dir/#\~/$HOME}"
                    
                    # Make relative paths relative to script directory
                    if [[ ! "$working_dir" =~ ^/ ]]; then
                        working_dir="$script_dir/$working_dir"
                    fi
                fi
                
                # Execute command
                local command="${APP_ACTIONS[$app:$action]:-}"
                if [[ -n "$CONTAINER_COMMAND" ]]; then
                    # Container mode: validate command exists and execute with cd inside container
                    if [[ -n "$command" ]]; then
                        local escaped_command="$(printf '%q' "$command")"
                        if [[ -n "$working_dir_for_container" ]]; then
                            local container_cmd="cd $(printf '%q' "$working_dir_for_container") && $command"
                            local escaped_container_cmd="$(printf '%q' "$container_cmd")"
                            bash -c "$CONTAINER_COMMAND bash -lc $escaped_container_cmd" > "$log_file" 2>&1
                        else
                            bash -c "$CONTAINER_COMMAND bash -lc $escaped_command" > "$log_file" 2>&1
                        fi
                    else
                        echo "Error: Command not found" > "$log_file" 2>&1
                        exit 1
                    fi
                else
                    # Non-container mode: validate command and working directory exist
                    if [[ -n "$command" && -d "$working_dir" ]]; then
                        cd "$working_dir" && bash -c "$command" > "$log_file" 2>&1
                    else
                        echo "Error: Command not found or working directory invalid" > "$log_file" 2>&1
                        exit 1
                    fi
                fi
            ) &
            
            pids+=($!)
            command_names+=("$item")
            ((counter++))
        fi
    done
    
    # Wait for all background processes and track which ones failed
    local success_count=0
    local failure_count=0
    local -a failed_commands=()
    
    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local cmd_name="${command_names[$i]}"
        local log_file_path="${log_files[$i]}"
        
        if wait "$pid"; then
            ((success_count++))
            EXECUTION_RESULTS+=("SUCCESS: $cmd_name ($log_file_path)")
            log_execution "${cmd_name%% - *}" "${cmd_name##* - }" "success"
        else
            ((failure_count++))
            failed_commands+=("$cmd_name")
            EXECUTION_RESULTS+=("FAILED: $cmd_name ($log_file_path)")
            log_execution "${cmd_name%% - *}" "${cmd_name##* - }" "error"
        fi
    done
    
    # Only show summary if more than one action was executed
    if [[ ${#pids[@]} -gt 1 ]]; then
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
    fi
    
    # Show log viewer directly
    if [[ ${#EXECUTION_RESULTS[@]} -gt 0 ]]; then
        show_log_viewer "${EXECUTION_RESULTS[@]}"
    else
        echo "Press Enter to continue..."
        read
    fi
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
        # Get all actions for this app
        local actions="${APP_ACTION_LIST[$app]:-}"
        if [[ -n "$actions" ]]; then
            for action in $actions; do
                SELECTED_ITEMS+=("$app - $action")
            done
        fi
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

    # Scrolling and viewport variables
    local terminal_height
    terminal_height=$(tput lines 2>/dev/null || echo 24) # Default to 24 if tput fails
    
    local title_box_height=4 # 3 for box, 1 for blank line after
    local help_lines_height=3 # 2 for help, 1 for blank line after
    local status_lines_height=2 # 1 for filter, 1 for selected (no blank line after these now)
    local scroll_indicator_lines=2 # Reserve 2 lines for "items above" and "items below" indicators
    local min_menu_items_display=3 # Minimum number of items to try and display
    local min_height_for_title_box=15 # Threshold to hide title box
    local reserved_bottom_line=1 # Keep one line at the bottom empty

    local static_header_actual_height
    local show_title_box=true
    if [[ $terminal_height -lt $min_height_for_title_box ]]; then
        show_title_box=false
        static_header_actual_height=$help_lines_height # Only help lines
    else
        show_title_box=true
        static_header_actual_height=$((title_box_height + help_lines_height)) # Title box + help lines
    fi
    
    local dynamic_content_start_line=$((static_header_actual_height + 1))
    
    local menu_max_display_lines=$((terminal_height - static_header_actual_height - status_lines_height - scroll_indicator_lines - reserved_bottom_line))
    if [[ $menu_max_display_lines -lt $min_menu_items_display ]]; then
        # If not enough space even for min display, check if we can at least show min_menu_items_display
        # by sacrificing the reserved bottom line.
        local potential_max_lines_no_reserve=$((terminal_height - static_header_actual_height - status_lines_height - scroll_indicator_lines))
        if [[ $potential_max_lines_no_reserve -ge $min_menu_items_display ]]; then
             menu_max_display_lines=$potential_max_lines_no_reserve
        elif [[ $potential_max_lines_no_reserve -lt 0 ]]; then # Not enough space at all
            menu_max_display_lines=0
        else
            menu_max_display_lines=$potential_max_lines_no_reserve # Show what we can, even if < min_menu_items_display
        fi
    fi
    if [[ $menu_max_display_lines -lt 0 ]]; then menu_max_display_lines=0; fi


    local view_offset=0 # Starting index of the visible part of the filtered items

    # Build menu items
    for app in "${APPS[@]}"; do
        local actions="${APP_ACTION_LIST[$app]:-}"
        if [[ -n "$actions" ]]; then
            for action in $actions; do
                menu_items+=("$app - $action")
            done
        fi
        menu_items+=("$app - Show Details")
    done
    
    printf '\033[?25l' # Hide cursor
    trap 'printf "\033[?25h"' EXIT # Ensure cursor is shown on exit
    
    while true; do
        if [[ "$first_draw" == "true" ]] || [[ "$need_full_clear" == "true" ]]; then
            clear
            printf '\033[H' # Cursor to home
            
            # Print static header
            if [[ "$show_title_box" == "true" ]]; then
                print_color "$BLUE" "╔══════════════════════════════════════════════════════════════════════════════════════╗"
                print_color "$BLUE" "║          Shell-Bun by Fredrik Reveny (https://github.com/Chetic/shell-bun/)          ║"
                print_color "$BLUE" "╚══════════════════════════════════════════════════════════════════════════════════════╝"
                echo
            fi
            print_color "$CYAN" "Navigation: ↑/↓ arrows | PgUp/PgDn: page | Type: filter | Space: select | Enter: execute | ESC: quit"
            print_color "$CYAN" "Shortcuts: '+' select visible | '-' deselect visible | Delete: clear filter | Enter: run current or selected"
            echo

            first_draw=false
            need_full_clear=false
        else
            # Partial refresh: move cursor to start of dynamic content and clear below
            local start_line=${dynamic_content_start_line}
            if [[ -z "$start_line" || "$start_line" -le 0 ]]; then start_line=1; fi
            if [[ "$start_line" -gt "$terminal_height" ]]; then start_line=$terminal_height; fi

            # show_unified_menu already has 'reserved_bottom_line' variable, typically 1.
            local last_line_to_clear=$((terminal_height - reserved_bottom_line))
            if [[ "$last_line_to_clear" -lt "$start_line" ]]; then last_line_to_clear=$start_line; fi
            if [[ "$last_line_to_clear" -gt "$terminal_height" ]]; then last_line_to_clear=$terminal_height; fi

            for ((line_idx = start_line; line_idx <= last_line_to_clear; line_idx++)); do
                printf $'\\033['"${line_idx}"$';1H' # Move to start of the line
                printf $'\\033[2K'                # Clear entire line
            done
            printf $'\\033['"${start_line}"$';1H'     # Reset cursor to start of dynamic content area
        fi
        
        # Track if filter changed (still useful for other logic, e.g., resetting selection index)
        local filter_changed=false 
        if [[ "$filter" != "$prev_filter" ]]; then
            filter_changed=true
            selected=0 # Reset selection when filter changes
            view_offset=0 # Reset view offset when filter changes
        fi
        prev_filter="$filter"

        # Always print dynamic content from here
        # Display filter status and selection count (Dynamic Header)
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

        # Filter menu items
        local -a filtered=()
        for item in "${menu_items[@]}"; do
            if [[ -z "$filter" ]] || [[ "${item,,}" == *"${filter,,}"* ]]; then
                filtered+=("$item")
            fi
        done
        local num_filtered=${#filtered[@]}

        # Adjust 'selected' index
        if [[ $num_filtered -eq 0 ]]; then
            selected=0
        else
            if [[ $selected -ge $num_filtered ]]; then selected=$((num_filtered - 1)); fi
            if [[ $selected -lt 0 ]]; then selected=0; fi
        fi

        # Calculate view_offset for scrolling
        if [[ $num_filtered -le $menu_max_display_lines ]]; then
            view_offset=0
        else
            if [[ $selected -lt $view_offset ]]; then
                view_offset=$selected
            elif [[ $selected -ge $((view_offset + menu_max_display_lines)) ]]; then
                view_offset=$((selected - menu_max_display_lines + 1))
            fi
            if [[ $view_offset -lt 0 ]]; then view_offset=0; fi
            local max_offset=$((num_filtered - menu_max_display_lines))
            if [[ $max_offset -lt 0 ]]; then max_offset=0; fi # Handle case where num_filtered < menu_max_display_lines
            if [[ $view_offset -gt $max_offset ]]; then view_offset=$max_offset; fi
        fi
        
        # Display "items above" indicator
        if [[ $view_offset -gt 0 ]]; then
            print_color "$DIM" "  ... $((view_offset)) more item(s) above ..."
        else
            if [[ $num_filtered -gt $menu_max_display_lines && $menu_max_display_lines -gt 0 ]]; then echo ""; fi # Keep spacing if scrollable
        fi

        # Display filtered items within the viewport
        if [[ $menu_max_display_lines -gt 0 ]]; then
            local display_loop_end_index=$((view_offset + menu_max_display_lines - 1))
            if [[ $display_loop_end_index -ge $num_filtered ]]; then
                display_loop_end_index=$((num_filtered - 1))
            fi

            for (( i=view_offset; i <= display_loop_end_index && i < num_filtered; i++ )); do
                local item="${filtered[$i]}"
                local prefix="  "
                local suffix=""
                local is_currently_selected=false
                local is_highlighted=false
                local is_show_details=false
                
                if [[ "$item" =~ "- Show Details"$ ]]; then is_show_details=true; fi
                if is_selected "$item"; then suffix=" [✓]"; is_currently_selected=true; fi
                if [[ $i -eq $selected ]]; then prefix="► "; is_highlighted=true; fi
                
                if [[ "$is_currently_selected" == "true" && "$is_highlighted" == "true" ]]; then
                    print_color "$BOLD$GREEN" "${prefix}${item}${suffix}"
                elif [[ "$is_currently_selected" == "true" ]]; then
                    print_color "$GREEN" "${prefix}${item}${suffix}"
                elif [[ "$is_highlighted" == "true" && "$is_show_details" == "true" ]]; then
                    print_color "$BOLD$PURPLE" "${prefix}${item}${suffix}"
                elif [[ "$is_highlighted" == "true" ]]; then
                    print_color "$CYAN" "${prefix}${item}${suffix}"
                elif [[ "$is_show_details" == "true" ]]; then
                    print_color "$YELLOW" "${prefix}${item}${suffix}"
                else
                    echo "  ${item}${suffix}"
                fi
            done
        fi
        
        if [[ $num_filtered -eq 0 && $menu_max_display_lines -gt 0 ]]; then
            print_color "$RED" "No matches found"
        fi

        # Display "items below" indicator
        local items_actually_shown_in_viewport=0
        if [[ $num_filtered -gt 0 && $menu_max_display_lines -gt 0 ]]; then
             local end_idx_for_shown_calc=$((view_offset + menu_max_display_lines -1))
             if [[ $end_idx_for_shown_calc -ge $num_filtered ]]; then end_idx_for_shown_calc=$((num_filtered -1)); fi
             if [[ $end_idx_for_shown_calc -ge $view_offset ]]; then # Ensure start is not past end
                items_actually_shown_in_viewport=$((end_idx_for_shown_calc - view_offset + 1))
             fi
        fi

        if [[ $num_filtered -gt 0 && $menu_max_display_lines -gt 0 && $((view_offset + items_actually_shown_in_viewport)) -lt $num_filtered ]]; then
            local items_below=$((num_filtered - (view_offset + items_actually_shown_in_viewport)))
            print_color "$DIM" "  ... $((items_below)) more item(s) below ..."
        else
            if [[ $num_filtered -gt $menu_max_display_lines && $menu_max_display_lines -gt 0 ]]; then echo ""; fi # Keep spacing if scrollable
        fi
        
        # Key handling (omitted for brevity in this thought, but it's the same as before)

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
                debug_log "ESC sequence: '$arrows'"
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
                        if [[ $num_filtered -gt 0 ]]; then
                            selected=$((selected - menu_max_display_lines))
                            if [[ $selected -lt 0 ]]; then selected=0; fi
                        fi
                        # view_offset adjustment will happen at the start of the next loop iteration
                    fi
                elif [[ "$arrows" == "[6" ]]; then
                    # Page Down - read the final ~ character
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        debug_log "Page Down pressed"
                        if [[ $num_filtered -gt 0 ]]; then
                            selected=$((selected + menu_max_display_lines))
                            if [[ $selected -ge $num_filtered ]]; then
                                selected=$((num_filtered - 1))
                            fi
                        fi
                        # view_offset adjustment will happen at the start of the next loop iteration
                    fi
                elif [[ "$arrows" == "[3" ]]; then
                    # Delete key sequence - read final character
                    read -rsn1 -t 0.1 final_char 2>/dev/null
                    if [[ "$final_char" == "~" ]]; then
                        debug_log "Delete key (ESC[3~) pressed - clearing filter"
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
                                
                                execute_single "$app" "$action"
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
                                
                                execute_single "$app" "$action"
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
    local app_pattern="$1"
    local action_pattern="$2"
    
    # Match applications using fuzzy patterns
    local matched_apps_output
    matched_apps_output=$(match_apps_fuzzy "$app_pattern")
    
    if [[ -z "$matched_apps_output" ]]; then
        echo "Error: No applications found matching pattern '$app_pattern'"
        echo "Available applications: ${APPS[*]}"
        echo ""
        echo "Pattern matching supports:"
        echo "  - Exact names: MyWebApp"
        echo "  - Wildcards: *Web*, API*"
        echo "  - Substrings: web, api"
        echo "  - Multiple: MyWebApp,API*,mobile"
        exit 1
    fi
    
    local -a matched_apps
    readarray -t matched_apps <<< "$matched_apps_output"
    
    # Prepare completely parallel execution (all actions run in parallel)
    local -a pids=()
    local -a command_descriptions=()
    local found_any_action=false
    
    # Start all matched commands in parallel
    for app in "${matched_apps[@]}"; do
        # Skip empty entries
        [[ -z "$app" ]] && continue
        
        # Match actions for this app using fuzzy patterns
        local matched_actions_output
        matched_actions_output=$(match_actions_fuzzy "$action_pattern" "$app")
        
        if [[ -z "$matched_actions_output" ]]; then
            echo "Warning: No actions found for '$app' matching pattern '$action_pattern'"
            local actions="${APP_ACTION_LIST[$app]:-}"
            echo "Available actions for $app: $actions"
            continue
        fi
        
        found_any_action=true
        
        local -a matched_actions
        readarray -t matched_actions <<< "$matched_actions_output"
        
        # Start each action in parallel
        for action in "${matched_actions[@]}"; do
            # Skip empty entries
            [[ -z "$action" ]] && continue
            
            # Start each action as a separate background process
            execute_command "$app" "$action" "false" "" &
            pids+=($!)
            command_descriptions+=("$app - $action")
        done
    done
    
    # Check if any actions were found
    if [[ "$found_any_action" == "false" || ${#pids[@]} -eq 0 ]]; then
        echo ""
        echo "Error: No actions found matching pattern '$action_pattern'"
        exit 1
    fi
    
    # Determine if this is a single action execution
    local is_single_action=false
    if [[ ${#pids[@]} -eq 1 ]]; then
        is_single_action=true
    fi
    
    # For multiple actions, show verbose header
    if [[ "$is_single_action" == "false" ]]; then
        echo "Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)"
        echo "App pattern: '$app_pattern'"
        echo "Action pattern: '$action_pattern'"
        echo "Matched apps: ${matched_apps[*]}"
        echo "Config: $CONFIG_FILE"
        echo "========================================"
        echo ""
        echo "Running ${#pids[@]} actions in parallel..."
        echo "========================================"
    fi
    
    # Wait for all background processes and collect results
    local total_success=0
    local total_failure=0
    local -a failed_commands=()
    
    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local cmd_description="${command_descriptions[$i]}"
        
        if wait "$pid"; then
            ((total_success++))
        else
            ((total_failure++))
            failed_commands+=("$cmd_description")
        fi
    done
    
    # Only show summary if more than one action was executed
    if [[ "$is_single_action" == "false" ]]; then
        echo ""
        echo "========================================"
        echo "CI Execution Summary (Parallel):"
        echo "Commands executed: ${#pids[@]}"
        echo "✅ Successful operations: $total_success"
        if [[ $total_failure -gt 0 ]]; then
            echo "❌ Failed operations: $total_failure"
            echo "Failed commands:"
            for failed_cmd in "${failed_commands[@]}"; do
                echo "  - $failed_cmd"
            done
            exit 1
        else
            echo "🎉 All operations completed successfully"
            exit 0
        fi
    else
        # Single action: just exit with appropriate code
        if [[ $total_failure -gt 0 ]]; then
            exit 1
        else
            exit 0
        fi
    fi
}

# Function to match applications using fuzzy patterns
match_apps_fuzzy() {
    local pattern="$1"
    local -a matched_apps=()
    
    # Split comma-separated patterns
    IFS=',' read -ra patterns <<< "$pattern"
    
    for pat in "${patterns[@]}"; do
        # Trim whitespace
        pat=$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        for app in "${APPS[@]}"; do
            # Check if already matched
            local already_matched=false
            if [[ ${#matched_apps[@]} -gt 0 ]]; then
                for matched in "${matched_apps[@]}"; do
                    if [[ "$matched" == "$app" ]]; then
                        already_matched=true
                        break
                    fi
                done
            fi
            
            if [[ "$already_matched" == "false" ]]; then
                # Support different matching patterns
                if [[ "$pat" == "$app" ]]; then
                    # Exact match
                    matched_apps+=("$app")
                elif [[ "$pat" == *"*"* ]]; then
                    # Wildcard pattern matching
                    if [[ "$app" == $pat ]]; then
                        matched_apps+=("$app")
                    fi
                elif [[ "${app,,}" == *"${pat,,}"* ]]; then
                    # Case-insensitive substring match
                    matched_apps+=("$app")
                fi
            fi
        done
    done
    
    printf '%s\n' "${matched_apps[@]}"
}

# Function to match actions using fuzzy patterns
match_actions_fuzzy() {
    local pattern="$1"
    local app="$2"
    local matched_actions=()
    local available_actions=()

    # Get available actions for this app from the generic action list
    local actions="${APP_ACTION_LIST[$app]:-}"
    if [[ -n "$actions" ]]; then
        read -r -a available_actions <<< "$actions"
    fi

    if [[ "$pattern" == "all" ]]; then
        # Return all available actions for "all"
        matched_actions=("${available_actions[@]}")
    else
        # Split comma-separated patterns
        local patterns=()
        IFS=',' read -r -a patterns <<< "$pattern"

        for pat in "${patterns[@]}"; do
            # Trim whitespace
            pat=$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            for action in "${available_actions[@]}"; do
                # Check if already matched
                local already_matched=false
                if [[ ${#matched_actions[@]} -gt 0 ]]; then
                    for matched in "${matched_actions[@]}"; do
                        if [[ "$matched" == "$action" ]]; then
                            already_matched=true
                            break
                        fi
                    done
                fi

                if [[ "$already_matched" == "false" ]]; then
                    # Support different matching patterns
                    if [[ "$pat" == "$action" ]]; then
                        # Exact match
                        matched_actions+=("$action")
                    elif [[ "$pat" == *"*"* ]]; then
                        # Wildcard pattern matching
                        if [[ "$action" == $pat ]]; then
                            matched_actions+=("$action")
                        fi
                    elif [[ "${action,,}" == *"${pat,,}"* ]]; then
                        # Case-insensitive substring match
                        matched_actions+=("$action")
                    fi
                fi
            done
        done
    fi

    if [[ ${#matched_actions[@]} -gt 0 ]]; then
        printf '%s\n' "${matched_actions[@]}"
    fi
}

# Main function
main() {
    # Parse the configuration file first
    print_color "$BLUE" "Loading configuration from: $CONFIG_FILE"
    parse_config

    if [[ -n "$CONTAINER_COMMAND" ]]; then
        if [[ $CLI_CONTAINER_OVERRIDE -eq 1 ]]; then
            print_color "$PURPLE" "Container mode enabled using CLI override: $CONTAINER_COMMAND"
        else
            print_color "$PURPLE" "Container mode enabled using: $CONTAINER_COMMAND"
        fi
    elif [[ $CLI_CONTAINER_OVERRIDE -eq 1 ]]; then
        if [[ -n "$CONFIG_CONTAINER_COMMAND" ]]; then
            print_color "$YELLOW" "Container command overridden via --container (original: $CONFIG_CONTAINER_COMMAND)"
        else
            print_color "$YELLOW" "Container command overridden via --container"
        fi
    fi

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
            echo "Actions are user-defined in your configuration file"
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
