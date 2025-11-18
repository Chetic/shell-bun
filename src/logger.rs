use chrono::Local;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Logger;

impl Logger {
    pub fn generate_log_path(
        app: &str,
        action: &str,
        global_log_dir: Option<&String>,
        app_log_dir: Option<&String>,
        script_dir: &Path,
    ) -> PathBuf {
        // Determine log directory
        let log_dir = if let Some(app_log) = app_log_dir {
            expand_path(app_log, script_dir)
        } else if let Some(global_log) = global_log_dir {
            expand_path(global_log, script_dir)
        } else {
            script_dir.join("logs")
        };

        // Create log directory if it doesn't exist
        if let Err(e) = fs::create_dir_all(&log_dir) {
            eprintln!("Warning: Cannot create log directory '{:?}', using script directory: {}", log_dir, e);
            let timestamp = Local::now().format("%Y%m%d_%H%M%S");
            return script_dir.join(format!("{}_{}_{}.log", timestamp, app, action));
        }

        // Generate log file name: timestamp_app_action.log
        let timestamp = Local::now().format("%Y%m%d_%H%M%S");
        log_dir.join(format!("{}_{}_{}.log", timestamp, app, action))
    }

    pub fn log_execution_status(app: &str, action: &str, status: ExecutionStatus, command: Option<&str>) {
        match status {
            ExecutionStatus::Start => {
                if let Some(cmd) = command {
                    println!("\x1b[36m🚀 Starting: {} - {}: \x1b[2m{}\x1b[0m\x1b[36m", app, action, cmd);
                } else {
                    println!("\x1b[36m🚀 Starting: {} - {}\x1b[0m", app, action);
                }
            }
            ExecutionStatus::Success => {
                println!("\x1b[32m✅ Completed: {} - {}\x1b[0m", app, action);
            }
            ExecutionStatus::Error => {
                println!("\x1b[31m❌ Failed: {} - {}\x1b[0m", app, action);
            }
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum ExecutionStatus {
    Start,
    Success,
    Error,
}

fn expand_path(path: &str, script_dir: &Path) -> PathBuf {
    // Expand tilde
    let path = if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            path.replacen('~', &home.to_string_lossy(), 1)
        } else {
            path.to_string()
        }
    } else {
        path.to_string()
    };

    // Handle absolute vs relative paths
    let path = Path::new(&path);
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        script_dir.join(path)
    }
}

