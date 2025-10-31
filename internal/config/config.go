package config

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Config represents the full configuration loaded from the INI-style file.
type Config struct {
	Path             string
	BaseDir          string
	GlobalLogDirRaw  string
	GlobalLogDir     string
	ContainerCommand string

	apps       []*App
	appsByName map[string]*App
}

// App represents a single application section in the configuration.
type App struct {
	Name string

	WorkingDirRaw string
	WorkingDir    string

	LogDirRaw string
	LogDir    string

	actionsOrder []string
	actions      map[string]string
}

// Action represents a single executable action for an application.
type Action struct {
	AppName       string
	ActionName    string
	Command       string
	WorkingDir    string
	WorkingDirRaw string
	LogDir        string
	LogDirRaw     string
}

// Load reads the configuration file located at path and returns a parsed Config.
func Load(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("configuration file '%s' not found", path)
		}
		return nil, fmt.Errorf("unable to open configuration file '%s': %w", path, err)
	}
	defer f.Close()

	baseDir := filepath.Dir(path)
	absPath, err := filepath.Abs(path)
	if err == nil {
		path = absPath
		baseDir = filepath.Dir(absPath)
	}

	cfg := &Config{
		Path:       path,
		BaseDir:    baseDir,
		apps:       make([]*App, 0, 8),
		appsByName: make(map[string]*App),
	}

	if err := cfg.parse(f); err != nil {
		return nil, err
	}

	if len(cfg.apps) == 0 {
		return nil, fmt.Errorf("no applications defined in configuration '%s'", path)
	}

	cfg.finalize()
	return cfg, nil
}

// Apps returns all applications in the order they were defined.
func (c *Config) Apps() []*App {
	return append([]*App(nil), c.apps...)
}

// App returns the application with the given name, if present.
func (c *Config) App(name string) (*App, bool) {
	app, ok := c.appsByName[name]
	return app, ok
}

// AllActions returns every defined action across all applications.
func (c *Config) AllActions() []Action {
	var out []Action
	for _, app := range c.apps {
		for _, actionName := range app.actionsOrder {
			cmd := app.actions[actionName]
			out = append(out, Action{
				AppName:       app.Name,
				ActionName:    actionName,
				Command:       cmd,
				WorkingDir:    app.WorkingDir,
				WorkingDirRaw: app.WorkingDirRaw,
				LogDir:        app.LogDir,
				LogDirRaw:     app.LogDirRaw,
			})
		}
	}
	return out
}

// ActionsFor returns all actions belonging to the application with name.
func (c *Config) ActionsFor(name string) []Action {
	app, ok := c.appsByName[name]
	if !ok {
		return nil
	}

	actions := make([]Action, 0, len(app.actionsOrder))
	for _, actionName := range app.actionsOrder {
		cmd := app.actions[actionName]
		actions = append(actions, Action{
			AppName:       app.Name,
			ActionName:    actionName,
			Command:       cmd,
			WorkingDir:    app.WorkingDir,
			WorkingDirRaw: app.WorkingDirRaw,
			LogDir:        app.LogDir,
			LogDirRaw:     app.LogDirRaw,
		})
	}

	return actions
}

func (c *Config) parse(r io.Reader) error {
	scanner := bufio.NewScanner(r)

	var current *App
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		raw := scanner.Text()
		if lineNum == 1 {
			raw = strings.TrimPrefix(raw, "\ufeff")
		}

		trimmed := strings.TrimSpace(raw)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
			name := strings.TrimSpace(trimmed[1 : len(trimmed)-1])
			if name == "" {
				return fmt.Errorf("invalid application name at line %d", lineNum)
			}

			app := &App{
				Name:         name,
				actions:      make(map[string]string),
				actionsOrder: make([]string, 0, 8),
			}
			c.apps = append(c.apps, app)
			c.appsByName[name] = app
			current = app
			continue
		}

		key, value, ok := strings.Cut(trimmed, "=")
		if !ok {
			// Ignore malformed lines to mirror the bash implementation behaviour.
			continue
		}

		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)

		if current == nil {
			switch key {
			case "log_dir":
				c.GlobalLogDirRaw = value
			case "container":
				c.ContainerCommand = value
			}
			continue
		}

		switch key {
		case "working_dir":
			current.WorkingDirRaw = value
		case "log_dir":
			current.LogDirRaw = value
		default:
			if _, exists := current.actions[key]; !exists {
				current.actionsOrder = append(current.actionsOrder, key)
			}
			current.actions[key] = value
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading configuration: %w", err)
	}

	return nil
}

func (c *Config) finalize() {
	c.GlobalLogDir = c.resolvePath(c.GlobalLogDirRaw)

	for _, app := range c.apps {
		app.WorkingDir = c.resolveWorkingDir(app.WorkingDirRaw)
		app.LogDir = c.resolveLogDir(app.LogDirRaw)

		if len(app.actionsOrder) == 0 {
			app.actionsOrder = make([]string, 0)
		}
	}
}

// ResolvePath exposes path resolution for consumers needing to resolve custom paths.
func (c *Config) ResolvePath(value string) string {
	return c.resolvePath(value)
}

func (c *Config) resolvePath(value string) string {
	if strings.TrimSpace(value) == "" {
		return ""
	}

	expanded := expandUserDir(strings.TrimSpace(value))
	if expanded == "" {
		return ""
	}

	if filepath.IsAbs(expanded) {
		return filepath.Clean(expanded)
	}

	return filepath.Clean(filepath.Join(c.BaseDir, expanded))
}

func (c *Config) resolveWorkingDir(value string) string {
	trimmed := strings.TrimSpace(value)
	if c.ContainerCommand != "" {
		if trimmed == "" {
			return ""
		}
		return trimmed
	}

	if trimmed == "" {
		return c.BaseDir
	}

	resolved := c.resolvePath(trimmed)
	if resolved == "" {
		return c.BaseDir
	}
	return resolved
}

func (c *Config) resolveLogDir(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		if c.GlobalLogDir != "" {
			return c.GlobalLogDir
		}
		return filepath.Join(c.BaseDir, "logs")
	}

	resolved := c.resolvePath(trimmed)
	if resolved == "" {
		if c.GlobalLogDir != "" {
			return c.GlobalLogDir
		}
		return filepath.Join(c.BaseDir, "logs")
	}

	return resolved
}

// expandUserDir expands a leading tilde to the user's home directory when possible.
func expandUserDir(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}

	if !strings.HasPrefix(trimmed, "~") {
		return trimmed
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return trimmed
	}

	if trimmed == "~" {
		return home
	}

	return filepath.Join(home, strings.TrimPrefix(trimmed, "~/"))
}
