package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func runGit(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimRight(string(out), "\n"), nil
}

func repoRoot() (string, error) {
	return runGit("rev-parse", "--show-toplevel")
}

func stagedFiles() ([]string, error) {
	out, err := runGit("diff", "--staged", "--name-only")
	if err != nil {
		return nil, err
	}
	return splitLines(out), nil
}

// partiallyStagedFiles returns the set of files that have both staged and
// unstaged changes (git status "MM"-style codes), meaning a re-add would
// pull in more than what was originally staged.
func partiallyStagedFiles() (map[string]bool, error) {
	out, err := runGit("status", "--porcelain")
	if err != nil {
		return nil, err
	}
	result := map[string]bool{}
	for _, line := range splitLines(out) {
		if len(line) < 4 {
			continue
		}
		index := line[0]
		worktree := line[1]
		file := strings.TrimSpace(line[3:])
		if index != ' ' && index != '?' && worktree != ' ' && worktree != '?' {
			result[file] = true
		}
	}
	return result, nil
}

// stagedAddedLines returns the added ('+') lines from the staged diff of a
// single file, used for content-based rule matching.
func stagedAddedLines(file string) ([]string, error) {
	out, err := runGit("diff", "--staged", "--unified=0", "--", file)
	if err != nil {
		return nil, err
	}
	var added []string
	scanner := bufio.NewScanner(strings.NewReader(out))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "+++") {
			continue
		}
		if strings.HasPrefix(line, "+") {
			added = append(added, strings.TrimPrefix(line, "+"))
		}
	}
	return added, nil
}

func resetStaged() error {
	_, err := runGit("reset")
	return err
}

// addAll stages every change in the working tree, tracked or untracked,
// including dotfiles - git's own pathspec matching has no special-casing
// of dotfiles the way old shell globs did.
func addAll() error {
	_, err := runGit("add", "-A")
	return err
}

// stagePaths stages exactly the given paths if any are provided, otherwise
// falls back to staging everything.
func stagePaths(paths []string) error {
	if len(paths) > 0 {
		return addFiles(paths)
	}
	return addAll()
}

// addFilesLenient stages each path independently, skipping (and warning
// about) any that match nothing rather than aborting the whole batch. Used
// for a preset's own default paths, which are candidates that may not all
// apply to every invocation (e.g. an npm lockfile that doesn't exist for a
// yarn-managed package).
func addFilesLenient(paths []string) []string {
	var staged []string
	for _, p := range paths {
		if _, err := runGit("add", "--", p); err != nil {
			warnf("skipping %s (no match)", p)
			continue
		}
		staged = append(staged, p)
	}
	return staged
}

func addFiles(files []string) error {
	if len(files) == 0 {
		return nil
	}
	args := append([]string{"add", "--"}, files...)
	_, err := runGit(args...)
	return err
}

func commitWithMessage(message string) error {
	tmp, err := os.CreateTemp("", "kommit-msg-*.txt")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(message); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	_, err = runGit("commit", "-F", tmp.Name())
	return err
}

func splitLines(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
