use crate::config::Config;
use crate::executor;
// Logger and ExecutionStatus not needed in TUI
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph};
use ratatui::Terminal;
use std::io;

#[derive(Clone)]
enum MenuItem {
    Action { app: String, action: String },
    ShowDetails { app: String },
}

pub async fn run_interactive(config: &Config, container_command: Option<&str>, _debug: bool) -> Result<()> {
    // Build menu items
    let mut menu_items = Vec::new();
    for app in &config.apps {
        let actions = config.get_actions(app);
        for action in actions {
            menu_items.push(MenuItem::Action {
                app: app.clone(),
                action: action.clone(),
            });
        }
        menu_items.push(MenuItem::ShowDetails {
            app: app.clone(),
        });
    }

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App {
        menu_items,
        filtered_items: Vec::new(),
        selected_index: 0,
        filter: String::new(),
        selected_items: Vec::new(),
        _view_offset: 0,
    };

    app.filter_items();

    let result = run_app(&mut terminal, &mut app, config, container_command).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

struct App {
    menu_items: Vec<MenuItem>,
    filtered_items: Vec<usize>, // Indices into menu_items
    selected_index: usize,
    filter: String,
    selected_items: Vec<usize>, // Indices into filtered_items
    _view_offset: usize,
}

impl App {
    fn filter_items(&mut self) {
        self.filtered_items.clear();
        if self.filter.is_empty() {
            // Show all items
            self.filtered_items = (0..self.menu_items.len()).collect();
        } else {
            let filter_lower = self.filter.to_lowercase();
            for (idx, item) in self.menu_items.iter().enumerate() {
                let text = match item {
                    MenuItem::Action { app, action } => format!("{} - {}", app, action),
                    MenuItem::ShowDetails { app } => format!("{} - Show Details", app),
                };
                if text.to_lowercase().contains(&filter_lower) {
                    self.filtered_items.push(idx);
                }
            }
        }
        // Adjust selected_index
        if self.selected_index >= self.filtered_items.len() && !self.filtered_items.is_empty() {
            self.selected_index = self.filtered_items.len() - 1;
        } else if self.filtered_items.is_empty() {
            self.selected_index = 0;
        }
    }

    fn is_selected(&self, filtered_idx: usize) -> bool {
        self.selected_items.contains(&filtered_idx)
    }

    fn toggle_selection(&mut self, filtered_idx: usize) {
        if let Some(pos) = self.selected_items.iter().position(|&x| x == filtered_idx) {
            self.selected_items.remove(pos);
        } else {
            self.selected_items.push(filtered_idx);
        }
    }

    fn select_all_filtered(&mut self) {
        self.selected_items = (0..self.filtered_items.len()).collect();
    }

    fn deselect_all_filtered(&mut self) {
        self.selected_items.clear();
    }
}

async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    config: &Config,
    container_command: Option<&str>,
) -> Result<()> {
    loop {
        terminal.draw(|f| {
            ui(f, app);
        })?;

        if let Event::Key(key) = event::read()? {
            if key.kind == KeyEventKind::Press {
                match key.code {
                    KeyCode::Esc => break,
                    KeyCode::Up => {
                        if app.selected_index > 0 {
                            app.selected_index -= 1;
                        }
                    }
                    KeyCode::Down => {
                        if app.selected_index < app.filtered_items.len().saturating_sub(1) {
                            app.selected_index += 1;
                        }
                    }
                    KeyCode::PageUp => {
                        let page_size = 10;
                        app.selected_index = app.selected_index.saturating_sub(page_size);
                    }
                    KeyCode::PageDown => {
                        let page_size = 10;
                        app.selected_index = (app.selected_index + page_size)
                            .min(app.filtered_items.len().saturating_sub(1));
                    }
                    KeyCode::Enter => {
                        if !app.selected_items.is_empty() {
                            // Execute all selected
                            execute_selected(terminal, app, config, container_command).await?;
                            app.selected_items.clear();
                        } else if let Some(&item_idx) = app.filtered_items.get(app.selected_index) {
                            let item = &app.menu_items[item_idx];
                            match item {
                                MenuItem::Action { app: app_name, action } => {
                                    execute_single(terminal, config, app_name, action, container_command).await?;
                                }
                                MenuItem::ShowDetails { app: app_name } => {
                                    show_details(terminal, config, app_name, container_command).await?;
                                }
                            }
                        }
                    }
                    KeyCode::Char(' ') => {
                        if let Some(&item_idx) = app.filtered_items.get(app.selected_index) {
                            let item = &app.menu_items[item_idx];
                            if matches!(item, MenuItem::Action { .. }) {
                                app.toggle_selection(app.selected_index);
                            }
                        }
                    }
                    KeyCode::Char('+') => {
                        app.select_all_filtered();
                    }
                    KeyCode::Char('-') => {
                        app.deselect_all_filtered();
                    }
                    KeyCode::Backspace => {
                        app.filter.pop();
                        app.filter_items();
                    }
                    KeyCode::Delete => {
                        app.filter.clear();
                        app.filter_items();
                    }
                    KeyCode::Char(c) => {
                        if c.is_ascii() && !c.is_control() {
                            app.filter.push(c);
                            app.filter_items();
                            app.selected_index = 0;
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    Ok(())
}

fn ui(f: &mut ratatui::Frame, app: &App) {
    let size = f.size();

    // Title and help
    let chunks = Layout::default()
        .constraints([
            Constraint::Length(3), // Title
            Constraint::Length(2), // Help
            Constraint::Length(2), // Filter/Selection status
            Constraint::Min(0),    // Menu items
            Constraint::Length(1), // Footer
        ])
        .split(size);

    // Title
    let title = Line::from(vec![
        Span::styled("╔══════════════════════════════════════════════════════════════════════════════════════╗", Style::default().fg(Color::Blue)),
    ]);
    let title2 = Line::from(vec![
        Span::styled("║          Shell-Bun by Fredrik Reveny (https://github.com/Chetic/shell-bun/)          ║", Style::default().fg(Color::Blue)),
    ]);
    let title3 = Line::from(vec![
        Span::styled("╚══════════════════════════════════════════════════════════════════════════════════════╝", Style::default().fg(Color::Blue)),
    ]);
    f.render_widget(Paragraph::new(vec![title, title2, title3]), chunks[0]);

    // Help
    let help = "Navigation: ↑/↓ arrows | PgUp/PgDn: page | Type: filter | Space: select | Enter: execute | ESC: quit\nShortcuts: '+' select visible | '-' deselect visible | Delete: clear filter";
    f.render_widget(
        Paragraph::new(help).style(Style::default().fg(Color::Cyan)),
        chunks[1],
    );

    // Filter and selection status
    let status = format!(
        "Filter: {}\nSelected: {} items",
        if app.filter.is_empty() {
            "(type to search)".to_string()
        } else {
            app.filter.clone()
        },
        app.selected_items.len()
    );
    let style = if app.filter.is_empty() {
        Style::default().fg(Color::DarkGray)
    } else {
        Style::default().fg(Color::Yellow)
    };
    f.render_widget(Paragraph::new(status).style(style), chunks[2]);

    // Menu items
    let items: Vec<ListItem> = app
        .filtered_items
        .iter()
        .enumerate()
        .map(|(filtered_idx, &item_idx)| {
            let item = &app.menu_items[item_idx];
            let text = match item {
                MenuItem::Action { app, action } => format!("{} - {}", app, action),
                MenuItem::ShowDetails { app } => format!("{} - Show Details", app),
            };
            let prefix = if filtered_idx == app.selected_index {
                "► "
            } else {
                "  "
            };
            let suffix = if app.is_selected(filtered_idx) {
                " [✓]"
            } else {
                ""
            };
            let mut style = Style::default();
            let text_with_suffix = format!("{}{}{}", prefix, text, suffix);
            
            if app.is_selected(filtered_idx) {
                style = style.fg(Color::Green);
                if filtered_idx == app.selected_index {
                    style = style.add_modifier(Modifier::BOLD);
                }
            } else if filtered_idx == app.selected_index {
                if matches!(item, MenuItem::ShowDetails { .. }) {
                    style = style.fg(Color::Magenta);
                } else {
                    style = style.fg(Color::Cyan);
                }
                style = style.add_modifier(Modifier::BOLD);
            } else if matches!(item, MenuItem::ShowDetails { .. }) {
                style = style.fg(Color::Yellow);
            }
            
            ListItem::new(text_with_suffix).style(style)
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::NONE));
    f.render_stateful_widget(list, chunks[3], &mut ListState::default().with_selected(Some(app.selected_index)));
}

async fn execute_single(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    config: &Config,
    app: &str,
    action: &str,
    container_command: Option<&str>,
) -> Result<()> {
    // Switch to normal mode temporarily
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;

    println!("\x1b[34m📦 Executing: {} - {}\x1b[0m\n", app, action);

    let result = executor::execute_command(
        config,
        app,
        action,
        container_command,
        true,
        None,
    )
    .await;

    println!("\nPress Enter to continue...");
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;

    // Return to TUI mode
    enable_raw_mode()?;
    execute!(terminal.backend_mut(), EnterAlternateScreen)?;

    result?;
    Ok(())
}

async fn execute_selected(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    config: &Config,
    container_command: Option<&str>,
) -> Result<()> {
    // Switch to normal mode
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;

    println!("\x1b[34m📦 Executing {} selected items in parallel...\x1b[0m\n", app.selected_items.len());

    let mut handles = Vec::new();
    let mut results = Vec::new();

    for &filtered_idx in &app.selected_items {
        if let Some(&item_idx) = app.filtered_items.get(filtered_idx) {
            if let MenuItem::Action { app: app_name, action } = &app.menu_items[item_idx] {
                let app_name_clone = app_name.clone();
                let action_clone = action.clone();
                let config = config.clone();
                let container = container_command.map(|s| s.to_string());
                let app_name_for_tuple = app_name.clone();
                let action_for_tuple = action.clone();

                let handle = tokio::spawn(async move {
                    executor::execute_command(
                        &config,
                        &app_name_clone,
                        &action_clone,
                        container.as_deref(),
                        false,
                        None,
                    )
                    .await
                });

                handles.push((app_name_for_tuple, action_for_tuple, handle));
            }
        }
    }

    // Wait for all and collect results
    for (app, action, handle) in handles {
        match handle.await {
            Ok(Ok(success)) => {
                results.push((app.clone(), action.clone(), success));
            }
            _ => {
                results.push((app, action, false));
            }
        }
    }

    // Show summary
    let success_count = results.iter().filter(|(_, _, s)| *s).count();
    let failure_count = results.len() - success_count;

    if results.len() > 1 {
        println!();
        println!("\x1b[1m📊 Execution Summary:\x1b[0m");
        println!("\x1b[32m✅ Successful: {}\x1b[0m", success_count);
        if failure_count > 0 {
            println!("\x1b[31m❌ Failed: {}\x1b[0m", failure_count);
        }
        println!();
    }

    // Show log viewer would go here (simplified for now)
    println!("Press Enter to continue...");
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;

    // Return to TUI
    enable_raw_mode()?;
    execute!(terminal.backend_mut(), EnterAlternateScreen)?;

    Ok(())
}

async fn show_details(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    config: &Config,
    app: &str,
    container_command: Option<&str>,
) -> Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;

    println!();
    println!("\x1b[36m=== {}\x1b[0m", app);
    println!("Working Dir:    {:?}", config.working_dirs.get(app));
    println!("Log Dir:        {:?}", config.log_dirs.get(app));
    if let Some(cmd) = container_command {
        println!("Container:      {}", cmd);
    } else {
        println!("Container:      (none - runs on host)");
    }
    println!();
    println!("\x1b[33mAvailable Actions:\x1b[0m");

    let actions = config.get_actions(app);
    for action in actions {
        if let Some(command) = config.get_command(app, action) {
            println!();
            println!("\x1b[36m  {}:\x1b[0m", action);
            println!("    Command: {}", command);
        }
    }
    println!();

    println!("Press Enter to continue...");
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;

    enable_raw_mode()?;
    execute!(terminal.backend_mut(), EnterAlternateScreen)?;

    Ok(())
}

