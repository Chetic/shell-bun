use crate::config::Config;
use crate::logger::{Logger, ExecutionStatus};
use crate::matcher;
use anyhow::Result;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command as TokioCommand;

pub async fn execute_ci_mode(
    config: &Config,
    app_pattern: &str,
    action_pattern: &str,
    container_command: Option<&str>,
    _debug: bool,
) -> Result<()> {
    // Match applications
    let matched_apps = matcher::match_apps_fuzzy(&config.apps, app_pattern);

    if matched_apps.is_empty() {
        eprintln!("Error: No applications found matching pattern '{}'", app_pattern);
        eprintln!("Available applications: {:?}", config.apps);
        anyhow::bail!("No matching applications");
    }

    // Prepare parallel execution
    let mut handles = Vec::new();
    let mut found_any_action = false;

    // Start all matched commands in parallel
    for app in &matched_apps {
        let actions = config.get_actions(app);
        let matched_actions = matcher::match_actions_fuzzy(actions, action_pattern);

        if matched_actions.is_empty() {
            eprintln!(
                "Warning: No actions found for '{}' matching pattern '{}'",
                app, action_pattern
            );
            eprintln!("Available actions for {}: {:?}", app, actions);
            continue;
        }

        found_any_action = true;

        for action in matched_actions {
            let app_clone = app.clone();
            let action_clone = action.clone();
            let config = config.clone();
            let container = container_command.map(|s| s.to_string());
            let app_for_tuple = app.clone();
            let action_for_tuple = action.clone();

            let handle = tokio::spawn(async move {
                execute_command(
                    &config,
                    &app_clone,
                    &action_clone,
                    container.as_deref(),
                    false,
                    None,
                )
                .await
            });

            handles.push((app_for_tuple, action_for_tuple, handle));
        }
    }

    if !found_any_action || handles.is_empty() {
        anyhow::bail!("No actions found matching pattern '{}'", action_pattern);
    }

    // Determine if this is a single action execution
    let is_single_action = handles.len() == 1;

    // For multiple actions, show verbose header
    if !is_single_action {
        println!("Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)");
        println!("App pattern: '{}'", app_pattern);
        println!("Action pattern: '{}'", action_pattern);
        println!("Matched apps: {:?}", matched_apps);
        println!("========================================");
        println!();
        println!("Running {} actions in parallel...", handles.len());
        println!("========================================");
    }

    // Wait for all processes and collect results
    let mut total_success = 0;
    let mut total_failure = 0;
    let mut failed_commands = Vec::new();

    for (app, action, handle) in handles {
        match handle.await {
            Ok(Ok(true)) => {
                total_success += 1;
            }
            Ok(Ok(false)) | Ok(Err(_)) => {
                total_failure += 1;
                failed_commands.push(format!("{} - {}", app, action));
            }
            Err(e) => {
                total_failure += 1;
                failed_commands.push(format!("{} - {}", app, action));
                eprintln!("Error waiting for process: {}", e);
            }
        }
    }

    // Show summary if multiple actions
    if !is_single_action {
        println!();
        println!("========================================");
        println!("CI Execution Summary (Parallel):");
        println!("Commands executed: {}", total_success + total_failure);
        println!("✅ Successful operations: {}", total_success);
        if total_failure > 0 {
            println!("❌ Failed operations: {}", total_failure);
            println!("Failed commands:");
            for cmd in &failed_commands {
                println!("  - {}", cmd);
            }
            std::process::exit(1);
        } else {
            println!("🎉 All operations completed successfully");
            std::process::exit(0);
        }
    } else {
        // Single action: just exit with appropriate code
        if total_failure > 0 {
            std::process::exit(1);
        } else {
            std::process::exit(0);
        }
    }
}

pub async fn execute_command(
    config: &Config,
    app: &str,
    action: &str,
    container_command: Option<&str>,
    show_output: bool,
    _log_file_var: Option<&PathBuf>,
) -> Result<bool> {
    let command = config.get_command(app, action)
        .ok_or_else(|| anyhow::anyhow!("No command configured for '{}' in {}", action, app))?;

    // Get script directory (executable location)
    let script_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."));

    // Get working directory
    let working_dir = config.working_dirs.get(app).map(|s| s.as_str());
    let working_dir_path = resolve_working_dir(config.working_dirs.get(app), container_command.is_some(), &script_dir)?;

    // Generate log file path
    let app_log_dir = config.log_dirs.get(app);
    let log_file = Logger::generate_log_path(
        app,
        action,
        config.global_log_dir.as_ref(),
        app_log_dir,
        &script_dir,
    );

    // Build full command for display
    let full_command = build_full_command(
        command,
        working_dir,
        container_command,
    );

    Logger::log_execution_status(app, action, ExecutionStatus::Start, Some(&full_command));

    // Execute command
    let exit_code = if let Some(container_cmd) = container_command {
        execute_in_container(container_cmd, command, working_dir, &log_file, show_output).await?
    } else {
        execute_direct(command, working_dir_path.as_ref(), &log_file, show_output).await?
    };

    if exit_code == 0 {
        Logger::log_execution_status(app, action, ExecutionStatus::Success, None);
        Ok(true)
    } else {
        Logger::log_execution_status(app, action, ExecutionStatus::Error, None);
        if container_command.is_none() {
            eprintln!("Command failed with exit code {}", exit_code);
        }
        Ok(false)
    }
}

fn resolve_working_dir(
    working_dir: Option<&String>,
    is_container: bool,
    script_dir: &PathBuf,
) -> Result<Option<PathBuf>> {
    if is_container {
        // Container mode: working_dir is relative to container's starting point
        if let Some(wd) = working_dir {
            return Ok(Some(expand_path(wd, script_dir)?));
        }
        return Ok(None);
    }

    // Non-container mode: resolve paths relative to script directory
    let working_dir = if let Some(wd) = working_dir {
        Some(expand_path(wd, script_dir)?)
    } else {
        Some(script_dir.clone())
    };

    // Check if working directory exists
    if let Some(ref wd) = working_dir {
        if !wd.exists() {
            anyhow::bail!("Working directory '{}' does not exist", wd.display());
        }
    }

    Ok(working_dir)
}

fn expand_path(path: &str, script_dir: &PathBuf) -> Result<PathBuf> {
    // Expand tilde
    let expanded = if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            path.replacen('~', &home.to_string_lossy(), 1)
        } else {
            path.to_string()
        }
    } else {
        path.to_string()
    };

    // Handle absolute vs relative paths
    let path = PathBuf::from(expanded);
    if path.is_absolute() {
        Ok(path)
    } else {
        Ok(script_dir.join(path))
    }
}

fn build_full_command(
    command: &str,
    working_dir: Option<&str>,
    container_command: Option<&str>,
) -> String {
    if let Some(container_cmd) = container_command {
        if let Some(wd) = working_dir {
            format!("{} bash -lc \"cd {} && {}\"", container_cmd, shell_escape(wd), command)
        } else {
            format!("{} bash -lc \"{}\"", container_cmd, command)
        }
    } else {
        format!("bash -c {}", shell_escape(command))
    }
}

fn shell_escape(s: &str) -> String {
    // Simple shell escaping - replace single quotes
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

async fn execute_in_container(
    container_command: &str,
    command: &str,
    working_dir: Option<&str>,
    log_file: &PathBuf,
    show_output: bool,
) -> Result<i32> {
    let mut cmd_parts: Vec<&str> = container_command.split_whitespace().collect();
    
    // Build the command to execute inside container
    let container_cmd = if let Some(wd) = working_dir {
        format!("cd {} && {}", shell_escape(wd), command)
    } else {
        command.to_string()
    };

    cmd_parts.extend(&["bash", "-lc", &container_cmd]);

    let mut cmd = TokioCommand::new(cmd_parts[0]);
    cmd.args(&cmd_parts[1..]);

    if show_output {
        cmd.stdout(Stdio::inherit()).stderr(Stdio::inherit());
    } else {
        let file = std::fs::File::create(log_file)?;
        let file2 = file.try_clone()?;
        cmd.stdout(Stdio::from(file)).stderr(Stdio::from(file2));
    }

    let status = cmd.status().await?;
    Ok(status.code().unwrap_or(1))
}

async fn execute_direct(
    command: &str,
    working_dir: Option<&PathBuf>,
    log_file: &PathBuf,
    show_output: bool,
) -> Result<i32> {
    if show_output {
        // Use tee to show output and log simultaneously
        let log_file_str = log_file.to_string_lossy().to_string();
        let tee_cmd = format!("{} 2>&1 | tee {}", command, shell_escape(&log_file_str));
        let mut cmd = TokioCommand::new("bash");
        cmd.arg("-c").arg(&tee_cmd);
        
        if let Some(wd) = working_dir {
            cmd.current_dir(wd);
        }

        cmd.stdout(Stdio::inherit()).stderr(Stdio::inherit());
        let status = cmd.status().await?;
        Ok(status.code().unwrap_or(1))
    } else {
        let mut cmd = TokioCommand::new("bash");
        cmd.arg("-c").arg(command);

        if let Some(wd) = working_dir {
            cmd.current_dir(wd);
        }

        let file = std::fs::File::create(log_file)?;
        let file2 = file.try_clone()?;
        cmd.stdout(Stdio::from(file)).stderr(Stdio::from(file2));

        let status = cmd.status().await?;
        Ok(status.code().unwrap_or(1))
    }
}

