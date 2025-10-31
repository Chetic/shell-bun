package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/Chetic/shell-bun/internal/config"
	"github.com/Chetic/shell-bun/internal/executor"
	"github.com/Chetic/shell-bun/internal/pattern"
	"github.com/Chetic/shell-bun/internal/ui"
)

const version = "2.0.0"

func main() {
	var (
		debugFlag   bool
		ciFlag      bool
		configPath  string
		showVersion bool
	)

	flag.BoolVar(&debugFlag, "debug", false, "Enable debug logging")
	flag.BoolVar(&ciFlag, "ci", false, "Run in CI mode")
	flag.StringVar(&configPath, "config", "", "Path to configuration file")
	flag.BoolVar(&showVersion, "version", false, "Print version and exit")
	flag.BoolVar(&showVersion, "v", false, "Print version and exit")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Shell-Bun %s\n", version)
		fmt.Fprintf(flag.CommandLine.Output(), "Usage:\n")
		fmt.Fprintf(flag.CommandLine.Output(), "  shellbun [options] [config-file]\n")
		fmt.Fprintf(flag.CommandLine.Output(), "\nOptions:\n")
		flag.PrintDefaults()
		fmt.Fprintf(flag.CommandLine.Output(), "\nExamples:\n")
		fmt.Fprintf(flag.CommandLine.Output(), "  shellbun --ci MyApp build\n")
		fmt.Fprintf(flag.CommandLine.Output(), "  shellbun custom.cfg\n")
	}

	flag.Parse()

	if showVersion {
		fmt.Println("Shell-Bun", version)
		return
	}

	args := flag.Args()

	// Allow positional config path compatibility (e.g., shellbun my-config.cfg)
	if configPath == "" {
		for i := len(args) - 1; i >= 0; i-- {
			arg := args[i]
			if strings.HasSuffix(arg, ".cfg") {
				configPath = arg
				args = append(args[:i], args[i+1:]...)
				break
			}
		}
	}

	if configPath == "" {
		configPath = "shell-bun.cfg"
	}

	debugWriter := ensureDebugLog(debugFlag)
	if debugWriter != nil {
		fmt.Fprintf(debugWriter, "Shell-Bun %s starting\n", version)
		fmt.Fprintf(debugWriter, "Using configuration: %s\n", configPath)
		defer debugWriter.Close()
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	runner := executor.NewRunner(cfg)

	if ciFlag {
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Error: --ci requires application and action patterns")
			os.Exit(1)
		}
		appPattern := args[0]
		actionPattern := args[1]
		if debugWriter != nil {
			fmt.Fprintf(debugWriter, "CI mode: apps='%s' actions='%s'\n", appPattern, actionPattern)
		}
		handleCIMode(cfg, runner, appPattern, actionPattern)
		return
	}

	ensureInteractive()

	model := ui.NewModel(cfg, runner)
	if debugWriter != nil {
		fmt.Fprintln(debugWriter, "Interactive mode initialised")
	}
	program := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := program.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func handleCIMode(cfg *config.Config, runner *executor.Runner, appPattern, actionPattern string) {
	apps := cfg.Apps()
	appNames := make([]string, len(apps))
	for i, app := range apps {
		appNames[i] = app.Name
	}

	matchedApps := pattern.MatchSet(appPattern, appNames)
	if len(matchedApps) == 0 {
		fmt.Fprintf(os.Stderr, "Error: No applications found matching '%s'\n", appPattern)
		fmt.Fprintf(os.Stderr, "Available applications: %s\n", strings.Join(appNames, ", "))
		os.Exit(1)
	}

	var actions []config.Action
	for _, appName := range matchedApps {
		appActions := cfg.ActionsFor(appName)
		actionNames := make([]string, len(appActions))
		for i, act := range appActions {
			actionNames[i] = act.ActionName
		}

		matchedActions := pattern.MatchActions(actionPattern, actionNames)
		if len(matchedActions) == 0 {
			fmt.Fprintf(os.Stderr, "Warning: No actions matched '%s' for %s\n", actionPattern, appName)
			fmt.Fprintf(os.Stderr, "Available actions: %s\n", strings.Join(actionNames, ", "))
			continue
		}

		for _, name := range matchedActions {
			for _, act := range appActions {
				if act.ActionName == name {
					actions = append(actions, act)
					break
				}
			}
		}
	}

	if len(actions) == 0 {
		fmt.Fprintf(os.Stderr, "Error: No actions matched '%s'\n", actionPattern)
		os.Exit(1)
	}

	fmt.Println("Shell-Bun CI Mode: Fuzzy Pattern Execution (Parallel)")
	fmt.Printf("App pattern: '%s'\n", appPattern)
	fmt.Printf("Action pattern: '%s'\n", actionPattern)
	fmt.Printf("Matched apps: %s\n", strings.Join(matchedApps, ", "))
	fmt.Printf("Config: %s\n", cfg.Path)
	fmt.Println(strings.Repeat("=", 40))
	fmt.Printf("Running %d action(s) in parallel...\n", len(actions))
	fmt.Println(strings.Repeat("=", 40))

	for _, act := range actions {
		fmt.Printf("🚀 Starting: %s - %s\n", act.AppName, act.ActionName)
	}

	results := runner.RunParallel(context.Background(), actions, executor.ModeCI)

	success := 0
	failure := 0
	for _, res := range results {
		if res.Success {
			success++
			fmt.Printf("✅ Completed: %s - %s\n", res.AppName, res.ActionName)
		} else {
			failure++
			fmt.Printf("❌ Failed: %s - %s\n", res.AppName, res.ActionName)
			if res.Err != nil {
				fmt.Printf("   Error: %v\n", res.Err)
			}
		}
	}

	fmt.Println(strings.Repeat("=", 40))
	fmt.Println("CI Execution Summary:")
	fmt.Printf("Commands executed: %d\n", len(results))
	fmt.Printf("✅ Successful operations: %d\n", success)
	if failure > 0 {
		fmt.Printf("❌ Failed operations: %d\n", failure)
		os.Exit(1)
	}

	fmt.Println("🎉 All operations completed successfully")
}

func ensureInteractive() {
	if !isTerminal(os.Stdin) || !isTerminal(os.Stdout) {
		fmt.Fprintln(os.Stderr, "Error: interactive mode requires a TTY")
		fmt.Fprintln(os.Stderr, "Use --ci for non-interactive execution")
		os.Exit(1)
	}
}

func isTerminal(file *os.File) bool {
	info, err := file.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}

// ensureDebugLog optionally creates a debug log writer.
func ensureDebugLog(enabled bool) io.WriteCloser {
	if !enabled {
		return nil
	}

	path := filepath.Join(".", "debug.log")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: unable to create debug.log: %v\n", err)
		return nil
	}
	return f
}
