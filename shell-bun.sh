#!/bin/bash

# Shell-Bun - Interactive build environment script
# Usage: ./shell-bun.sh [config-file]
# Usage: ./shell-bun.sh --debug [config-file]

set -uo pipefail

# Debug mode
DEBUG_MODE=0

# Check for debug mode
if [[ "${1:-}" == "--debug" ]] || [[ "${2:-}" == "--debug" ]]; then
    DEBUG_MODE=1
    if [[ "${1:-}" == "--debug" ]]; then
        CONFIG_FILE="${2:-build-config.txt}"
    else
        CONFIG_FILE="${1:-build-config.txt}"
    fi
else
    CONFIG_FILE="${1:-build-config.txt}"
fi

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
        print_color "$CYAN" "Navigation: ↑/↓ arrows | Type: filter | Space: select | Enter: execute | ESC: quit"
        print_color "$CYAN" "Shortcuts: '+': select all | '-': clear selections | Tab: run selected"
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
            local is_currently_selected=false
            local is_highlighted=false
            
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
            if [[ "$is_currently_selected" == "true" ]]; then
                # Selected items: entire line in green
                print_color "$GREEN" "${prefix}${item}${suffix}"
            elif [[ "$is_highlighted" == "true" ]]; then
                # Highlighted but not selected: green arrow and text
                print_color "$GREEN" "${prefix}${item}${suffix}"
            else
                # Normal items: default color
                echo "  ${item}${suffix}"
            fi
        done
        
        if [[ ${#filtered[@]} -eq 0 ]]; then
            print_color "$RED" "No matches found"
        fi
        
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
                else
                    # Plain ESC key or unknown sequence - quit
                    debug_log "ESC key pressed - quitting"
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
                    else
                        # Always execute the currently highlighted command (ignore selections)
                        debug_log "Executing highlighted command with summary (Enter always executes current item)"
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
                    else
                        debug_log "Cannot select 'Show Details' item"
                    fi
                else
                    debug_log "No filtered items available"
                fi
                action_taken=true
                ;;
            $'\n'|$'\r') # Enter key - execute highlighted item only
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
                    else
                        # Always execute the currently highlighted command (ignore selections)
                        debug_log "Executing highlighted command with summary (Enter always executes current item)"
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
                        fi
                    fi
                fi
                action_taken=true
                ;;
            '+') # Plus - select all
                debug_log "Plus key pressed - selecting all"
                select_all
                action_taken=true
                ;;
            '-') # Minus - clear selections
                debug_log "Minus key pressed - clearing selections"
                select_none
                action_taken=true
                ;;
            $'\x7f'|$'\x08') # Backspace
                debug_log "Backspace pressed"
                filter="${filter%?}"
                selected=0
                action_taken=true
                ;;
            $'\t') # Tab key - run selected items
                debug_log "TAB key pressed - running selected items"
                execute_parallel
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

# Main function
main() {
    # Check if we're in a terminal that supports colors and arrow keys
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        print_color "$RED" "Error: This script requires an interactive terminal"
        exit 1
    fi
    

    
    print_color "$BLUE" "Loading configuration from: $CONFIG_FILE"
    parse_config
    
    print_color "$GREEN" "Found ${#APPS[@]} applications"
    if [[ ${#APPS[@]} -gt 0 ]]; then
        echo "Applications: ${APPS[*]}"
    fi
    echo
    
    show_unified_menu
}

# Run main function
main "$@" 