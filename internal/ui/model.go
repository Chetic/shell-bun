package ui

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Chetic/shell-bun/internal/config"
	"github.com/Chetic/shell-bun/internal/executor"
)

type viewState int

const (
	stateList viewState = iota
	stateRunning
	stateSummary
	stateDetails
	stateLog
)

type entryType int

const (
	entryAction entryType = iota
	entryDetails
)

type entry struct {
	typ     entryType
	app     string
	action  string
	command string
}

type runResultsMsg struct {
	Results []executor.Result
	Mode    executor.Mode
}

type Model struct {
	cfg    *config.Config
	runner *executor.Runner

	entries  []entry
	filtered []int
	filter   string

	cursor int
	scroll int

	selected map[int]struct{}

	state viewState

	width  int
	height int

	spinner spinner.Model

	infoMessage string
	errMessage  string

	results       []executor.Result
	summaryCursor int
	lastRunMode   executor.Mode

	logTitle  string
	logLines  []string
	logScroll int

	detailsTitle string
	detailsLines []string

	styles uiStyles
}

type uiStyles struct {
	header       lipgloss.Style
	filter       lipgloss.Style
	selectedItem lipgloss.Style
	currentItem  lipgloss.Style
	help         lipgloss.Style
	successBadge lipgloss.Style
	failureBadge lipgloss.Style
	dimmed       lipgloss.Style
	warning      lipgloss.Style
}

// NewModel constructs a Bubble Tea model initialised with configuration data.
func NewModel(cfg *config.Config, runner *executor.Runner) Model {
	entries := buildEntries(cfg)
	m := Model{
		cfg:      cfg,
		runner:   runner,
		entries:  entries,
		filtered: make([]int, len(entries)),
		selected: make(map[int]struct{}),
		state:    stateList,
		spinner:  spinner.New(),
		styles:   defaultStyles(),
	}

	for i := range entries {
		m.filtered[i] = i
	}

	m.spinner.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("63"))
	m.spinner.Spinner = spinner.Dot
	return m
}

func defaultStyles() uiStyles {
	return uiStyles{
		header:       lipgloss.NewStyle().Foreground(lipgloss.Color("213")).Bold(true),
		filter:       lipgloss.NewStyle().Foreground(lipgloss.Color("229")),
		selectedItem: lipgloss.NewStyle().Foreground(lipgloss.Color("46")),
		currentItem:  lipgloss.NewStyle().Foreground(lipgloss.Color("39")).Bold(true),
		help:         lipgloss.NewStyle().Foreground(lipgloss.Color("244")),
		successBadge: lipgloss.NewStyle().Foreground(lipgloss.Color("10")),
		failureBadge: lipgloss.NewStyle().Foreground(lipgloss.Color("196")),
		dimmed:       lipgloss.NewStyle().Foreground(lipgloss.Color("240")),
		warning:      lipgloss.NewStyle().Foreground(lipgloss.Color("214")),
	}
}

func buildEntries(cfg *config.Config) []entry {
	var entries []entry
	for _, app := range cfg.Apps() {
		for _, action := range cfg.ActionsFor(app.Name) {
			entries = append(entries, entry{
				typ:     entryAction,
				app:     action.AppName,
				action:  action.ActionName,
				command: action.Command,
			})
		}
		entries = append(entries, entry{
			typ: entryDetails,
			app: app.Name,
		})
	}
	return entries
}

func (m Model) Init() tea.Cmd {
	return m.spinner.Tick
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case runResultsMsg:
		return m.handleRunResults(msg)
	}

	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch m.state {
	case stateList:
		return m.handleListKey(msg)
	case stateRunning:
		if msg.Type == tea.KeyCtrlC {
			return m, tea.Quit
		}
		// Ignore other keys while running
		return m, nil
	case stateSummary:
		return m.handleSummaryKey(msg)
	case stateDetails:
		return m.handleDetailsKey(msg)
	case stateLog:
		return m.handleLogKey(msg)
	default:
		return m, nil
	}
}

func (m Model) handleListKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC:
		return m, tea.Quit
	case tea.KeyEsc:
		return m, tea.Quit
	case tea.KeyUp:
		if m.cursor > 0 {
			m.cursor--
			m.ensureCursorVisible()
		}
	case tea.KeyDown:
		if m.cursor+1 < len(m.filtered) {
			m.cursor++
			m.ensureCursorVisible()
		}
	case tea.KeyHome:
		m.cursor = 0
		m.ensureCursorVisible()
	case tea.KeyEnd:
		if len(m.filtered) > 0 {
			m.cursor = len(m.filtered) - 1
			m.ensureCursorVisible()
		}
	case tea.KeyPgUp:
		step := m.viewportHeight()
		if step < 1 {
			step = 1
		}
		if m.cursor-step < 0 {
			m.cursor = 0
		} else {
			m.cursor -= step
		}
		m.ensureCursorVisible()
	case tea.KeyPgDown:
		step := m.viewportHeight()
		if step < 1 {
			step = 1
		}
		if m.cursor+step >= len(m.filtered) {
			m.cursor = len(m.filtered) - 1
		} else {
			m.cursor += step
		}
		m.ensureCursorVisible()
	case tea.KeySpace:
		m.toggleSelection()
	case tea.KeyBackspace, tea.KeyCtrlH:
		if len(m.filter) > 0 {
			m.filter = m.filter[:len(m.filter)-1]
			m.applyFilter()
		}
	case tea.KeyDelete:
		if len(m.filter) > 0 {
			m.filter = ""
			m.applyFilter()
		}
	case tea.KeyEnter:
		return m.confirmSelection()
	default:
		if msg.Type == tea.KeyRunes {
			r := msg.String()
			if r != "" && r != " " && r != "+" && r != "-" {
				m.filter += r
				m.applyFilter()
			}
		} else if msg.String() == "+" {
			m.selectFiltered()
		} else if msg.String() == "-" {
			m.deselectFiltered()
		}
	}

	return m, nil
}

func (m *Model) toggleSelection() {
	if len(m.filtered) == 0 {
		return
	}

	idx := m.filtered[m.cursor]
	ent := m.entries[idx]
	if ent.typ != entryAction {
		return
	}

	if _, ok := m.selected[idx]; ok {
		delete(m.selected, idx)
	} else {
		m.selected[idx] = struct{}{}
	}
}

func (m *Model) selectFiltered() {
	for _, idx := range m.filtered {
		if m.entries[idx].typ != entryAction {
			continue
		}
		m.selected[idx] = struct{}{}
	}
}

func (m *Model) deselectFiltered() {
	for _, idx := range m.filtered {
		delete(m.selected, idx)
	}
}

func (m *Model) confirmSelection() (tea.Model, tea.Cmd) {
	if len(m.filtered) == 0 {
		return m, nil
	}

	// If cursor on details entry, open details view
	currentIdx := m.filtered[m.cursor]
	current := m.entries[currentIdx]
	if current.typ == entryDetails {
		m.openDetails(current.app)
		return m, nil
	}

	var actions []config.Action
	for idx := range m.selected {
		if m.entries[idx].typ != entryAction {
			continue
		}
		appActions := m.cfg.ActionsFor(m.entries[idx].app)
		for _, act := range appActions {
			if act.ActionName == m.entries[idx].action {
				actions = append(actions, act)
				break
			}
		}
	}

	if len(actions) == 0 {
		// No explicit selections - execute current entry
		appActions := m.cfg.ActionsFor(current.app)
		for _, act := range appActions {
			if act.ActionName == current.action {
				actions = append(actions, act)
				break
			}
		}
		if len(actions) == 0 {
			return m, nil
		}
		m.lastRunMode = executor.ModeInteractiveSingle
		return m.startRun(actions, executor.ModeInteractiveSingle)
	}

	// When selections exist, execute them all in batch
	// Ensure stable order: use filtered order to maintain UI semantics
	sort.SliceStable(actions, func(i, j int) bool {
		ai := m.indexOfEntry(actions[i])
		aj := m.indexOfEntry(actions[j])
		return ai < aj
	})

	m.lastRunMode = executor.ModeInteractiveBatch
	return m.startRun(actions, executor.ModeInteractiveBatch)
}

func (m *Model) indexOfEntry(action config.Action) int {
	for idx, ent := range m.entries {
		if ent.typ == entryAction && ent.app == action.AppName && ent.action == action.ActionName {
			return idx
		}
	}
	return -1
}

func (m *Model) startRun(actions []config.Action, mode executor.Mode) (tea.Model, tea.Cmd) {
	if len(actions) == 0 {
		return m, nil
	}

	m.state = stateRunning
	m.infoMessage = fmt.Sprintf("Running %d action(s)...", len(actions))
	m.errMessage = ""
	m.results = nil
	m.summaryCursor = 0
	m.logLines = nil
	m.logTitle = ""
	m.logScroll = 0

	cmd := runActionsCmd(m.runner, actions, mode)
	return m, tea.Batch(cmd, m.spinner.Tick)
}

func runActionsCmd(runner *executor.Runner, actions []config.Action, mode executor.Mode) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		switch mode {
		case executor.ModeInteractiveSingle:
			res := runner.Run(ctx, actions[0], executor.RunParams{Mode: executor.ModeInteractiveSingle})
			return runResultsMsg{Results: []executor.Result{res}, Mode: mode}
		case executor.ModeInteractiveBatch:
			res := runner.RunParallel(ctx, actions, executor.ModeInteractiveBatch)
			return runResultsMsg{Results: res, Mode: mode}
		case executor.ModeCI:
			res := runner.RunParallel(ctx, actions, executor.ModeCI)
			return runResultsMsg{Results: res, Mode: mode}
		default:
			return runResultsMsg{Results: nil, Mode: mode}
		}
	}
}

func (m Model) handleRunResults(msg runResultsMsg) (tea.Model, tea.Cmd) {
	ordered := orderResults(msg.Results)
	m.results = ordered
	m.state = stateSummary
	m.lastRunMode = msg.Mode
	m.infoMessage = fmt.Sprintf("Completed %d action(s)", len(msg.Results))
	m.selected = make(map[int]struct{})
	m.summaryCursor = 0
	return m, nil
}

func orderResults(results []executor.Result) []executor.Result {
	out := append([]executor.Result(nil), results...)
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Success == out[j].Success {
			return false
		}
		return !out[i].Success && out[j].Success
	})
	return out
}

func (m Model) handleSummaryKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC:
		return m, tea.Quit
	case tea.KeyEsc:
		m.state = stateList
		return m, nil
	case tea.KeyUp:
		if m.summaryCursor > 0 {
			m.summaryCursor--
		}
	case tea.KeyDown:
		if m.summaryCursor+1 < len(m.results) {
			m.summaryCursor++
		}
	case tea.KeyEnter:
		return m.openLogForCursor()
	default:
		if msg.String() == "q" {
			m.state = stateList
		} else if msg.String() == "l" {
			return m.openLogForCursor()
		}
	}

	return m, nil
}

func (m Model) openLogForCursor() (tea.Model, tea.Cmd) {
	if len(m.results) == 0 {
		return m, nil
	}

	res := m.results[m.summaryCursor]
	if strings.TrimSpace(res.LogPath) == "" {
		m.errMessage = "Log file not available (CI mode)"
		return m, nil
	}

	content, err := os.ReadFile(res.LogPath)
	if err != nil {
		m.errMessage = fmt.Sprintf("Unable to read log: %v", err)
		return m, nil
	}

	lines := strings.Split(string(content), "\n")
	m.logLines = lines
	m.logTitle = fmt.Sprintf("%s - %s", res.AppName, res.ActionName)
	m.logScroll = 0
	m.state = stateLog
	return m, nil
}

func (m Model) handleDetailsKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEnter, tea.KeyEsc:
		m.state = stateList
	case tea.KeyCtrlC:
		return m, tea.Quit
	default:
		if msg.String() == "q" {
			m.state = stateList
		}
	}
	return m, nil
}

func (m Model) handleLogKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC:
		return m, tea.Quit
	case tea.KeyEsc:
		m.state = stateSummary
	case tea.KeyUp:
		if m.logScroll > 0 {
			m.logScroll--
		}
	case tea.KeyDown:
		if m.logScroll+1 < len(m.logLines) {
			m.logScroll++
		}
	case tea.KeyPgUp:
		step := m.viewportHeight()
		if step < 1 {
			step = 1
		}
		if m.logScroll-step < 0 {
			m.logScroll = 0
		} else {
			m.logScroll -= step
		}
	case tea.KeyPgDown:
		step := m.viewportHeight()
		if step < 1 {
			step = 1
		}
		if m.logScroll+step >= len(m.logLines) {
			m.logScroll = len(m.logLines) - 1
		} else {
			m.logScroll += step
		}
	default:
		if msg.String() == "q" {
			m.state = stateSummary
		}
	}
	return m, nil
}

func (m *Model) openDetails(appName string) {
	app, ok := m.cfg.App(appName)
	if !ok {
		m.errMessage = fmt.Sprintf("Unknown application '%s'", appName)
		return
	}

	lines := []string{
		fmt.Sprintf("Application: %s", app.Name),
	}

	var workingDirDisplay string
	if strings.TrimSpace(m.cfg.ContainerCommand) != "" {
		if strings.TrimSpace(app.WorkingDirRaw) == "" {
			workingDirDisplay = "(container default)"
		} else {
			workingDirDisplay = app.WorkingDirRaw
		}
	} else {
		wd := app.WorkingDir
		if strings.TrimSpace(wd) == "" {
			wd = m.cfg.BaseDir
		}
		workingDirDisplay = wd
	}
	lines = append(lines, fmt.Sprintf("Working Dir: %s", workingDirDisplay))

	logDir := app.LogDir
	if logDir == "" {
		logDir = filepath.Join(m.cfg.BaseDir, "logs")
	}
	lines = append(lines, fmt.Sprintf("Log Dir: %s", logDir))

	if m.cfg.ContainerCommand != "" {
		lines = append(lines, fmt.Sprintf("Container: %s", m.cfg.ContainerCommand))
	} else {
		lines = append(lines, "Container: (host)")
	}

	lines = append(lines, "")
	lines = append(lines, "Actions:")
	for _, action := range m.cfg.ActionsFor(appName) {
		lines = append(lines, fmt.Sprintf("  - %s", action.ActionName))
		lines = append(lines, fmt.Sprintf("    %s", action.Command))
	}

	m.state = stateDetails
	m.detailsTitle = fmt.Sprintf("Details - %s", appName)
	m.detailsLines = lines
}

func (m *Model) applyFilter() {
	m.filtered = m.filtered[:0]
	lower := strings.ToLower(m.filter)
	for idx, ent := range m.entries {
		if lower == "" || entryMatches(ent, lower) {
			m.filtered = append(m.filtered, idx)
		}
	}

	if m.cursor >= len(m.filtered) {
		m.cursor = len(m.filtered) - 1
		if m.cursor < 0 {
			m.cursor = 0
		}
	}
	m.ensureCursorVisible()
}

func entryMatches(ent entry, lowerFilter string) bool {
	if lowerFilter == "" {
		return true
	}

	lowerApp := strings.ToLower(ent.app)
	if strings.Contains(lowerApp, lowerFilter) {
		return true
	}

	if ent.typ == entryDetails {
		return strings.Contains("show details", lowerFilter)
	}

	lowerAction := strings.ToLower(ent.action)
	if strings.Contains(lowerAction, lowerFilter) {
		return true
	}

	lowerCommand := strings.ToLower(ent.command)
	return strings.Contains(lowerCommand, lowerFilter)
}

func (m *Model) ensureCursorVisible() {
	if len(m.filtered) == 0 {
		m.cursor = 0
		m.scroll = 0
		return
	}

	vp := m.viewportHeight()
	if vp <= 0 {
		vp = len(m.filtered)
	}

	if m.cursor < m.scroll {
		m.scroll = m.cursor
	} else if m.cursor >= m.scroll+vp {
		m.scroll = m.cursor - vp + 1
	}

	if m.scroll < 0 {
		m.scroll = 0
	}
	maxScroll := len(m.filtered) - vp
	if maxScroll < 0 {
		maxScroll = 0
	}
	if m.scroll > maxScroll {
		m.scroll = maxScroll
	}
}

func (m Model) View() string {
	switch m.state {
	case stateList:
		return m.viewList()
	case stateRunning:
		return m.viewRunning()
	case stateSummary:
		return m.viewSummary()
	case stateDetails:
		return m.viewDetails()
	case stateLog:
		return m.viewLog()
	default:
		return ""
	}
}

func (m Model) viewList() string {
	b := &strings.Builder{}
	fmt.Fprintf(b, "%s\n", m.styles.header.Render("Shell-Bun"))
	fmt.Fprintf(b, "%s\n", m.styles.help.Render("Navigation: ↑/↓ PgUp/PgDn Home/End | Type: filter | Space: select | Enter: execute | + select visible | - clear visible | ESC: quit"))
	fmt.Fprintf(b, "%s\n", m.styles.filter.Render(fmt.Sprintf("Filter: %s", m.filter)))
	fmt.Fprintf(b, "%s\n", m.styles.filter.Render(fmt.Sprintf("Selected: %d", len(m.selected))))

	if m.errMessage != "" {
		fmt.Fprintf(b, "%s\n", m.styles.warning.Render(m.errMessage))
	} else if m.infoMessage != "" {
		fmt.Fprintf(b, "%s\n", m.styles.help.Render(m.infoMessage))
	}

	fmt.Fprintln(b)

	if len(m.filtered) == 0 {
		fmt.Fprintf(b, "%s\n", m.styles.warning.Render("No matching entries"))
		return b.String()
	}

	vp := m.viewportHeight()
	if vp <= 0 {
		vp = len(m.filtered)
	}

	end := m.scroll + vp
	if end > len(m.filtered) {
		end = len(m.filtered)
	}

	if m.scroll > 0 {
		fmt.Fprintf(b, "%s\n", m.styles.dimmed.Render(fmt.Sprintf("... %d more item(s) above ...", m.scroll)))
	}

	for i := m.scroll; i < end; i++ {
		idx := m.filtered[i]
		ent := m.entries[idx]

		marker := " "
		if i == m.cursor {
			marker = "►"
		}

		selectedMarker := "[ ]"
		if _, ok := m.selected[idx]; ok {
			selectedMarker = "[✓]"
		}

		line := ""
		if ent.typ == entryAction {
			line = fmt.Sprintf("%s %s %s - %s", marker, selectedMarker, ent.app, ent.action)
		} else {
			line = fmt.Sprintf("%s     %s - Show Details", marker, ent.app)
		}

		if i == m.cursor {
			fmt.Fprintf(b, "%s\n", m.styles.currentItem.Render(line))
		} else if _, ok := m.selected[idx]; ok {
			fmt.Fprintf(b, "%s\n", m.styles.selectedItem.Render(line))
		} else {
			fmt.Fprintf(b, "%s\n", line)
		}
	}

	if end < len(m.filtered) {
		remaining := len(m.filtered) - end
		fmt.Fprintf(b, "%s\n", m.styles.dimmed.Render(fmt.Sprintf("... %d more item(s) below ...", remaining)))
	}

	return b.String()
}

func (m Model) viewRunning() string {
	msg := fmt.Sprintf("%s %s", m.spinner.View(), m.infoMessage)
	return m.styles.header.Render("Executing...") + "\n\n" + msg + "\n\nPress Ctrl+C to abort"
}

func (m Model) viewSummary() string {
	b := &strings.Builder{}
	fmt.Fprintf(b, "%s\n", m.styles.header.Render("Execution Summary"))

	successes := 0
	failures := 0
	for _, res := range m.results {
		if res.Success {
			successes++
		} else {
			failures++
		}
	}

	fmt.Fprintf(b, "Commands executed: %d\n", len(m.results))
	fmt.Fprintf(b, "%s\n", m.styles.successBadge.Render(fmt.Sprintf("✅ Success: %d", successes)))
	fmt.Fprintf(b, "%s\n", m.styles.failureBadge.Render(fmt.Sprintf("❌ Failed: %d", failures)))

	if m.errMessage != "" {
		fmt.Fprintf(b, "%s\n", m.styles.warning.Render(m.errMessage))
	}

	fmt.Fprintf(b, "\n%s\n", m.styles.help.Render("Enter/l to view log | q/Esc to return"))

	for i, res := range m.results {
		icon := "✅"
		style := m.styles.selectedItem
		if !res.Success {
			icon = "❌"
			style = m.styles.failureBadge
		}

		line := fmt.Sprintf("%s %s - %s", icon, res.AppName, res.ActionName)
		if !res.Success && res.Err != nil {
			line = fmt.Sprintf("%s (%v)", line, res.Err)
		}
		if i == m.summaryCursor {
			fmt.Fprintf(b, "%s\n", m.styles.currentItem.Render(line))
		} else {
			fmt.Fprintf(b, "%s\n", style.Render(line))
		}
	}

	return b.String()
}

func (m Model) viewDetails() string {
	b := &strings.Builder{}
	fmt.Fprintf(b, "%s\n\n", m.styles.header.Render(m.detailsTitle))
	for _, line := range m.detailsLines {
		fmt.Fprintf(b, "%s\n", line)
	}
	fmt.Fprintf(b, "\n%s\n", m.styles.help.Render("Press Enter/q/Esc to return"))
	return b.String()
}

func (m Model) viewLog() string {
	b := &strings.Builder{}
	fmt.Fprintf(b, "%s\n", m.styles.header.Render(fmt.Sprintf("Log Viewer - %s", m.logTitle)))
	fmt.Fprintf(b, "%s\n\n", m.styles.help.Render("Esc/q to summary | ↑/↓ scroll | PgUp/PgDn page"))

	vp := m.viewportHeight()
	if vp <= 0 {
		vp = len(m.logLines)
	}

	end := m.logScroll + vp
	if end > len(m.logLines) {
		end = len(m.logLines)
	}

	for i := m.logScroll; i < end; i++ {
		fmt.Fprintf(b, "%s\n", m.logLines[i])
	}

	if end < len(m.logLines) {
		fmt.Fprintf(b, "%s\n", m.styles.dimmed.Render("-- more --"))
	}

	return b.String()
}

func (m Model) viewportHeight() int {
	if m.height <= 0 {
		return 15
	}
	// Reserve space for headers/help lines (~7 lines)
	vp := m.height - 7
	if vp < 3 {
		vp = 3
	}
	return vp
}
