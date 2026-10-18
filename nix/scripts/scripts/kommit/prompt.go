package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

var stdinReader = bufio.NewReader(os.Stdin)

// Note: the numbered-list selectPrompt that used to live here for commit
// type selection was replaced by the bubbletea list TUI in tui.go
// (resolveCommitType/runListSelect), per plan step 1. textPrompt is kept
// around for the preset scope fallback (main.go/runPresetCommit), which
// is intentionally left as free text rather than ported to the TUI --
// the plan's generalized scope-inference TUI fallback (tui.go's
// resolveScopeTUI) only applies to the main (non-preset) commit path.

func textPrompt(label, defaultVal string) (string, error) {
	if defaultVal != "" {
		fmt.Printf("%s [%s]: ", label, defaultVal)
	} else {
		fmt.Printf("%s: ", label)
	}
	line, err := readLine()
	if err != nil {
		return "", err
	}
	if line == "" {
		return defaultVal, nil
	}
	return line, nil
}

func requiredTextPrompt(label string) (string, error) {
	for {
		line, err := textPrompt(label, "")
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(line) != "" {
			return line, nil
		}
		fmt.Println("this field is required")
	}
}

func confirmPrompt(label string, defaultYes bool) (bool, error) {
	hint := "y/N"
	if defaultYes {
		hint = "Y/n"
	}
	fmt.Printf("%s [%s]: ", label, hint)
	line, err := readLine()
	if err != nil {
		return false, err
	}
	line = strings.ToLower(strings.TrimSpace(line))
	if line == "" {
		return defaultYes, nil
	}
	return line == "y" || line == "yes", nil
}

func readLine() (string, error) {
	line, err := stdinReader.ReadString('\n')
	if err != nil && line == "" {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

// editorPrompt opens $EDITOR on a temp file pre-filled with template,
// waits for it to close, then returns the content with '#'-prefixed
// instructional comment lines stripped.
func editorPrompt(template string) (string, error) {
	tmp, err := os.CreateTemp("", "kommit-body-*.txt")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(template); err != nil {
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}

	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vi"
	}
	cmd := exec.Command(editor, tmp.Name())
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", err
	}

	data, err := os.ReadFile(tmp.Name())
	if err != nil {
		return "", err
	}

	var kept []string
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		kept = append(kept, line)
	}
	return strings.TrimSpace(strings.Join(kept, "\n")), nil
}
