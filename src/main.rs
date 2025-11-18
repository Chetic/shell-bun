mod config;
mod executor;
mod logger;
mod matcher;
mod tui;

use anyhow::{Context, Result};
use std::path::PathBuf;

async fn execute_ci_with_config(
    config: config::Config,
    ci_args: &[String],
    container_command: Option<String>,
    debug_mode: bool,
) -> Result<()> {
    let (app_pattern, action_pattern) = if ci_args.len() >= 2 {
        (ci_args[0].clone(), ci_args[1].clone())
    } else {
        anyhow::bail!("CI mode requires APP_PATTERN and ACTION_PATTERN arguments");
    };

    executor::execute_ci_mode(
        &config,
        &app_pattern,
        &action_pattern,
        container_command.as_deref(),
        debug_mode,
    )
    .await
}

// Manual argument parsing to match shell script behavior

#[tokio::main]
async fn main() -> Result<()> {
    let mut args_iter = std::env::args().skip(1);
    let mut config_file = None;
    let mut debug_mode = false;
    let mut ci_mode = false;
    let mut container = None;
    let mut ci_args = Vec::new();

    // Parse arguments manually to match shell script behavior
    while let Some(arg) = args_iter.next() {
        match arg.as_str() {
            "--debug" => debug_mode = true,
            "--ci" => {
                ci_mode = true;
                // Collect remaining args as CI arguments
                while let Some(next) = args_iter.next() {
                    if next.starts_with("--") {
                        if next == "--container" {
                            if let Some(cmd) = args_iter.next() {
                                container = Some(cmd);
                            }
                        } else if let Some(cmd) = next.strip_prefix("--container=") {
                            container = Some(cmd.to_string());
                        }
                        break;
                    } else {
                        ci_args.push(next);
                    }
                }
            }
            "--container" => {
                if let Some(cmd) = args_iter.next() {
                    container = Some(cmd);
                }
            }
            arg if arg.starts_with("--container=") => {
                container = arg.strip_prefix("--container=").map(|s| s.to_string());
            }
            "--help" | "-h" => {
                println!("Shell-Bun v1.4.1 - Interactive build environment script");
                println!("Usage:");
                println!("  shell-bun [options] [config-file]");
                println!();
                println!("Interactive mode (default):");
                println!("  shell-bun                         # Use default config (shell-bun.cfg)");
                println!("  shell-bun my-config.txt           # Use custom config file");
                println!("  shell-bun --debug                 # Enable debug logging");
                println!();
                println!("Non-interactive mode (CI/CD):");
                println!("  shell-bun --ci APP_PATTERN ACTION_PATTERN [config]");
                println!();
                std::process::exit(0);
            }
            "--version" | "-v" => {
                println!("v1.4.1");
                std::process::exit(0);
            }
            arg if arg.starts_with('-') => {
                eprintln!("Unknown option: {}", arg);
                std::process::exit(1);
            }
            _ => {
                // Config file or part of CI args
                if ci_mode {
                    ci_args.push(arg);
                } else {
                    config_file = Some(PathBuf::from(arg));
                }
            }
        }
    }

    // Determine config file
    let config_path = config_file.unwrap_or_else(|| PathBuf::from("shell-bun.cfg"));

    // Parse configuration
    let config = config::Config::from_file(&config_path)
        .with_context(|| format!("Failed to load config from {:?}", config_path))?;

    // Override container command if provided
    let container_command = if let Some(cmd) = container {
        Some(cmd)
    } else {
        config.global_container.clone()
    };

    // Handle CI mode
    if ci_mode {
        // Check if last arg is a config file
        let (app_pattern, action_pattern) = if ci_args.len() >= 2 {
            if ci_args.len() >= 3 {
                let last_arg = &ci_args[ci_args.len() - 1];
                if last_arg.ends_with(".cfg") && std::path::Path::new(last_arg).exists() {
                    // Last arg is config file, re-parse config
                    let config_path = PathBuf::from(last_arg);
                    let config = config::Config::from_file(&config_path)
                        .with_context(|| format!("Failed to load config from {:?}", config_path))?;
                    let mut ci_args_no_config = ci_args.clone();
                    ci_args_no_config.pop(); // Remove config file from args
                    return execute_ci_with_config(config, &ci_args_no_config, container_command, debug_mode).await;
                }
            }
            (ci_args[0].clone(), ci_args[1].clone())
        } else {
            anyhow::bail!("CI mode requires APP_PATTERN and ACTION_PATTERN arguments. Usage: --ci APP_PATTERN ACTION_PATTERN");
        };

        executor::execute_ci_mode(
            &config,
            &app_pattern,
            &action_pattern,
            container_command.as_deref(),
            debug_mode,
        )
        .await?;
        return Ok(());
    }

    // Interactive mode
    tui::run_interactive(&config, container_command.as_deref(), debug_mode).await?;

    Ok(())
}

