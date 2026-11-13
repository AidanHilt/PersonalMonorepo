package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// promptChoice is the user's answer to one approval dialog.
type promptChoice int

const (
	choiceDeny promptChoice = iota
	choiceAllowOnce
	choiceAllowSession
)

// prompter shows one approval dialog and blocks until the user answers or
// ctx is cancelled (prompt timeout, or helper shutdown). An error return
// means "fail closed": the caller must treat it as a denial, never as a
// grant -- see PLAN.md's "Approval helper (host side)" decision row.
type prompter interface {
	Prompt(ctx context.Context, info capabilityInfo) (promptChoice, error)
}

// denyAllPrompter never shows anything and always denies immediately.
// Used for `--ui deny-all` and as the final fallback when no interactive
// UI can be found at all (e.g. a headless host with no tmux).
type denyAllPrompter struct{}

func (denyAllPrompter) Prompt(context.Context, capabilityInfo) (promptChoice, error) {
	return choiceDeny, nil
}

func promptMessage(info capabilityInfo) string {
	reason := info.Reason
	if reason == "" {
		reason = "(no reason given)"
	}
	return fmt.Sprintf(
		"pi sandbox network approval request\nhost: %s\nport: %d\nprotocol: %s\nreason: %s",
		info.Host, info.Port, info.Protocol, reason,
	)
}

// osascriptPrompter shows a native macOS dialog with three buttons via
// osascript. UNVERIFIED: no macOS spike has exercised this (PLAN.md
// section 3/6 -- "the entire harness on macOS... is UNTESTED"); this is a
// best-effort implementation only.
type osascriptPrompter struct {
	lookPath func(string) (string, error)
}

func (p *osascriptPrompter) Prompt(ctx context.Context, info capabilityInfo) (promptChoice, error) {
	if _, err := p.lookPath("osascript"); err != nil {
		return choiceDeny, err
	}
	script := fmt.Sprintf(
		`display dialog %s with title "pi sandbox" buttons {"Deny", "Allow once", "Allow for session"} default button "Deny"`,
		appleScriptQuote(promptMessage(info)),
	)
	out, err := exec.CommandContext(ctx, "osascript", "-e", script).Output()
	if err != nil {
		// Covers both a real failure and the user dismissing the dialog
		// (osascript exits non-zero on Cancel) -- fail closed either way.
		return choiceDeny, err
	}
	return parseButtonOutput(string(out)), nil
}

func appleScriptQuote(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	s = strings.ReplaceAll(s, "\n", "\\n")
	return `"` + s + `"`
}

func parseButtonOutput(out string) promptChoice {
	switch {
	case strings.Contains(out, "Allow for session"):
		return choiceAllowSession
	case strings.Contains(out, "Allow once"):
		return choiceAllowOnce
	default:
		return choiceDeny
	}
}

// kdialogPrompter shows a three-option menu via kdialog, for KDE Plasma
// desktops (mono-flake's `linux-desktop` role). UNVERIFIED: no spike
// exercised kdialog's exact CLI/output shape; this is a best-effort
// implementation based on kdialog's documented --menu behaviour (prints
// the chosen option's tag to stdout, exits non-zero on Cancel).
type kdialogPrompter struct {
	lookPath func(string) (string, error)
}

func (p *kdialogPrompter) Prompt(ctx context.Context, info capabilityInfo) (promptChoice, error) {
	if _, err := p.lookPath("kdialog"); err != nil {
		return choiceDeny, err
	}
	cmd := exec.CommandContext(ctx, "kdialog",
		"--title", "pi sandbox",
		"--menu", promptMessage(info),
		"deny", "Deny",
		"once", "Allow once",
		"session", "Allow for session",
	)
	out, err := cmd.Output()
	if err != nil {
		// kdialog exits non-zero on Cancel/Escape -- fail closed.
		return choiceDeny, err
	}
	switch strings.TrimSpace(string(out)) {
	case "once":
		return choiceAllowOnce, nil
	case "session":
		return choiceAllowSession, nil
	default:
		return choiceDeny, nil
	}
}

// tmuxPrompter asks a y/n/s question via a tmux command-prompt, for
// headless hosts with no desktop session (e.g. mono-flake's aarch64
// `devbox`, per PLAN.md). UNVERIFIED: no spike exercised tmux
// integration; this is a best-effort implementation.
type tmuxPrompter struct {
	lookPath func(string) (string, error)
}

func (p *tmuxPrompter) Prompt(ctx context.Context, info capabilityInfo) (promptChoice, error) {
	if _, err := p.lookPath("tmux"); err != nil {
		return choiceDeny, err
	}

	answerFile, err := os.CreateTemp("", "pi-approval-answer-*")
	if err != nil {
		return choiceDeny, err
	}
	answerPath := answerFile.Name()
	_ = answerFile.Close()
	defer func() { _ = os.Remove(answerPath) }()

	prompt := strings.ReplaceAll(promptMessage(info), "\n", " ") + " [y=allow once / n=deny / s=allow session]: "
	// command-prompt's template is a tmux command (not a shell command
	// line): %1 is substituted with the text the user typed once they
	// press Enter. run-shell then hands that one word to a real shell,
	// which writes it to answerPath for this process to poll.
	template := "run-shell \"printf '%s' %1 > " + answerPath + "\""
	cmd := exec.CommandContext(ctx, "tmux", "command-prompt", "-p", prompt, template)
	if err := cmd.Run(); err != nil {
		return choiceDeny, err
	}

	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return choiceDeny, ctx.Err()
		case <-ticker.C:
			data, err := os.ReadFile(answerPath)
			if err != nil {
				continue
			}
			answer := strings.ToLower(strings.TrimSpace(string(data)))
			if answer == "" {
				continue
			}
			switch {
			case strings.HasPrefix(answer, "y"):
				return choiceAllowOnce, nil
			case strings.HasPrefix(answer, "s"):
				return choiceAllowSession, nil
			default:
				return choiceDeny, nil
			}
		}
	}
}

// selectPrompter picks a prompter for `--ui` mode m ("auto", "osascript",
// "kdialog", "tmux", or "deny-all"). goos/lookPath/getenv are explicit
// parameters (rather than runtime.GOOS/exec.LookPath/os.Getenv read
// directly) so tests can exercise every branch without being tied to the
// actual OS/environment the test happens to run under.
func selectPrompter(mode, goos string, lookPath func(string) (string, error), getenv func(string) string) (prompter, error) {
	switch mode {
	case "deny-all":
		return denyAllPrompter{}, nil
	case "osascript":
		return &osascriptPrompter{lookPath: lookPath}, nil
	case "kdialog":
		return &kdialogPrompter{lookPath: lookPath}, nil
	case "tmux":
		return &tmuxPrompter{lookPath: lookPath}, nil
	case "", "auto":
		if goos == "darwin" {
			if _, err := lookPath("osascript"); err == nil {
				return &osascriptPrompter{lookPath: lookPath}, nil
			}
		}
		if goos == "linux" && (getenv("DISPLAY") != "" || getenv("WAYLAND_DISPLAY") != "") {
			if _, err := lookPath("kdialog"); err == nil {
				return &kdialogPrompter{lookPath: lookPath}, nil
			}
		}
		if _, err := lookPath("tmux"); err == nil {
			return &tmuxPrompter{lookPath: lookPath}, nil
		}
		// No desktop session and no tmux: fail closed rather than guess
		// at another UI.
		return denyAllPrompter{}, nil
	default:
		return nil, fmt.Errorf("unknown --ui mode %q (want auto|osascript|kdialog|tmux|deny-all)", mode)
	}
}
