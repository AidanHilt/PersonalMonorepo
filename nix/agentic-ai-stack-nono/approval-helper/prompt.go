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
// grant.
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
// osascript.
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
// desktops. Based on kdialog's documented --menu behaviour (prints the
// chosen option's tag to stdout, exits non-zero on Cancel).
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
// headless hosts with no desktop session.
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
//
// On success, the second return value is a short, human-readable
// description of the prompter chosen (and why) -- the caller (main.go) is
// expected to log it at startup. `auto` NEVER silently falls back to
// denyAllPrompter any more: if no usable UI can be found, this returns an
// error with an actionable message instead, so a misconfigured host fails
// loudly at helper startup rather than silently denying every approval
// later. `deny-all` remains available, but only via an explicit `--ui
// deny-all`.
func selectPrompter(mode, goos string, lookPath func(string) (string, error), getenv func(string) string) (prompter, string, error) {
	switch mode {
	case "deny-all":
		return denyAllPrompter{}, "explicit --ui deny-all (never prompts, always denies)", nil
	case "osascript":
		return &osascriptPrompter{lookPath: lookPath}, "explicit --ui osascript", nil
	case "kdialog":
		return &kdialogPrompter{lookPath: lookPath}, "explicit --ui kdialog", nil
	case "tmux":
		return &tmuxPrompter{lookPath: lookPath}, "explicit --ui tmux (requires $TMUX to be set once a prompt is actually shown)", nil
	case "", "auto":
		// overSSH: kdialog/osascript dialogs can't reach an SSH client's
		// local display even when DISPLAY/WAYLAND_DISPLAY happen to be set
		// in the remote shell (X11 forwarding quirks, stale env, etc.) --
		// over SSH we only ever trust tmux.
		overSSH := getenv("SSH_CONNECTION") != "" || getenv("SSH_TTY") != ""
		hasDisplay := getenv("DISPLAY") != "" || getenv("WAYLAND_DISPLAY") != ""
		inTmux := getenv("TMUX") != ""

		if goos == "darwin" {
			if _, err := lookPath("osascript"); err == nil {
				return &osascriptPrompter{lookPath: lookPath}, "auto: osascript prompter (darwin)", nil
			}
		}
		if goos == "linux" && hasDisplay && !overSSH {
			if _, err := lookPath("kdialog"); err == nil {
				return &kdialogPrompter{lookPath: lookPath}, "auto: kdialog prompter (DISPLAY/WAYLAND_DISPLAY set, not an SSH session)", nil
			}
		}
		// tmux fallback: both the darwin-no-osascript and the linux-no-
		// desktop-or-over-SSH cases land here. Only trusted when $TMUX is
		// actually set (i.e. this process itself is running inside a tmux
		// session/server it can reach) -- a bare `tmux` on PATH with no
		// $TMUX means there's no server to send a command-prompt to.
		if inTmux {
			if _, err := lookPath("tmux"); err == nil {
				return &tmuxPrompter{lookPath: lookPath}, "auto: tmux prompter ($TMUX set)", nil
			}
		}
		// Nothing usable: fail loudly rather than silently falling back to
		// deny-all -- a silent deny-all here is exactly what made approvals
		// look "broken" for no visible reason over SSH.
		return nil, "", fmt.Errorf(
			"no approval UI available (auto): over SSH/headless, start tmux first and launch from inside it (so $TMUX is set); or pass --ui deny-all explicitly to fail closed on purpose",
		)
	default:
		return nil, "", fmt.Errorf("unknown --ui mode %q (want auto|osascript|kdialog|tmux|deny-all)", mode)
	}
}
