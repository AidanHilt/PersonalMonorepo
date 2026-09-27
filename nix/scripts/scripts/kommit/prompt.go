package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

var stdinReader = bufio.NewReader(os.Stdin)

func selectPrompt(label string, options []string, defaultIdx int) (string, error) {
	fmt.Printf("%s\n", label)
	for i, opt := range options {
		marker := " "
		if i == defaultIdx {
			marker = "*"
		}
		fmt.Printf("  %s %d) %s\n", marker, i+1, opt)
	}
	if defaultIdx >= 0 {
		fmt.Printf("Choice [%d]: ", defaultIdx+1)
	} else {
		fmt.Print("Choice: ")
	}
	line, err := readLine()
	if err != nil {
		return "", err
	}
	if line == "" {
		if defaultIdx < 0 {
			fmt.Println("a selection is required")
			return selectPrompt(label, options, defaultIdx)
		}
		return options[defaultIdx], nil
	}
	n, err := strconv.Atoi(line)
	if err != nil || n < 1 || n > len(options) {
		fmt.Println("invalid choice, try again")
		return selectPrompt(label, options, defaultIdx)
	}
	return options[n-1], nil
}

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
