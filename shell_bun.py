#!/usr/bin/env python3

#
# Shell-Bun - Interactive build environment script
# Version: 1.4.1
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

import argparse
import fnmatch
import os
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import curses
    CURSES_AVAILABLE = True
except ImportError:
    CURSES_AVAILABLE = False

try:
    from textual.app import App, ComposeResult
    from textual.widgets import Input, ListView, ListItem, Label, Header, Footer
    from textual.containers import Container, Vertical, Horizontal
    from textual.binding import Binding
    from textual.message import Message
    TEXTUAL_AVAILABLE = True
except ImportError:
    TEXTUAL_AVAILABLE = False

# Version information
VERSION = "1.4.1"

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    NC = '\033[0m'  # No Color


def print_color(color: str, message: str) -> None:
    """Print colored output."""
    print(f"{color}{message}{Colors.NC}")


class Config:
    """Configuration management."""
    
    def __init__(self):
        self.apps: List[str] = []
        self.app_actions: Dict[str, str] = {}  # Key: "app:action", Value: "command"
        self.app_action_list: Dict[str, List[str]] = {}  # Key: "app", Value: list of actions
        self.app_working_dir: Dict[str, str] = {}
        self.app_log_dir: Dict[str, str] = {}
        self.global_log_dir: str = ""
        self.config_container_command: str = ""
        self.container_command: str = ""
        self.container_env_file = os.environ.get("SHELL_BUN_CONTAINER_MARKER_FILE", "/run/.containerenv")
    
    def parse_config(self, config_file: str) -> None:
        """Parse configuration file."""
        if not os.path.isfile(config_file):
            print_color(Colors.RED, f"Error: Configuration file '{config_file}' not found!")
            print("Please create a configuration file or specify a different one.")
            sys.exit(1)
        
        # Read file manually to handle global settings before sections
        # (configparser doesn't support this natively)
        with open(config_file, 'r') as f:
            current_app = None
            for line in f:
                # Remove leading/trailing whitespace
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Check for section header
                if line.startswith('[') and line.endswith(']'):
                    current_app = line[1:-1]
                    if current_app not in self.apps:
                        self.apps.append(current_app)
                        self.app_action_list[current_app] = []
                elif '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    if current_app is None:
                        # Global setting (before any section)
                        if key == "log_dir":
                            self.global_log_dir = value
                        elif key == "container":
                            self.config_container_command = value
                    else:
                        # App-specific setting
                        if key == "working_dir":
                            self.app_working_dir[current_app] = value
                        elif key == "log_dir":
                            self.app_log_dir[current_app] = value
                        else:
                            # Generic action
                            self.app_actions[f"{current_app}:{key}"] = value
                            if key not in self.app_action_list[current_app]:
                                self.app_action_list[current_app].append(key)
        
        if not self.apps:
            print_color(Colors.RED, "Error: No applications found in configuration file!")
            sys.exit(1)
    
    def set_container_command(self, cli_override: Optional[str] = None) -> None:
        """Set the effective container command."""
        if cli_override is not None:
            self.container_command = cli_override
        elif os.path.isfile(self.container_env_file) and self.config_container_command:
            print_color(Colors.YELLOW, 
                       f"Detected {self.container_env_file} - ignoring configured container command: {self.config_container_command}")
            self.container_command = ""
        else:
            self.container_command = self.config_container_command


class Executor:
    """Command execution management."""
    
    def __init__(self, config: Config, debug_mode: bool = False):
        self.config = config
        self.debug_mode = debug_mode
        self.script_dir = Path(__file__).parent.absolute()
    
    def debug_log(self, message: str) -> None:
        """Log debug message."""
        if self.debug_mode:
            with open("debug.log", "a") as f:
                f.write(f"[DEBUG] {message}\n")
    
    def generate_log_file_path(self, app: str, action: str) -> str:
        """Generate log file path."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Get log directory - check app-specific first, then global, then default
        log_dir = self.config.app_log_dir.get(app, "")
        if not log_dir and self.config.global_log_dir:
            log_dir = self.config.global_log_dir
        if not log_dir:
            log_dir = str(self.script_dir / "logs")
        
        # Expand tilde
        log_dir = os.path.expanduser(log_dir)
        
        # Make relative paths relative to script directory
        if not os.path.isabs(log_dir):
            log_dir = str(self.script_dir / log_dir)
        
        # Create log directory if it doesn't exist
        try:
            os.makedirs(log_dir, exist_ok=True)
        except OSError:
            print(f"Warning: Cannot create log directory '{log_dir}', using script directory")
            log_dir = str(self.script_dir)
        
        # Generate log file name
        log_file = os.path.join(log_dir, f"{timestamp}_{app}_{action}.log")
        return log_file
    
    def log_execution(self, app: str, action: str, status: str, command: str = "") -> None:
        """Log execution status."""
        if status == "start":
            if command:
                print_color(Colors.CYAN, f"🚀 Starting: {app} - {action}: {Colors.DIM}{command}{Colors.NC}{Colors.CYAN}")
            else:
                print_color(Colors.CYAN, f"🚀 Starting: {app} - {action}")
        elif status == "success":
            print_color(Colors.GREEN, f"✅ Completed: {app} - {action}")
        elif status == "error":
            print_color(Colors.RED, f"❌ Failed: {app} - {action}")
    
    def execute_command(self, app: str, action: str, show_output: bool = False, 
                       ci_mode: bool = False) -> Tuple[int, Optional[str]]:
        """Execute a command."""
        command_key = f"{app}:{action}"
        command = self.config.app_actions.get(command_key)
        
        if not command:
            self.log_execution(app, action, "error")
            print_color(Colors.RED, f"Error: No command configured for '{action}' in {app}")
            return 1, None
        
        # Get working directory
        working_dir = self.config.app_working_dir.get(app, "")
        working_dir_for_container = working_dir
        
        if self.config.container_command:
            # Container mode: use working_dir as-is
            if not working_dir_for_container:
                working_dir_for_container = ""
        else:
            # Non-container mode: resolve paths relative to script directory
            if not working_dir:
                working_dir = str(self.script_dir)
            else:
                working_dir = os.path.expanduser(working_dir)
                if not os.path.isabs(working_dir):
                    working_dir = str(self.script_dir / working_dir)
            
            # Check if working directory exists (only for non-container mode)
            if not os.path.isdir(working_dir):
                self.log_execution(app, action, "error")
                print_color(Colors.RED, f"Error: Working directory '{working_dir}' does not exist for {app}")
                return 1, None
        
        # Generate log file path (unless in CI mode)
        log_file = None
        if not ci_mode:
            log_file = self.generate_log_file_path(app, action)
        
        # Build the full command that will be executed
        if self.config.container_command:
            if working_dir_for_container:
                container_cmd = f"cd {shlex.quote(working_dir_for_container)} && {command}"
                full_command_display = f"{self.config.container_command} bash -lc {shlex.quote(container_cmd)}"
            else:
                full_command_display = f"{self.config.container_command} bash -lc {shlex.quote(command)}"
        else:
            full_command_display = f"bash -c {shlex.quote(command)}"
        
        self.log_execution(app, action, "start", full_command_display)
        
        # Execute the command
        exit_code = 0
        
        try:
            if self.config.container_command:
                # Container mode
                if working_dir_for_container:
                    container_cmd = f"cd {shlex.quote(working_dir_for_container)} && {command}"
                    cmd = ["bash", "-c", f"{self.config.container_command} bash -lc {shlex.quote(container_cmd)}"]
                else:
                    cmd = ["bash", "-c", f"{self.config.container_command} bash -lc {shlex.quote(command)}"]
            else:
                # Non-container mode
                cmd = ["bash", "-c", command]
            
            if ci_mode:
                # CI mode: just print to terminal
                result = subprocess.run(cmd, cwd=working_dir if not self.config.container_command else None,
                                      capture_output=False, text=True)
                exit_code = result.returncode
            elif show_output:
                # Interactive single execution: show output and log to file
                with open(log_file, 'w') as log_f:
                    result = subprocess.run(cmd, cwd=working_dir if not self.config.container_command else None,
                                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    output = result.stdout
                    log_f.write(output)
                    print(output, end='')
                exit_code = result.returncode
            else:
                # Interactive parallel execution: only log to file
                with open(log_file, 'w') as log_f:
                    result = subprocess.run(cmd, cwd=working_dir if not self.config.container_command else None,
                                          stdout=log_f, stderr=subprocess.STDOUT, text=True)
                exit_code = result.returncode
            
            if exit_code == 0:
                self.log_execution(app, action, "success")
                return 0, log_file
            else:
                self.log_execution(app, action, "error")
                if ci_mode:
                    print_color(Colors.RED, f"Command failed with exit code {exit_code}")
                return exit_code, log_file
        
        except Exception as e:
            self.log_execution(app, action, "error")
            print_color(Colors.RED, f"Error executing command: {e}")
            return 1, log_file


class PatternMatcher:
    """Pattern matching for CI mode."""
    
    @staticmethod
    def match_apps_fuzzy(pattern: str, apps: List[str]) -> List[str]:
        """Match applications using fuzzy patterns."""
        matched_apps = []
        
        # Split comma-separated patterns
        patterns = [p.strip() for p in pattern.split(',')]
        
        for pat in patterns:
            for app in apps:
                if app in matched_apps:
                    continue
                
                # Exact match
                if pat == app:
                    matched_apps.append(app)
                # Wildcard pattern
                elif '*' in pat:
                    if fnmatch.fnmatch(app, pat):
                        matched_apps.append(app)
                # Case-insensitive substring match
                elif pat.lower() in app.lower():
                    matched_apps.append(app)
        
        return matched_apps
    
    @staticmethod
    def match_actions_fuzzy(pattern: str, actions: List[str]) -> List[str]:
        """Match actions using fuzzy patterns."""
        matched_actions = []
        
        if pattern == "all":
            return actions
        
        # Split comma-separated patterns
        patterns = [p.strip() for p in pattern.split(',')]
        
        for pat in patterns:
            for action in actions:
                if action in matched_actions:
                    continue
                
                # Exact match
                if pat == action:
                    matched_actions.append(action)
                # Wildcard pattern
                elif '*' in pat:
                    if fnmatch.fnmatch(action, pat):
                        matched_actions.append(action)
                # Case-insensitive substring match
                elif pat.lower() in action.lower():
                    matched_actions.append(action)
        
        return matched_actions


class CIMode:
    """CI mode execution."""
    
    def __init__(self, config: Config, executor: Executor):
        self.config = config
        self.executor = executor
        self.matcher = PatternMatcher()
    
    def execute(self, app_pattern: str, action_pattern: str) -> None:
        """Execute commands in CI mode."""
        # Match applications
        matched_apps = self.matcher.match_apps_fuzzy(app_pattern, self.config.apps)
        
        if not matched_apps:
            print(f"Error: No applications found matching pattern '{app_pattern}'")
            print(f"Available applications: {' '.join(self.config.apps)}")
            print("")
            print("Pattern matching supports:")
            print("  - Exact names: MyWebApp")
            print("  - Wildcards: *Web*, API*")
            print("  - Substrings: web, api")
            print("  - Multiple: MyWebApp,API*,mobile")
            sys.exit(1)
        
        # Prepare parallel execution
        futures = []
        command_descriptions = []
        found_any_action = False
        
        with ThreadPoolExecutor() as executor:
            # Start all matched commands in parallel
            for app in matched_apps:
                # Match actions for this app
                actions = self.config.app_action_list.get(app, [])
                matched_actions = self.matcher.match_actions_fuzzy(action_pattern, actions)
                
                if not matched_actions:
                    print(f"Warning: No actions found for '{app}' matching pattern '{action_pattern}'")
                    print(f"Available actions for {app}: {' '.join(actions)}")
                    continue
                
                found_any_action = True
                
                # Start each action in parallel
                for action in matched_actions:
                    future = executor.submit(self.executor.execute_command, app, action, False, True)
                    futures.append(future)
                    command_descriptions.append(f"{app} - {action}")
            
            # Check if any actions were found
            if not found_any_action or not futures:
                print("")
                print(f"Error: No actions found matching pattern '{action_pattern}'")
                sys.exit(1)
            
            # Determine if this is a single action execution
            is_single_action = len(futures) == 1
            
            # For multiple actions, show verbose header
            if not is_single_action:
                print("Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)")
                print(f"App pattern: '{app_pattern}'")
                print(f"Action pattern: '{action_pattern}'")
                print(f"Matched apps: {' '.join(matched_apps)}")
                print("========================================")
                print("")
                print(f"Running {len(futures)} actions in parallel...")
                print("========================================")
            
            # Wait for all futures and collect results
            total_success = 0
            total_failure = 0
            failed_commands = []
            
            for future in as_completed(futures):
                exit_code, _ = future.result()
                idx = futures.index(future)
                cmd_description = command_descriptions[idx]
                
                if exit_code == 0:
                    total_success += 1
                else:
                    total_failure += 1
                    failed_commands.append(cmd_description)
            
            # Only show summary if more than one action was executed
            if not is_single_action:
                print("")
                print("========================================")
                print("CI Execution Summary (Parallel):")
                print(f"Commands executed: {len(futures)}")
                print(f"✅ Successful operations: {total_success}")
                if total_failure > 0:
                    print(f"❌ Failed operations: {total_failure}")
                    print("Failed commands:")
                    for failed_cmd in failed_commands:
                        print(f"  - {failed_cmd}")
                    sys.exit(1)
                else:
                    print("🎉 All operations completed successfully")
                    sys.exit(0)
            else:
                # Single action: just exit with appropriate code
                if total_failure > 0:
                    sys.exit(1)
                else:
                    sys.exit(0)


if TEXTUAL_AVAILABLE:
    class MenuItem(ListItem):
        """Custom list item for menu entries."""
        
        def __init__(self, item_text: str, is_selected: bool = False):
            display = item_text
            if is_selected:
                display += " [✓]"
            label = Label(display)
            super().__init__(label)
            self.item_text = item_text
            self.is_selected = is_selected
            self.label = label  # Store reference to the Label
        
        def update_display(self):
            """Update the display text."""
            display = self.item_text
            if self.is_selected:
                display += " [✓]"
            self.label.update(display)


if TEXTUAL_AVAILABLE:
    class ShellBunApp(App):
        """Textual-based interactive menu for Shell-Bun."""
        
        CSS = """
        Screen {
            background: $surface;
        }
        
        .header-box {
            text-align: center;
            padding: 1;
            background: $primary;
            color: $text;
            text-style: bold;
        }
        
        .help-text {
            padding: 1;
            background: $panel;
            text-style: italic;
        }
        
        .status-bar {
            padding: 1;
            background: $panel;
        }
        
        #filter-input {
            border: solid $primary;
            padding: 1;
        }
        
        #menu-list {
            height: 1fr;
        }
        
        ListItem {
            padding: 1;
        }
        
        ListItem.--highlight {
            background: $primary 20%;
        }
        
        ListItem.--selected {
            background: $primary;
            color: $text;
        }
        """
        
        BINDINGS = [
            Binding("q", "quit", "Quit", priority=True),
            Binding("escape", "quit", "Quit", priority=True),
            Binding("space", "toggle_selection", "Toggle Selection"),
            Binding("+", "select_all", "Select All Visible"),
            Binding("-", "deselect_all", "Deselect All Visible"),
            Binding("delete", "clear_filter", "Clear Filter"),
        ]
        
        def action_quit(self) -> None:
            """Quit the application."""
            self.exit(None)
        
        def __init__(self, config: Config, executor: Executor, **kwargs):
            super().__init__(**kwargs)
            self.config = config
            self.executor = executor
            self.selected_items: List[str] = []
            self.menu_items: List[str] = []
            
            # Build menu items
            for app in config.apps:
                actions = config.app_action_list.get(app, [])
                for action in actions:
                    self.menu_items.append(f"{app} - {action}")
                self.menu_items.append(f"{app} - Show Details")
            
            self.filtered_items = self.menu_items
        
        def compose(self) -> ComposeResult:
            """Create child widgets for the app."""
            yield Header(show_clock=False)
            yield Vertical(
                Label("╔══════════════════════════════════════════════════════════════════════════════════════╗", classes="header-box"),
                Label("║          Shell-Bun by Fredrik Reveny (https://github.com/Chetic/shell-bun/)          ║", classes="header-box"),
                Label("╚══════════════════════════════════════════════════════════════════════════════════════╝", classes="header-box"),
                Label("Navigation: ↑/↓ arrows | PgUp/PgDn: page | Type: filter | Space: select | Enter: execute | ESC: quit", classes="help-text"),
                Label("Shortcuts: '+' select visible | '-' deselect visible | Delete: clear filter", classes="help-text"),
                Input(placeholder="Type to filter...", id="filter-input"),
                Label("Selected: none", id="selection-status", classes="status-bar"),
                ListView(id="menu-list"),
            )
            yield Footer()
        
        def on_mount(self) -> None:
            """Called when app starts."""
            self.update_menu_list()
            # Focus on ListView so arrow keys work
            self.query_one("#menu-list", ListView).focus()
        
        def update_menu_list(self) -> None:
            """Update the menu list with filtered items."""
            list_view = self.query_one("#menu-list", ListView)
            list_view.clear()
            
            for item in self.filtered_items:
                is_selected = item in self.selected_items
                menu_item = MenuItem(item, is_selected)
                menu_item.item_data = item
                list_view.append(menu_item)
        
        def on_input_changed(self, event: Input.Changed) -> None:
            """Handle filter input changes."""
            filter_text = event.value.lower()
            if not filter_text:
                self.filtered_items = self.menu_items
            else:
                self.filtered_items = [item for item in self.menu_items 
                                     if filter_text in item.lower()]
            self.update_menu_list()
            self.update_selection_status()
            # Return focus to ListView after filtering
            self.query_one("#menu-list", ListView).focus()
        
        def update_selection_status(self) -> None:
            """Update the selection status label."""
            status_label = self.query_one("#selection-status", Label)
            count = len(self.selected_items)
            if count > 0:
                status_label.update(f"Selected: {count} items")
            else:
                status_label.update("Selected: none")
        
        def action_toggle_selection(self) -> None:
            """Toggle selection of current item."""
            list_view = self.query_one("#menu-list", ListView)
            highlighted = list_view.highlighted_child
            if highlighted and hasattr(highlighted, 'item_data'):
                item = highlighted.item_data
                if not item.endswith(" - Show Details"):
                    if item in self.selected_items:
                        self.selected_items.remove(item)
                    else:
                        self.selected_items.append(item)
                    self.update_menu_list()
                    self.update_selection_status()
        
        def action_select_all(self) -> None:
            """Select all filtered items."""
            for item in self.filtered_items:
                if not item.endswith(" - Show Details") and item not in self.selected_items:
                    self.selected_items.append(item)
            self.update_menu_list()
            self.update_selection_status()
        
        def action_deselect_all(self) -> None:
            """Deselect all filtered items."""
            for item in self.filtered_items:
                if item in self.selected_items:
                    self.selected_items.remove(item)
            self.update_menu_list()
            self.update_selection_status()
        
        def action_clear_filter(self) -> None:
            """Clear the filter."""
            filter_input = self.query_one("#filter-input", Input)
            filter_input.value = ""
            self.filtered_items = self.menu_items
            self.update_menu_list()
            # Return focus to ListView
            self.query_one("#menu-list", ListView).focus()
        
        def on_key(self, event) -> None:
            """Handle key events to allow typing to filter."""
            # If it's a printable character and ListView has focus, move focus to Input
            if event.character and event.character.isprintable() and len(event.character) == 1:
                list_view = self.query_one("#menu-list", ListView)
                if list_view.has_focus:
                    # Move focus to Input and let it handle the character
                    filter_input = self.query_one("#filter-input", Input)
                    filter_input.focus()
                    # The character will be handled by the Input widget
            # For other keys (arrows, etc.), let them propagate normally by not stopping the event
        
        def on_list_view_selected(self, event: ListView.Selected) -> None:
            """Handle item selection (Enter key)."""
            if not hasattr(event.item, 'item_data'):
                return
            
            item = event.item.item_data
            self.exit_with_result(item)
        
        def exit_with_result(self, item: str) -> None:
            """Exit the app with a result to process."""
            self.exit(item)


class InteractiveMenu:
    """Wrapper class for the Textual-based interactive menu."""
    
    def __init__(self, config: Config, executor: Executor):
        self.config = config
        self.executor = executor
    
    def show_app_details(self, app: str) -> None:
        """Show application details."""
        working_dir = self.config.app_working_dir.get(app, "")
        log_dir = self.config.app_log_dir.get(app, "")
        script_dir = Path(__file__).parent.absolute()
        
        if not working_dir:
            working_dir = f"{script_dir} (default)"
        else:
            working_dir = os.path.expanduser(working_dir)
            if not os.path.isabs(working_dir):
                working_dir = str(script_dir / working_dir)
        
        # Determine effective log directory
        if log_dir:
            log_dir = os.path.expanduser(log_dir)
            if not os.path.isabs(log_dir):
                log_dir = str(script_dir / log_dir)
            log_dir = f"{log_dir} (app-specific)"
        elif self.config.global_log_dir:
            log_dir = self.config.global_log_dir
            log_dir = os.path.expanduser(log_dir)
            if not os.path.isabs(log_dir):
                log_dir = str(script_dir / log_dir)
            log_dir = f"{log_dir} (global)"
        else:
            log_dir = f"{script_dir}/logs (default)"
        
        print()
        print_color(Colors.CYAN, f"=== {app} ===")
        print(f"Working Dir:    {working_dir}")
        print(f"Log Dir:        {log_dir}")
        
        if self.config.container_command:
            print(f"Container:      {self.config.container_command}")
        else:
            print("Container:      (none - runs on host)")
        
        print()
        print_color(Colors.YELLOW, "Available Actions:")
        
        actions = self.config.app_action_list.get(app, [])
        if not actions:
            print("  No actions configured")
        else:
            for action in actions:
                command = self.config.app_actions.get(f"{app}:{action}", "")
                print()
                print_color(Colors.CYAN, f"  {action}:")
                print(f"    Command: {command}")
                
                if self.config.container_command:
                    working_dir_for_display = self.config.app_working_dir.get(app, "")
                    if working_dir_for_display:
                        container_cmd = f"cd {shlex.quote(working_dir_for_display)} && {command}"
                        print(f"    Full cmd: {self.config.container_command} bash -lc {shlex.quote(container_cmd)}")
                    else:
                        print(f"    Full cmd: {self.config.container_command} bash -lc {shlex.quote(command)}")
                else:
                    print(f"    Full cmd: bash -c {shlex.quote(command)}")
        print()
    
    def execute_single(self, app: str, action: str) -> None:
        """Execute a single command."""
        print_color(Colors.BLUE, f"📦 Executing: {app} - {action}")
        print()
        
        exit_code, log_file = self.executor.execute_command(app, action, show_output=True)
        
        print()
        input("Press Enter to continue...")
    
    def execute_parallel(self, selected_items: List[str]) -> None:
        """Execute multiple commands in parallel."""
        if not selected_items:
            print_color(Colors.YELLOW, "No items selected for execution.")
            return
        
        print_color(Colors.BLUE, f"📦 Executing {len(selected_items)} selected items in parallel...")
        print()
        
        execution_results = []
        futures = []
        log_files = []
        
        with ThreadPoolExecutor() as executor:
            for item in selected_items:
                if item.endswith(" - Show Details"):
                    continue
                
                match = re.match(r"^(.+)\s-\s(.+)$", item)
                if not match:
                    continue
                
                app = match.group(1)
                action = match.group(2)
                
                # Generate log file before starting
                log_file = self.executor.generate_log_file_path(app, action)
                log_files.append(log_file)
                
                # Start command in background
                future = executor.submit(self.executor.execute_command, app, action, False, False)
                futures.append(future)
                execution_results.append((item, log_file))
            
            # Wait for all futures
            success_count = 0
            failure_count = 0
            failed_commands = []
            
            for i, future in enumerate(as_completed(futures)):
                exit_code, _ = future.result()
                item, log_file = execution_results[i]
                
                if exit_code == 0:
                    success_count += 1
                    execution_results[i] = (f"SUCCESS: {item} ({log_file})", log_file)
                else:
                    failure_count += 1
                    failed_commands.append(item)
                    execution_results[i] = (f"FAILED: {item} ({log_file})", log_file)
            
            # Show summary if more than one action
            if len(futures) > 1:
                print()
                print_color(Colors.BOLD, "📊 Execution Summary:")
                print_color(Colors.GREEN, f"✅ Successful: {success_count}")
                if failure_count > 0:
                    print_color(Colors.RED, f"❌ Failed: {failure_count}")
                    print_color(Colors.RED, "Failed commands:")
                    for failed_cmd in failed_commands:
                        print_color(Colors.RED, f"  - {failed_cmd}")
                print()
        
        # Show log viewer
        self.show_log_viewer(execution_results)
    
    def show_log_viewer(self, results: List[Tuple[str, str]]) -> None:
        """Show log viewer."""
        if not results:
            return
        
        # Sort results: failed first, then successful
        failed_results = []
        success_results = []
        
        for result, log_file in results:
            if result.startswith("FAILED:"):
                failed_results.append((result, log_file))
            else:
                success_results.append((result, log_file))
        
        sorted_results = failed_results + success_results
        
        if not TEXTUAL_AVAILABLE:
            # Fallback: simple text-based viewer
            print("Log files:")
            for i, (result, log_file) in enumerate(sorted_results, 1):
                print(f"{i}. {result}")
            print()
            choice = input("Enter log number to view (or Enter to continue): ")
            if choice.isdigit():
                idx = int(choice) - 1
                if 0 <= idx < len(sorted_results):
                    _, log_file = sorted_results[idx]
                    if os.path.isfile(log_file):
                        subprocess.run(["less", "+G", log_file])
            return
        
        # Textual-based log viewer
        class LogViewerApp(App):
            CSS = """
            Screen {
                background: $surface;
            }
            
            ListView {
                height: 1fr;
            }
            
            ListItem {
                padding: 1;
            }
            """
            
            BINDINGS = [
                Binding("q", "quit", "Quit"),
                Binding("escape", "quit", "Quit"),
            ]
            
            def __init__(self, results: List[Tuple[str, str]], **kwargs):
                super().__init__(**kwargs)
                self.results = results
            
            def compose(self) -> ComposeResult:
                yield Header(show_clock=False)
                yield Label("📋 Select a log file to view (q to quit, Enter to view)", classes="header-box")
                yield ListView(id="log-list")
                yield Footer()
            
            def on_mount(self) -> None:
                list_view = self.query_one("#log-list", ListView)
                for result, log_file in self.results:
                    item = ListItem(Label(result))
                    item.log_file = log_file
                    list_view.append(item)
            
            def on_list_view_selected(self, event: ListView.Selected) -> None:
                if hasattr(event.item, 'log_file'):
                    log_file = event.item.log_file
                    if os.path.isfile(log_file):
                        self.exit()
                        subprocess.run(["less", "+G", log_file])
        
        try:
            app = LogViewerApp(sorted_results)
            app.run()
        except Exception as e:
            print(f"Error in log viewer: {e}")
            input("Press Enter to continue...")
    
    def run(self) -> None:
        """Run the interactive menu."""
        if not TEXTUAL_AVAILABLE:
            print_color(Colors.RED, "Error: Textual module not available. Interactive mode requires Textual.")
            print("Please install Textual: pip install textual")
            print("Or use --ci mode for non-interactive execution")
            sys.exit(1)
        
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            print_color(Colors.RED, "Error: This script requires an interactive terminal for interactive mode")
            print_color(Colors.YELLOW, "Use --ci mode for non-interactive execution")
            print(f"Example: {sys.argv[0]} --ci MyApp build_host")
            sys.exit(1)
        
        # Create app with reference to this menu for callbacks
        app = ShellBunApp(self.config, self.executor)
        app.menu_wrapper = self  # Store reference for callbacks
        
        try:
            while True:
                result = app.run()
                if result is None:
                    # User quit
                    print_color(Colors.YELLOW, "Goodbye!")
                    break
                
                # Handle the result
                if isinstance(result, str):
                    item = result
                    if item.endswith(" - Show Details"):
                        app_name = item[:-14]
                        self.show_app_details(app_name)
                        input("Press Enter to continue...")
                    else:
                        if app.selected_items:
                            self.execute_parallel(app.selected_items)
                            # After parallel execution, ask if user wants to continue
                            response = input("Press Enter to return to menu, or 'q' to quit: ")
                            if response.lower() == 'q':
                                print_color(Colors.YELLOW, "Goodbye!")
                                break
                        else:
                            match = re.match(r"^(.+)\s-\s(.+)$", item)
                            if match:
                                app_name = match.group(1)
                                action = match.group(2)
                                self.execute_single(app_name, action)
                                # After single execution, return to menu
                                response = input("Press Enter to return to menu, or 'q' to quit: ")
                                if response.lower() == 'q':
                                    print_color(Colors.YELLOW, "Goodbye!")
                                    break
                else:
                    break
        except KeyboardInterrupt:
            print_color(Colors.YELLOW, "Goodbye!")
            sys.exit(0)
        except Exception as e:
            print_color(Colors.RED, f"Error: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Shell-Bun - Interactive build environment script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                         # Use default config (shell-bun.cfg)
  %(prog)s my-config.txt           # Use custom config file
  %(prog)s --debug                 # Enable debug logging
  %(prog)s --container "podman exec ..."   # Override container command
  %(prog)s --ci APP_PATTERN ACTION_PATTERN   # Run actions matching patterns

App pattern examples:
  MyWebApp                    # Exact app name
  *Web*                       # Wildcard: any app containing 'Web'
  API*                        # Wildcard: apps starting with 'API'
  web                         # Substring: apps containing 'web'
  MyWebApp,API*,mobile        # Multiple: comma-separated patterns

Action pattern examples:
  build_host                  # Exact action name
  build*                      # Wildcard: actions starting with 'build'
  *host                       # Wildcard: actions ending with 'host'
  test*,deploy                # Multiple specific actions
  unit                        # Substring: actions containing 'unit'
  all                         # All available actions
        """
    )
    
    parser.add_argument('config_file', nargs='?', default='shell-bun.cfg',
                       help='Configuration file (default: shell-bun.cfg)')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug logging')
    parser.add_argument('--ci', nargs=2, metavar=('APP_PATTERN', 'ACTION_PATTERN'),
                       help='CI mode: run actions matching patterns')
    parser.add_argument('--container', metavar='CMD',
                       help='Override container command for this run')
    parser.add_argument('--version', '-v', action='version', version=f'v{VERSION}')
    
    args = parser.parse_args()
    
    # Parse configuration
    config = Config()
    config.parse_config(args.config_file)
    
    # Set container command
    config.set_container_command(args.container)
    
    if args.container:
        if args.container == "":
            print_color(Colors.YELLOW, "Container command overridden via --container")
        else:
            print_color(Colors.PURPLE, f"Container mode enabled using CLI override: {args.container}")
    elif config.container_command:
        print_color(Colors.PURPLE, f"Container mode enabled using: {config.container_command}")
    
    # Create executor
    executor = Executor(config, args.debug)
    
    # Handle CI mode
    if args.ci:
        app_pattern, action_pattern = args.ci
        ci_mode = CIMode(config, executor)
        ci_mode.execute(app_pattern, action_pattern)
        return
    
    # Interactive mode
    print_color(Colors.BLUE, f"Loading configuration from: {args.config_file}")
    print_color(Colors.GREEN, f"Found {len(config.apps)} applications")
    if config.apps:
        print(f"Applications: {' '.join(config.apps)}")
    print()
    
    menu = InteractiveMenu(config, executor)
    menu.run()


if __name__ == "__main__":
    main()

