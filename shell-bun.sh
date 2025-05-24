#!/bin/bash

# Shell-Bun - Interactive build environment script
# Usage: ./shell-bun.sh [config-file]

set -euo pipefail

# Configuration file path
CONFIG_FILE="${1:-build-config.txt}"

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
declare -a SELECTED_ITEMS=()

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
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
    echo
    print_color "$CYAN" "=== $app ==="
    echo "Build (Host):   ${APP_BUILD_HOST[$app]:-'Not configured'}"
    echo "Build (Target): ${APP_BUILD_TARGET[$app]:-'Not configured'}"
    echo "Run (Host):     ${APP_RUN_HOST[$app]:-'Not configured'}"
    echo "Clean:          ${APP_CLEAN[$app]:-'Not configured'}"
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
    
    log_execution "$app" "$action_name" "start"
    
    # Execute the command
    if eval "$command" >/dev/null 2>&1; then
        log_execution "$app" "$action_name" "success"
        return 0
    else
        log_execution "$app" "$action_name" "error"
        return 1
    fi
}

# Function to execute multiple commands in parallel
execute_parallel() {
    local -a pids=()
    local -a commands=()
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
        fi
    done
    
    # Wait for all background processes
    local success_count=0
    local failure_count=0
    
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done
    
    echo
    print_color "$BOLD" "📊 Execution Summary:"
    print_color "$GREEN" "✅ Successful: $success_count"
    if [[ $failure_count -gt 0 ]]; then
        print_color "$RED" "❌ Failed: $failure_count"
    fi
    echo
    echo "Press Enter to continue..."
    read
}

# Function to check if item is selected
is_selected() {
    local item="$1"
    for selected in "${SELECTED_ITEMS[@]}"; do
        [[ "$selected" == "$item" ]] && return 0
    done
    return 1
}

# Function to toggle selection
toggle_selection() {
    local item="$1"
    local -a new_selected=()
    local found=false
    
    for selected in "${SELECTED_ITEMS[@]}"; do
        if [[ "$selected" == "$item" ]]; then
            found=true
        else
            new_selected+=("$selected")
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        new_selected+=("$item")
    fi
    
    SELECTED_ITEMS=("${new_selected[@]}")
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

# Function to display unified menu
show_unified_menu() {
    local -a menu_items=()
    local selected=0
    local filter=""
    
    # Build menu items
    for app in "${APPS[@]}"; do
        [[ -n "${APP_BUILD_HOST[$app]:-}" ]] && menu_items+=("$app - Build (Host)")
        [[ -n "${APP_BUILD_TARGET[$app]:-}" ]] && menu_items+=("$app - Build (Target)")
        [[ -n "${APP_RUN_HOST[$app]:-}" ]] && menu_items+=("$app - Run (Host)")
        [[ -n "${APP_CLEAN[$app]:-}" ]] && menu_items+=("$app - Clean")
        menu_items+=("$app - Show Details")
    done
    
    while true; do
        clear
        print_color "$BLUE" "╔══════════════════════════════════════════╗"
        print_color "$BLUE" "║                Shell-Bun                 ║"
        print_color "$BLUE" "╚══════════════════════════════════════════╝"
        echo
        print_color "$CYAN" "Navigation: ↑/↓ arrows | Type: filter | Space: select | Enter: execute | 'q': quit"
        print_color "$CYAN" "Shortcuts: 'a': select all | 'n': select none | 'r': run selected"
        echo
        
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
            
            # Check if selected for execution
            if is_selected "$item"; then
                suffix=" ${GREEN}[✓]${NC}"
            fi
            
            # Check if currently highlighted
            if [[ $i -eq $selected ]] && [[ ${#filtered[@]} -gt 0 ]]; then
                prefix="${GREEN}► "
                print_color "$GREEN" "${prefix}${item}${suffix}"
            else
                echo -e "  ${item}${suffix}"
            fi
        done
        
        if [[ ${#filtered[@]} -eq 0 ]]; then
            print_color "$RED" "No matches found"
        fi
        
        # Read user input
        read -rsn1 key
        
        case "$key" in
            $'\x1b') # Escape sequence (arrow keys)
                read -rsn2 arrows
                case "$arrows" in
                    '[A') # Up arrow
                        if [[ $selected -gt 0 ]]; then
                            ((selected--))
                        fi
                        ;;
                    '[B') # Down arrow
                        if [[ $selected -lt $((${#filtered[@]} - 1)) ]] && [[ ${#filtered[@]} -gt 0 ]]; then
                            ((selected++))
                        fi
                        ;;
                esac
                ;;
            '') # Enter key
                if [[ ${#filtered[@]} -gt 0 ]]; then
                    local selection="${filtered[$selected]}"
                    if [[ "$selection" =~ ^(.+)\ -\ Show\ Details$ ]]; then
                        local app="${BASH_REMATCH[1]}"
                        clear
                        show_app_details "$app"
                        echo "Press Enter to continue..."
                        read
                    else
                        # Execute single command immediately
                        if [[ "$selection" =~ ^(.+)\ -\ (.+)$ ]]; then
                            local app="${BASH_REMATCH[1]}"
                            local action="${BASH_REMATCH[2]}"
                            clear
                            echo "Executing: $selection"
                            echo "Press Enter to continue, Ctrl+C to cancel..."
                            read
                            case "$action" in
                                "Build (Host)")
                                    execute_command "$app" "build_host"
                                    ;;
                                "Build (Target)")
                                    execute_command "$app" "build_target"
                                    ;;
                                "Run (Host)")
                                    execute_command "$app" "run_host"
                                    ;;
                                "Clean")
                                    execute_command "$app" "clean"
                                    ;;
                            esac
                            echo
                            echo "Press Enter to return to menu..."
                            read
                        fi
                    fi
                fi
                ;;
            ' ') # Space bar - toggle selection
                if [[ ${#filtered[@]} -gt 0 ]]; then
                    local selection="${filtered[$selected]}"
                    if [[ ! "$selection" =~ -\ Show\ Details$ ]]; then
                        toggle_selection "$selection"
                    fi
                fi
                ;;
            'q'|'Q') # Quit
                print_color "$YELLOW" "Goodbye!"
                exit 0
                ;;
            'a'|'A') # Select all
                select_all
                ;;
            'n'|'N') # Select none
                select_none
                ;;
            'r'|'R') # Run selected
                execute_parallel
                ;;
            $'\x7f'|$'\x08') # Backspace
                filter="${filter%?}"
                selected=0
                ;;
            [[:print:]]) # Regular character
                filter="$filter$key"
                selected=0
                ;;
        esac
    done
}

# Main function
main() {
    # Check if we're in a terminal that supports colors and arrow keys
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        print_color "$RED" "Error: This script requires an interactive terminal"
        exit 1
    fi
    
    print_color "$BLUE" "Loading configuration from: $CONFIG_FILE"
    parse_config
    
    print_color "$GREEN" "Found ${#APPS[@]} applications: ${APPS[*]}"
    echo
    
    show_unified_menu
}

# Run main function
main "$@" 