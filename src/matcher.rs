use glob::Pattern;

pub fn match_apps_fuzzy(apps: &[String], pattern: &str) -> Vec<String> {
    let mut matched = Vec::new();
    let patterns: Vec<&str> = pattern.split(',').map(|s| s.trim()).collect();

    for pat in patterns {
        for app in apps {
            if matched.contains(app) {
                continue;
            }

            // Exact match
            if pat == app {
                matched.push(app.clone());
                continue;
            }

            // Wildcard pattern
            if pat.contains('*') {
                if let Ok(glob_pattern) = Pattern::new(pat) {
                    if glob_pattern.matches(app) {
                        matched.push(app.clone());
                        continue;
                    }
                }
            }

            // Case-insensitive substring match
            if app.to_lowercase().contains(&pat.to_lowercase()) {
                matched.push(app.clone());
            }
        }
    }

    matched
}

pub fn match_actions_fuzzy(actions: &[String], pattern: &str) -> Vec<String> {
    if pattern == "all" {
        return actions.to_vec();
    }

    let mut matched = Vec::new();
    let patterns: Vec<&str> = pattern.split(',').map(|s| s.trim()).collect();

    for pat in patterns {
        for action in actions {
            if matched.contains(action) {
                continue;
            }

            // Exact match
            if pat == action {
                matched.push(action.clone());
                continue;
            }

            // Wildcard pattern
            if pat.contains('*') {
                if let Ok(glob_pattern) = Pattern::new(pat) {
                    if glob_pattern.matches(action) {
                        matched.push(action.clone());
                        continue;
                    }
                }
            }

            // Case-insensitive substring match
            if action.to_lowercase().contains(&pat.to_lowercase()) {
                matched.push(action.clone());
            }
        }
    }

    matched
}

