package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// errAborted is returned by the TUI helpers when the user cancels
// (Ctrl-C/Esc) rather than picking a value.
var errAborted = errors.New("aborted by user")

// isInteractiveTTY reports whether both stdin and stdout look like a
// real terminal. When false, TUI prompts are skipped entirely in favor of
// flags/inference, per the plan's non-interactive-friendly requirement.
func isInteractiveTTY() bool {
	return isTerminal(os.Stdin) && isTerminal(os.Stdout)
}

func isTerminal(f *os.File) bool {
	info, err := f.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}

// listItem is the minimal bubbles/list.Item implementation for a plain
// string option.
type listItem string

func (i listItem) FilterValue() string { return string(i) }

// simpleDelegate renders a listItem as "<cursor><text>", with no external
// styling dependency.
type simpleDelegate struct{}

func (d simpleDelegate) Height() int                             { return 1 }
func (d simpleDelegate) Spacing() int                            { return 0 }
func (d simpleDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }
func (d simpleDelegate) Render(w io.Writer, m list.Model, index int, li list.Item) {
	it, ok := li.(listItem)
	if !ok {
		return
	}
	cursor := "  "
	if index == m.Index() {
		cursor = "> "
	}
	fmt.Fprintf(w, "%s%s", cursor, string(it))
}

// --- plain single-list selection (used for commit type) ---

type selectModel struct {
	list    list.Model
	choice  string
	aborted bool
}

func newSelectModel(title string, options []string, defaultIdx int) selectModel {
	items := make([]list.Item, len(options))
	for i, o := range options {
		items[i] = listItem(o)
	}
	l := list.New(items, simpleDelegate{}, 60, 14)
	l.Title = title
	l.SetShowStatusBar(false)
	l.SetShowHelp(false)
	l.SetFilteringEnabled(false)
	if defaultIdx >= 0 && defaultIdx < len(options) {
		l.Select(defaultIdx)
	}
	return selectModel{list: l}
}

func (m selectModel) Init() tea.Cmd { return nil }

func (m selectModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetSize(msg.Width, msg.Height)
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.aborted = true
			return m, tea.Quit
		case "enter":
			if it, ok := m.list.SelectedItem().(listItem); ok {
				m.choice = string(it)
			}
			return m, tea.Quit
		}
	}
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m selectModel) View() string {
	return m.list.View()
}

// runListSelect drives a bubbletea program presenting options as a
// navigable list; Enter confirms, Ctrl-C/Esc aborts (errAborted).
func runListSelect(title string, options []string, defaultIdx int) (string, error) {
	m := newSelectModel(title, options, defaultIdx)
	p := tea.NewProgram(m)
	finalModel, err := p.Run()
	if err != nil {
		return "", err
	}
	fm, ok := finalModel.(selectModel)
	if !ok {
		return "", errAborted
	}
	if fm.aborted || fm.choice == "" {
		return "", errAborted
	}
	return fm.choice, nil
}

// resolveCommitType resolves the commit type: --type override first, then
// (non-TTY) rule inference only, then (TTY) the bubbletea list.
func resolveCommitType(defaults commitDefaults) (string, error) {
	if defaults.typeOverride != "" {
		debugf("using --type override: %s", defaults.typeOverride)
		return defaults.typeOverride, nil
	}
	if !isInteractiveTTY() {
		if defaults.typeDefault != "" {
			debugf("non-TTY stdin/stdout: using inferred type %q", defaults.typeDefault)
			return defaults.typeDefault, nil
		}
		return "", fmt.Errorf("stdin/stdout is not a terminal and no --type flag or rule inference resolved a commit type")
	}
	idx := -1
	for i, t := range commitTypes {
		if t == defaults.typeDefault {
			idx = i
		}
	}
	chosen, err := runListSelect("Commit type:", commitTypes, idx)
	if err != nil {
		return "", err
	}
	return chosen, nil
}

// --- list selection with a "custom text entry" escape hatch (used for scope) ---

type scopeSelectModel struct {
	list        list.Model
	input       textinput.Model
	typing      bool
	choice      string
	aborted     bool
	noScope     string
	customLabel string
}

func newScopeSelectModel(title string, options []string, noScopeLabel, customLabel string) scopeSelectModel {
	items := make([]list.Item, len(options))
	for i, o := range options {
		items[i] = listItem(o)
	}
	l := list.New(items, simpleDelegate{}, 60, 14)
	l.Title = title
	l.SetShowStatusBar(false)
	l.SetShowHelp(false)
	l.SetFilteringEnabled(false)

	ti := textinput.New()
	ti.Placeholder = "scope"
	ti.CharLimit = 64

	return scopeSelectModel{list: l, input: ti, noScope: noScopeLabel, customLabel: customLabel}
}

func (m scopeSelectModel) Init() tea.Cmd { return nil }

func (m scopeSelectModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.typing {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch msg.String() {
			case "ctrl+c", "esc":
				m.aborted = true
				return m, tea.Quit
			case "enter":
				m.choice = strings.TrimSpace(m.input.Value())
				return m, tea.Quit
			}
		}
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetSize(msg.Width, msg.Height)
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.aborted = true
			return m, tea.Quit
		case "enter":
			it, ok := m.list.SelectedItem().(listItem)
			if !ok {
				return m, nil
			}
			switch string(it) {
			case m.noScope:
				m.choice = ""
				return m, tea.Quit
			case m.customLabel:
				m.typing = true
				m.input.Focus()
				return m, textinput.Blink
			default:
				m.choice = string(it)
				return m, tea.Quit
			}
		}
	}
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m scopeSelectModel) View() string {
	if m.typing {
		return fmt.Sprintf("Enter custom scope:\n\n%s\n\n(enter to confirm, esc to cancel)", m.input.View())
	}
	return m.list.View()
}

const (
	noScopeLabel    = "(no scope)"
	customScopeMenu = "Enter custom scope..."
)

// resolveScopeTUI presents every known scope (cog.toml package names plus
// any scope values referenced in inference-rules.json) as a list, with a
// "(no scope)" option and a free-text "Enter custom scope..." escape
// hatch. Only called when no scope was resolved by flag/package/inference
// and stdin/stdout is an interactive TTY.
func resolveScopeTUI(knownScopes []string) (string, error) {
	options := append([]string{noScopeLabel}, knownScopes...)
	options = append(options, customScopeMenu)

	m := newScopeSelectModel("Scope:", options, noScopeLabel, customScopeMenu)
	p := tea.NewProgram(m)
	finalModel, err := p.Run()
	if err != nil {
		return "", err
	}
	fm, ok := finalModel.(scopeSelectModel)
	if !ok {
		return "", errAborted
	}
	if fm.aborted {
		return "", errAborted
	}
	return fm.choice, nil
}
