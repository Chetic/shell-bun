use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Config {
    pub apps: Vec<String>,
    pub actions: HashMap<String, String>, // Key: "app:action", Value: "command"
    pub app_actions: HashMap<String, Vec<String>>, // Key: "app", Value: list of actions
    pub working_dirs: HashMap<String, String>, // Key: "app", Value: "working_dir"
    pub log_dirs: HashMap<String, String>, // Key: "app", Value: "log_dir"
    pub global_log_dir: Option<String>,
    pub global_container: Option<String>,
}

impl Config {
    pub fn from_file(path: &Path) -> Result<Self> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Configuration file not found: {:?}", path))?;

        let mut config = Config {
            apps: Vec::new(),
            actions: HashMap::new(),
            app_actions: HashMap::new(),
            working_dirs: HashMap::new(),
            log_dirs: HashMap::new(),
            global_log_dir: None,
            global_container: None,
        };

        let mut current_app: Option<String> = None;

        for (_line_num, line) in content.lines().enumerate() {
            let line = line.trim();

            // Skip empty lines and comments
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            // Check for section header [AppName]
            if let Some(app_name) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                let app_name = app_name.trim().to_string();
                if app_name.is_empty() {
                    continue;
                }
                current_app = Some(app_name.clone());
                if !config.apps.contains(&app_name) {
                    config.apps.push(app_name.clone());
                }
                config.app_actions.entry(app_name).or_insert_with(Vec::new);
                continue;
            }

            // Parse key=value pairs
            if let Some((key, value)) = line.split_once('=') {
                let key = key.trim();
                let value = value.trim();

                if key.is_empty() {
                    continue;
                }

                if let Some(ref app) = current_app {
                    // App-specific settings
                    match key {
                        "working_dir" => {
                            config.working_dirs.insert(app.clone(), value.to_string());
                        }
                        "log_dir" => {
                            config.log_dirs.insert(app.clone(), value.to_string());
                        }
                        _ => {
                            // Generic action
                            let action_key = format!("{}:{}", app, key);
                            config.actions.insert(action_key, value.to_string());
                            config
                                .app_actions
                                .entry(app.clone())
                                .or_insert_with(Vec::new)
                                .push(key.to_string());
                        }
                    }
                } else {
                    // Global settings (before any app section)
                    match key {
                        "log_dir" => {
                            config.global_log_dir = Some(value.to_string());
                        }
                        "container" => {
                            config.global_container = Some(value.to_string());
                        }
                        _ => {
                            // Ignore unknown global keys
                        }
                    }
                }
            }
        }

        if config.apps.is_empty() {
            anyhow::bail!("No applications found in configuration file");
        }

        Ok(config)
    }

    pub fn get_command(&self, app: &str, action: &str) -> Option<&String> {
        let key = format!("{}:{}", app, action);
        self.actions.get(&key)
    }

    pub fn get_actions(&self, app: &str) -> &[String] {
        self.app_actions.get(app).map(|v| v.as_slice()).unwrap_or(&[])
    }
}

