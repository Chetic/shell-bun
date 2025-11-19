#!/usr/bin/env node

/**
 * Shell-Bun - Interactive build environment script
 * Version: 1.4.1
 * Copyright (c) 2025, Fredrik Reveny
 * All rights reserved.
 */

const fs = require('fs');
const path = require('path');
const { spawn, exec } = require('child_process');
const { promisify } = require('util');
const ini = require('ini');
const React = require('react');
const { render, Text, Box } = require('ink');
const { Menu } = require('./ui');

const execAsync = promisify(exec);

// Version information
const VERSION = '1.4.1';

// Global state
let DEBUG_MODE = false;
let CI_MODE = false;
let CI_APP = '';
let CI_ACTIONS = '';
let CLI_CONTAINER_OVERRIDE = false;
let CLI_CONTAINER_COMMAND = '';
let CONFIG_FILE = 'shell-bun.cfg';

// Data structures
const apps = [];
const appActions = new Map(); // Key: "app:action", Value: "command"
const appActionList = new Map(); // Key: "app", Value: array of actions
const appWorkingDir = new Map();
const appLogDir = new Map();
let globalLogDir = '';
let configContainerCommand = '';
let containerCommand = '';
const CONTAINER_ENV_FILE = process.env.SHELL_BUN_CONTAINER_MARKER_FILE || '/run/.containerenv';

// Colors
const colors = {
  RED: '\x1b[0;31m',
  GREEN: '\x1b[0;32m',
  YELLOW: '\x1b[1;33m',
  BLUE: '\x1b[0;34m',
  PURPLE: '\x1b[0;35m',
  CYAN: '\x1b[0;36m',
  BOLD: '\x1b[1m',
  DIM: '\x1b[2m',
  NC: '\x1b[0m' // No Color
};

// Helper functions
function printColor(color, message) {
  console.log(`${color}${message}${colors.NC}`);
}

function debugLog(message) {
  if (DEBUG_MODE) {
    fs.appendFileSync('debug.log', `[DEBUG] ${message}\n`);
  }
}

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  let i = 0;
  
  while (i < args.length) {
    const arg = args[i];
    
    if (arg === '--debug') {
      DEBUG_MODE = true;
      i++;
    } else if (arg === '--ci') {
      CI_MODE = true;
      i++;
      if (i < args.length && !args[i].startsWith('--') && !args[i].endsWith('.cfg')) {
        CI_APP = args[i];
        i++;
        if (i < args.length && !args[i].startsWith('--') && !args[i].endsWith('.cfg')) {
          CI_ACTIONS = args[i];
          i++;
        }
      }
    } else if (arg === '--container') {
      if (i + 1 >= args.length) {
        console.error('Error: --container requires a command argument');
        process.exit(1);
      }
      CLI_CONTAINER_OVERRIDE = true;
      CLI_CONTAINER_COMMAND = args[i + 1];
      i += 2;
    } else if (arg.startsWith('--container=')) {
      CLI_CONTAINER_OVERRIDE = true;
      CLI_CONTAINER_COMMAND = arg.substring('--container='.length);
      i++;
    } else if (arg === '--help' || arg === '-h') {
      console.log(`Shell-Bun v${VERSION} - Interactive build environment script`);
      console.log('Copyright (c) 2025, Fredrik Reveny');
      console.log('');
      console.log('Usage:');
      console.log(`  ${process.argv[1]} [options] [config-file]`);
      console.log('');
      console.log('Interactive mode (default):');
      console.log(`  ${process.argv[1]}                         # Use default config (shell-bun.cfg)`);
      console.log(`  ${process.argv[1]} my-config.txt           # Use custom config file`);
      console.log(`  ${process.argv[1]} --debug                 # Enable debug logging`);
      console.log(`  ${process.argv[1]} --container "podman exec ..."   # Override container command`);
      console.log('');
      console.log('Non-interactive mode (CI/CD) with fuzzy pattern matching:');
      console.log(`  ${process.argv[1]} --ci APP_PATTERN ACTION_PATTERN   # Run actions matching patterns`);
      console.log('');
      console.log('App pattern examples:');
      console.log('  MyWebApp                    # Exact app name');
      console.log('  *Web*                       # Wildcard: any app containing \'Web\'');
      console.log('  API*                        # Wildcard: apps starting with \'API\'');
      console.log('  web                         # Substring: apps containing \'web\'');
      console.log('  MyWebApp,API*,mobile        # Multiple: comma-separated patterns');
      console.log('');
      console.log('Action pattern examples:');
      console.log('  build_host                  # Exact action name');
      console.log('  build*                      # Wildcard: actions starting with \'build\'');
      console.log('  *host                       # Wildcard: actions ending with \'host\'');
      console.log('  test*,deploy                # Multiple specific actions');
      console.log('  unit                        # Substring: actions containing \'unit\'');
      console.log('  all                         # All available actions');
      console.log('');
      console.log('Actions are completely user-defined in your config file');
      process.exit(0);
    } else if (arg === '--version' || arg === '-v') {
      console.log(`v${VERSION}`);
      process.exit(0);
    } else if (arg.startsWith('-')) {
      console.error(`Unknown option: ${arg}`);
      console.error('Use --help for usage information');
      process.exit(1);
    } else {
      CONFIG_FILE = arg;
      i++;
    }
  }
}

// Parse configuration file
function parseConfig() {
  if (!fs.existsSync(CONFIG_FILE)) {
    printColor(colors.RED, `Error: Configuration file '${CONFIG_FILE}' not found!`);
    console.log('Please create a configuration file or specify a different one.');
    console.log(`Usage: ${process.argv[1]} [config-file]`);
    process.exit(1);
  }

  const content = fs.readFileSync(CONFIG_FILE, 'utf-8');
  const config = ini.parse(content);
  
  let currentApp = '';
  
  // Process global settings first
  if (config.log_dir) {
    globalLogDir = config.log_dir;
  }
  if (config.container) {
    configContainerCommand = config.container;
  }
  
  // Process sections
  for (const [section, values] of Object.entries(config)) {
    if (section === 'log_dir' || section === 'container') {
      continue; // Already processed
    }
    
    // Check if this is a section header (application)
    if (section.startsWith('[') && section.endsWith(']')) {
      currentApp = section.slice(1, -1);
      apps.push(currentApp);
      appActionList.set(currentApp, []);
    } else if (currentApp) {
      // This shouldn't happen with ini parser, but handle it
      continue;
    }
  }
  
  // Re-parse to handle sections properly
  const lines = content.split('\n');
  currentApp = '';
  
  for (const line of lines) {
    const trimmed = line.trim();
    
    // Skip empty lines and comments
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    
    // Check for section header
    const sectionMatch = trimmed.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      currentApp = sectionMatch[1];
      if (!apps.includes(currentApp)) {
        apps.push(currentApp);
        appActionList.set(currentApp, []);
      }
      continue;
    }
    
    // Check for key=value
    const kvMatch = trimmed.match(/^([^=]+)=(.*)$/);
    if (kvMatch) {
      const key = kvMatch[1].trim();
      const value = kvMatch[2].trim();
      
      if (!currentApp && key === 'log_dir') {
        globalLogDir = value;
      } else if (!currentApp && key === 'container') {
        configContainerCommand = value;
      } else if (currentApp && key === 'working_dir') {
        appWorkingDir.set(currentApp, value);
      } else if (currentApp && key === 'log_dir') {
        appLogDir.set(currentApp, value);
      } else if (currentApp) {
        // Generic action
        const actionKey = `${currentApp}:${key}`;
        appActions.set(actionKey, value);
        const actions = appActionList.get(currentApp) || [];
        if (!actions.includes(key)) {
          actions.push(key);
          appActionList.set(currentApp, actions);
        }
      }
    }
  }
  
  // Determine container command
  if (CLI_CONTAINER_OVERRIDE) {
    containerCommand = CLI_CONTAINER_COMMAND;
  } else {
    if (fs.existsSync(CONTAINER_ENV_FILE) && configContainerCommand) {
      printColor(colors.YELLOW, `Detected ${CONTAINER_ENV_FILE} - ignoring configured container command: ${configContainerCommand}`);
      containerCommand = '';
    } else {
      containerCommand = configContainerCommand;
    }
  }
  
  if (apps.length === 0) {
    printColor(colors.RED, 'Error: No applications found in configuration file!');
    process.exit(1);
  }
}

// Generate log file path
function generateLogFilePath(app, action) {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hour = String(now.getHours()).padStart(2, '0');
  const minute = String(now.getMinutes()).padStart(2, '0');
  const second = String(now.getSeconds()).padStart(2, '0');
  const timestamp = `${year}${month}${day}_${hour}${minute}${second}`;
  
  const scriptDir = path.dirname(__filename || process.argv[1] || '.');
  
  // Get log directory
  let logDir = appLogDir.get(app) || '';
  if (!logDir && globalLogDir) {
    logDir = globalLogDir;
  }
  if (!logDir) {
    logDir = path.join(scriptDir, 'logs');
  }
  
  // Expand tilde
  if (logDir.startsWith('~')) {
    logDir = path.join(process.env.HOME, logDir.slice(1));
  }
  
  // Make relative paths relative to script directory
  if (!path.isAbsolute(logDir)) {
    logDir = path.join(scriptDir, logDir);
  }
  
  // Create log directory if it doesn't exist
  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch (err) {
    console.warn(`Warning: Cannot create log directory '${logDir}', using script directory`);
    logDir = scriptDir;
  }
  
  const logFile = path.join(logDir, `${timestamp}_${app}_${action}.log`);
  return logFile;
}

// Log execution status
function logExecution(app, action, status, command = '') {
  switch (status) {
    case 'start':
      if (command) {
        printColor(colors.CYAN, `🚀 Starting: ${app} - ${action}: ${colors.DIM}${command}${colors.NC}${colors.CYAN}`);
      } else {
        printColor(colors.CYAN, `🚀 Starting: ${app} - ${action}`);
      }
      break;
    case 'success':
      printColor(colors.GREEN, `✅ Completed: ${app} - ${action}`);
      break;
    case 'error':
      printColor(colors.RED, `❌ Failed: ${app} - ${action}`);
      break;
  }
}

// Execute command
async function executeCommand(app, action, showOutput = false) {
  const actionKey = `${app}:${action}`;
  const command = appActions.get(actionKey);
  
  if (!command) {
    logExecution(app, action, 'error');
    printColor(colors.RED, `Error: No command configured for '${action}' in ${app}`);
    return { success: false, logFile: null };
  }
  
  const scriptDir = path.dirname(__filename || process.argv[1] || '.');
  let workingDir = appWorkingDir.get(app) || '';
  let workingDirForContainer = workingDir;
  
  if (containerCommand) {
    // Container mode: use working_dir as-is
    if (!workingDirForContainer) {
      workingDirForContainer = '';
    }
  } else {
    // Non-container mode: resolve paths
    if (!workingDir) {
      workingDir = scriptDir;
    }
    
    // Expand tilde
    if (workingDir.startsWith('~')) {
      workingDir = path.join(process.env.HOME, workingDir.slice(1));
    }
    
    // Make relative paths relative to script directory
    if (!path.isAbsolute(workingDir)) {
      workingDir = path.join(scriptDir, workingDir);
    }
    
    // Check if working directory exists
    if (!fs.existsSync(workingDir) || !fs.statSync(workingDir).isDirectory()) {
      logExecution(app, action, 'error');
      printColor(colors.RED, `Error: Working directory '${workingDir}' does not exist for ${app}`);
      return { success: false, logFile: null };
    }
  }
  
  // Generate log file path
  let logFile = null;
  if (!CI_MODE) {
    logFile = generateLogFilePath(app, action);
  }
  
  // Build full command
  let fullCommand;
  if (containerCommand) {
    if (workingDirForContainer) {
      const containerCmd = `cd ${escapeShell(workingDirForContainer)} && ${command}`;
      fullCommand = `${containerCommand} bash -lc ${escapeShell(containerCmd)}`;
    } else {
      fullCommand = `${containerCommand} bash -lc ${escapeShell(command)}`;
    }
  } else {
    fullCommand = `bash -c ${escapeShell(command)}`;
  }
  
  logExecution(app, action, 'start', fullCommand);
  
  // Execute command
  return new Promise((resolve) => {
    let exitCode = 0;
    
    if (CI_MODE) {
      // CI mode: just execute
      const proc = spawn('bash', ['-c', containerCommand 
        ? (workingDirForContainer 
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command)
        : command], {
        cwd: containerCommand ? undefined : workingDir,
        shell: true,
        stdio: 'inherit'
      });
      
      if (containerCommand) {
        // For container, we need to wrap it differently
        const containerCmd = workingDirForContainer
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command;
        const fullContainerCmd = `${containerCommand} bash -lc ${escapeShell(containerCmd)}`;
        const containerProc = spawn('bash', ['-c', fullContainerCmd], {
          stdio: 'inherit',
          shell: true
        });
        
        containerProc.on('close', (code) => {
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
            printColor(colors.RED, `Command failed with exit code ${exitCode}`);
          }
          resolve({ success: exitCode === 0, logFile });
        });
      } else {
        proc.on('close', (code) => {
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
            printColor(colors.RED, `Command failed with exit code ${exitCode}`);
          }
          resolve({ success: exitCode === 0, logFile });
        });
      }
    } else if (showOutput) {
      // Interactive single execution: show output and log
      const proc = spawn('bash', ['-c', containerCommand
        ? (workingDirForContainer
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command)
        : command], {
        cwd: containerCommand ? undefined : workingDir,
        shell: true
      });
      
      if (containerCommand) {
        const containerCmd = workingDirForContainer
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command;
        const fullContainerCmd = `${containerCommand} bash -lc ${escapeShell(containerCmd)}`;
        const containerProc = spawn('bash', ['-c', fullContainerCmd], {
          shell: true
        });
        
        const logStream = fs.createWriteStream(logFile);
        containerProc.stdout.pipe(process.stdout);
        containerProc.stderr.pipe(process.stderr);
        containerProc.stdout.pipe(logStream);
        containerProc.stderr.pipe(logStream);
        
        containerProc.on('close', (code) => {
          logStream.end();
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
          }
          resolve({ success: exitCode === 0, logFile });
        });
      } else {
        const logStream = fs.createWriteStream(logFile);
        proc.stdout.pipe(process.stdout);
        proc.stderr.pipe(process.stderr);
        proc.stdout.pipe(logStream);
        proc.stderr.pipe(logStream);
        
        proc.on('close', (code) => {
          logStream.end();
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
          }
          resolve({ success: exitCode === 0, logFile });
        });
      }
    } else {
      // Interactive parallel execution: only log to file
      const proc = spawn('bash', ['-c', containerCommand
        ? (workingDirForContainer
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command)
        : command], {
        cwd: containerCommand ? undefined : workingDir,
        shell: true
      });
      
      if (containerCommand) {
        const containerCmd = workingDirForContainer
          ? `cd ${escapeShell(workingDirForContainer)} && ${command}`
          : command;
        const fullContainerCmd = `${containerCommand} bash -lc ${escapeShell(containerCmd)}`;
        const containerProc = spawn('bash', ['-c', fullContainerCmd], {
          shell: true
        });
        
        const logStream = fs.createWriteStream(logFile);
        containerProc.stdout.pipe(logStream);
        containerProc.stderr.pipe(logStream);
        
        containerProc.on('close', (code) => {
          logStream.end();
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
          }
          resolve({ success: exitCode === 0, logFile });
        });
      } else {
        const logStream = fs.createWriteStream(logFile);
        proc.stdout.pipe(logStream);
        proc.stderr.pipe(logStream);
        
        proc.on('close', (code) => {
          logStream.end();
          exitCode = code || 0;
          if (exitCode === 0) {
            logExecution(app, action, 'success');
          } else {
            logExecution(app, action, 'error');
          }
          resolve({ success: exitCode === 0, logFile });
        });
      }
    }
  });
}

// Escape shell command
function escapeShell(str) {
  return `'${str.replace(/'/g, "'\\''")}'`;
}

// Pattern matching functions
function matchAppsFuzzy(pattern) {
  const matched = new Set();
  const patterns = pattern.split(',').map(p => p.trim());
  
  for (const pat of patterns) {
    for (const app of apps) {
      if (pat === app) {
        // Exact match
        matched.add(app);
      } else if (pat.includes('*')) {
        // Wildcard pattern
        const regex = new RegExp('^' + pat.replace(/\*/g, '.*') + '$');
        if (regex.test(app)) {
          matched.add(app);
        }
      } else {
        // Case-insensitive substring match
        if (app.toLowerCase().includes(pat.toLowerCase())) {
          matched.add(app);
        }
      }
    }
  }
  
  return Array.from(matched);
}

function matchActionsFuzzy(pattern, app) {
  const matched = [];
  const availableActions = appActionList.get(app) || [];
  
  if (pattern === 'all') {
    return availableActions;
  }
  
  const patterns = pattern.split(',').map(p => p.trim());
  
  for (const pat of patterns) {
    for (const action of availableActions) {
      if (matched.includes(action)) {
        continue;
      }
      
      if (pat === action) {
        // Exact match
        matched.push(action);
      } else if (pat.includes('*')) {
        // Wildcard pattern
        const regex = new RegExp('^' + pat.replace(/\*/g, '.*') + '$');
        if (regex.test(action)) {
          matched.push(action);
        }
      } else {
        // Case-insensitive substring match
        if (action.toLowerCase().includes(pat.toLowerCase())) {
          matched.push(action);
        }
      }
    }
  }
  
  return matched;
}

// CI mode execution
async function executeCIMode(appPattern, actionPattern) {
  const matchedApps = matchAppsFuzzy(appPattern);
  
  if (matchedApps.length === 0) {
    console.error(`Error: No applications found matching pattern '${appPattern}'`);
    console.error(`Available applications: ${apps.join(' ')}`);
    console.error('');
    console.error('Pattern matching supports:');
    console.error('  - Exact names: MyWebApp');
    console.error('  - Wildcards: *Web*, API*');
    console.error('  - Substrings: web, api');
    console.error('  - Multiple: MyWebApp,API*,mobile');
    process.exit(1);
  }
  
  const pids = [];
  const commandDescriptions = [];
  let foundAnyAction = false;
  
  // Start all matched commands in parallel
  for (const app of matchedApps) {
    const matchedActions = matchActionsFuzzy(actionPattern, app);
    
    if (matchedActions.length === 0) {
      console.warn(`Warning: No actions found for '${app}' matching pattern '${actionPattern}'`);
      const actions = appActionList.get(app) || [];
      console.warn(`Available actions for ${app}: ${actions.join(' ')}`);
      continue;
    }
    
    foundAnyAction = true;
    
    for (const action of matchedActions) {
      const result = executeCommand(app, action, false);
      pids.push(result);
      commandDescriptions.push(`${app} - ${action}`);
    }
  }
  
  if (!foundAnyAction || pids.length === 0) {
    console.error('');
    console.error(`Error: No actions found matching pattern '${actionPattern}'`);
    process.exit(1);
  }
  
  const isSingleAction = pids.length === 1;
  
  if (!isSingleAction) {
    console.log('Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)');
    console.log(`App pattern: '${appPattern}'`);
    console.log(`Action pattern: '${actionPattern}'`);
    console.log(`Matched apps: ${matchedApps.join(' ')}`);
    console.log(`Config: ${CONFIG_FILE}`);
    console.log('========================================');
    console.log('');
    console.log(`Running ${pids.length} actions in parallel...`);
    console.log('========================================');
  }
  
  // Wait for all promises
  const results = await Promise.all(pids);
  
  let totalSuccess = 0;
  let totalFailure = 0;
  const failedCommands = [];
  
  for (let i = 0; i < results.length; i++) {
    if (results[i].success) {
      totalSuccess++;
    } else {
      totalFailure++;
      failedCommands.push(commandDescriptions[i]);
    }
  }
  
  if (!isSingleAction) {
    console.log('');
    console.log('========================================');
    console.log('CI Execution Summary (Parallel):');
    console.log(`Commands executed: ${pids.length}`);
    console.log(`✅ Successful operations: ${totalSuccess}`);
    if (totalFailure > 0) {
      console.log(`❌ Failed operations: ${totalFailure}`);
      console.log('Failed commands:');
      for (const failedCmd of failedCommands) {
        console.log(`  - ${failedCmd}`);
      }
      process.exit(1);
    } else {
      console.log('🎉 All operations completed successfully');
      process.exit(0);
    }
  } else {
    if (totalFailure > 0) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  }
}

// Interactive TUI using Ink
function showInteractiveMenu() {
  // Build menu items
  const menuItems = [];
  for (const app of apps) {
    const actions = appActionList.get(app) || [];
    for (const action of actions) {
      menuItems.push({ type: 'action', app, action, label: `${app} - ${action}` });
    }
    menuItems.push({ type: 'details', app, label: `${app} - Show Details` });
  }

  let currentApp = null;
  let shouldQuit = false;

  const App = () => {
    const [showDetails, setShowDetails] = React.useState(false);

    if (shouldQuit) {
      return React.createElement(Text, { color: 'yellow' }, 'Goodbye!');
    }

    if (showDetails && currentApp) {
      const details = [];
      details.push(React.createElement(Text, { key: 'spacer1' }, ''));
      details.push(React.createElement(Text, { key: 'title', color: 'cyan' }, `=== ${currentApp} ===`));
      details.push(React.createElement(Text, { key: 'workdir' }, `Working Dir:    ${appWorkingDir.get(currentApp) || '(default)'}`));
      details.push(React.createElement(Text, { key: 'logdir' }, `Log Dir:        ${appLogDir.get(currentApp) || globalLogDir || '(default)'}`));
      details.push(React.createElement(Text, { key: 'container' }, `Container:      ${containerCommand || '(none - runs on host)'}`));
      details.push(React.createElement(Text, { key: 'spacer2' }, ''));
      details.push(React.createElement(Text, { key: 'actions-title', color: 'yellow' }, 'Available Actions:'));
      
      (appActionList.get(currentApp) || []).forEach((action, idx) => {
        const command = appActions.get(`${currentApp}:${action}`);
        details.push(React.createElement(Text, { key: `spacer-${idx}` }, ''));
        details.push(React.createElement(Text, { key: `action-${idx}`, color: 'cyan' }, `  ${action}:`));
        details.push(React.createElement(Text, { key: `cmd-${idx}` }, `    Command: ${command}`));
      });
      
      details.push(React.createElement(Text, { key: 'spacer3' }, ''));
      details.push(React.createElement(Text, { key: 'continue' }, 'Press Enter to continue...'));
      
      return React.createElement(Box, { flexDirection: 'column' }, ...details);
    }

    return React.createElement(Menu, {
      menuItems: menuItems,
      onSelect: (item) => {
        // Selection handled in Menu component
      },
      onExecute: async (items) => {
        // Exit UI, execute, then restart
        if (items.length === 1) {
          const match = items[0].match(/^(.+) - (.+)$/);
          if (match) {
            const app = match[1];
            const action = match[2];
            process.stdout.write('\x1b[2J\x1b[H'); // Clear screen
            await executeSingle(app, action);
            showInteractiveMenu();
          }
        } else {
          process.stdout.write('\x1b[2J\x1b[H'); // Clear screen
          await executeParallel(items);
          showInteractiveMenu();
        }
      },
      onDetails: (app) => {
        currentApp = app;
        setShowDetails(true);
        // Wait for enter, then go back
        process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.once('data', () => {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          setShowDetails(false);
        });
      },
      onQuit: () => {
        shouldQuit = true;
        process.exit(0);
      }
    });
  };

  render(React.createElement(App));
}

// Show app details
function showAppDetails(app) {
  console.log('');
  printColor(colors.CYAN, `=== ${app} ===`);
  
  const workingDir = appWorkingDir.get(app) || '(default)';
  console.log(`Working Dir:    ${workingDir}`);
  
  const logDir = appLogDir.get(app) || globalLogDir || '(default)';
  console.log(`Log Dir:        ${logDir}`);
  
  if (containerCommand) {
    console.log(`Container:      ${containerCommand}`);
  } else {
    console.log('Container:      (none - runs on host)');
  }
  
  console.log('');
  printColor(colors.YELLOW, 'Available Actions:');
  
  const actions = appActionList.get(app) || [];
  if (actions.length === 0) {
    console.log('  No actions configured');
  } else {
    for (const action of actions) {
      const command = appActions.get(`${app}:${action}`);
      console.log('');
      printColor(colors.CYAN, `  ${action}:`);
      console.log(`    Command: ${command}`);
    }
  }
  console.log('');
}

// Execute single command
async function executeSingle(app, action) {
  printColor(colors.BLUE, `📦 Executing: ${app} - ${action}`);
  console.log('');
  
  const result = await executeCommand(app, action, true);
  
  console.log('');
  console.log('Press Enter to continue...');
  await new Promise(resolve => {
    process.stdin.once('data', resolve);
  });
}

// Execute parallel commands
async function executeParallel(selectedItems) {
  if (selectedItems.length === 0) {
    printColor(colors.YELLOW, 'No items selected for execution.');
    return;
  }
  
  printColor(colors.BLUE, `📦 Executing ${selectedItems.length} selected items in parallel...`);
  console.log('');
  
  const promises = [];
  const descriptions = [];
  
  for (const item of selectedItems) {
    const match = item.match(/^(.+) - (.+)$/);
    if (match) {
      const app = match[1];
      const action = match[2];
      promises.push(executeCommand(app, action, false));
      descriptions.push(item);
    }
  }
  
  const results = await Promise.all(promises);
  
  let successCount = 0;
  let failureCount = 0;
  const failedCommands = [];
  const executionResults = [];
  
  for (let i = 0; i < results.length; i++) {
    if (results[i].success) {
      successCount++;
      executionResults.push(`SUCCESS: ${descriptions[i]} (${results[i].logFile})`);
    } else {
      failureCount++;
      failedCommands.push(descriptions[i]);
      executionResults.push(`FAILED: ${descriptions[i]} (${results[i].logFile})`);
    }
  }
  
  if (promises.length > 1) {
    console.log('');
    printColor(colors.BOLD, '📊 Execution Summary:');
    printColor(colors.GREEN, `✅ Successful: ${successCount}`);
    if (failureCount > 0) {
      printColor(colors.RED, `❌ Failed: ${failureCount}`);
      printColor(colors.RED, 'Failed commands:');
      for (const failedCmd of failedCommands) {
        printColor(colors.RED, `  - ${failedCmd}`);
      }
    }
    console.log('');
  }
  
  // Show log viewer (simplified)
  if (executionResults.length > 0) {
    console.log('Execution completed. Check log files for details.');
    console.log('Press Enter to continue...');
    await new Promise(resolve => {
      process.stdin.once('data', resolve);
    });
  }
}

// Main function
async function main() {
  parseArgs();
  
  printColor(colors.BLUE, `Loading configuration from: ${CONFIG_FILE}`);
  parseConfig();
  
  if (containerCommand) {
    if (CLI_CONTAINER_OVERRIDE) {
      printColor(colors.PURPLE, `Container mode enabled using CLI override: ${containerCommand}`);
    } else {
      printColor(colors.PURPLE, `Container mode enabled using: ${containerCommand}`);
    }
  } else if (CLI_CONTAINER_OVERRIDE) {
    if (configContainerCommand) {
      printColor(colors.YELLOW, `Container command overridden via --container (original: ${configContainerCommand})`);
    } else {
      printColor(colors.YELLOW, 'Container command overridden via --container');
    }
  }
  
  // Handle CI mode
  if (CI_MODE) {
    if (!CI_APP) {
      console.error('Error: Application name required for CI mode');
      console.error(`Available applications: ${apps.join(' ')}`);
      console.error('Use --help for usage information');
      process.exit(1);
    }
    
    if (!CI_ACTIONS) {
      console.error('Error: Action(s) required for CI mode');
      console.error('Actions are user-defined in your configuration file');
      console.error('Use --help for usage information');
      process.exit(1);
    }
    
    await executeCIMode(CI_APP, CI_ACTIONS);
    return;
  }
  
  // Interactive mode
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    printColor(colors.RED, 'Error: This script requires an interactive terminal for interactive mode');
    printColor(colors.YELLOW, 'Use --ci mode for non-interactive execution');
    console.log(`Example: ${process.argv[1]} --ci MyApp build_host`);
    process.exit(1);
  }
  
  printColor(colors.GREEN, `Found ${apps.length} applications`);
  if (apps.length > 0) {
    console.log(`Applications: ${apps.join(' ')}`);
  }
  console.log('');
  
  showInteractiveMenu();
}

// Run main
if (require.main === module) {
  main().catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
}

