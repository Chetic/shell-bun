package executor

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/Chetic/shell-bun/internal/config"
)

// Mode describes how a command should be executed.
type Mode int

const (
	ModeInteractiveSingle Mode = iota
	ModeInteractiveBatch
	ModeCI
)

// RunParams provides execution customisation for individual commands.
type RunParams struct {
	Mode   Mode
	Stdout io.Writer
	Stderr io.Writer
}

// Result captures the outcome of a command execution.
type Result struct {
	AppName    string
	ActionName string
	Command    string
	FullCmd    string
	LogPath    string
	Success    bool
	Err        error
	StartedAt  time.Time
	FinishedAt time.Time
}

// Runner encapsulates configuration-aware command execution.
type Runner struct {
	cfg *config.Config
}

// NewRunner constructs a new Runner.
func NewRunner(cfg *config.Config) *Runner {
	return &Runner{cfg: cfg}
}

// Run executes a single action and returns its result.
func (r *Runner) Run(ctx context.Context, action config.Action, params RunParams) Result {
	result := Result{
		AppName:    action.AppName,
		ActionName: action.ActionName,
		Command:    action.Command,
		StartedAt:  time.Now(),
	}

	logFile, logPath, err := r.prepareLog(action, params.Mode)
	if err != nil {
		result.Err = err
		result.Success = false
		result.LogPath = ""
		result.FinishedAt = time.Now()
		return result
	}
	result.LogPath = logPath

	cmd, display, err := r.buildCommand(ctx, action)
	result.FullCmd = display
	if err != nil {
		result.Err = err
		result.Success = false
		result.FinishedAt = time.Now()
		if logFile != nil {
			logFile.Close()
		}
		return result
	}

	// Configure stdout/stderr routing
	var writers []io.Writer
	if logFile != nil {
		writers = append(writers, logFile)
	}

	if params.Stdout != nil {
		writers = append(writers, params.Stdout)
	}

	if params.Stderr != nil && params.Stderr != params.Stdout {
		// stderr writer may differ; if not provided fallback to stdout writer chain
		cmd.Stderr = params.Stderr
	}

	if len(writers) > 0 {
		multi := io.MultiWriter(writers...)
		cmd.Stdout = multi
		if cmd.Stderr == nil {
			cmd.Stderr = multi
		}
	}

	if cmd.Stdout == nil {
		cmd.Stdout = io.Discard
	}
	if cmd.Stderr == nil {
		cmd.Stderr = io.Discard
	}

	err = cmd.Run()
	result.FinishedAt = time.Now()
	if err != nil {
		result.Err = err
		result.Success = false
	} else {
		result.Success = true
	}

	if logFile != nil {
		logFile.Close()
	}

	return result
}

// RunParallel executes the provided actions concurrently and returns ordered results.
func (r *Runner) RunParallel(ctx context.Context, actions []config.Action, mode Mode) []Result {
	results := make([]Result, len(actions))
	var wg sync.WaitGroup

	for idx, action := range actions {
		idx, action := idx, action
		wg.Add(1)
		go func() {
			defer wg.Done()
			params := RunParams{Mode: mode}
			if mode == ModeCI {
				params.Stdout = os.Stdout
				params.Stderr = os.Stderr
			}
			results[idx] = r.Run(ctx, action, params)
		}()
	}

	wg.Wait()
	return results
}

func (r *Runner) prepareLog(action config.Action, mode Mode) (*os.File, string, error) {
	// CI mode mirrors bash implementation by avoiding log file generation.
	if mode == ModeCI {
		return nil, "", nil
	}

	logDir := action.LogDir
	if logDir == "" {
		logDir = filepath.Join(r.cfg.BaseDir, "logs")
	}

	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, "", fmt.Errorf("unable to create log directory '%s': %w", logDir, err)
	}

	timestamp := time.Now().Format("20060102_150405")
	fileName := fmt.Sprintf("%s_%s_%s.log", timestamp, sanitizeName(action.AppName), sanitizeName(action.ActionName))
	logPath := filepath.Join(logDir, fileName)

	f, err := os.Create(logPath)
	if err != nil {
		return nil, "", fmt.Errorf("unable to create log file '%s': %w", logPath, err)
	}

	return f, logPath, nil
}

func (r *Runner) buildCommand(ctx context.Context, action config.Action) (*exec.Cmd, string, error) {
	command := strings.TrimSpace(action.Command)
	if command == "" {
		return nil, "", fmt.Errorf("no command configured for action '%s' in app '%s'", action.ActionName, action.AppName)
	}

	if r.cfg.ContainerCommand != "" {
		inner := command
		if strings.TrimSpace(action.WorkingDirRaw) != "" {
			inner = fmt.Sprintf("cd %s && %s", shellQuote(action.WorkingDirRaw), command)
		}

		escapedInner := shellQuote(inner)
		full := fmt.Sprintf("%s bash -lc %s", r.cfg.ContainerCommand, escapedInner)
		cmd := exec.CommandContext(ctx, "bash", "-lc", full)
		cmd.Dir = r.cfg.BaseDir
		return cmd, full, nil
	}

	cmd := exec.CommandContext(ctx, "bash", "-lc", command)
	workingDir := action.WorkingDir
	if strings.TrimSpace(workingDir) == "" {
		workingDir = r.cfg.BaseDir
	}

	if _, err := os.Stat(workingDir); err != nil {
		if os.IsNotExist(err) {
			return nil, "", fmt.Errorf("working directory '%s' does not exist for app '%s'", workingDir, action.AppName)
		}
		return nil, "", err
	}

	cmd.Dir = workingDir
	full := fmt.Sprintf("bash -lc %s", shellQuote(command))
	return cmd, full, nil
}

func sanitizeName(value string) string {
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r == '-' || r == '_':
			return r
		case r >= '0' && r <= '9':
			return r
		case r >= 'A' && r <= 'Z':
			return r
		case r >= 'a' && r <= 'z':
			return r
		default:
			return '_'
		}
	}, value)

	cleaned = strings.Trim(cleaned, "_")
	if cleaned == "" {
		return "action"
	}
	return cleaned
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}

	if !strings.ContainsAny(value, " \t\n\"'\\$`") {
		return value
	}

	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
