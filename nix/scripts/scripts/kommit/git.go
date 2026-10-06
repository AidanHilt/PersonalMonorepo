package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path"
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

// hasUpstream reports whether the current branch has an upstream
// configured; a non-nil error from git (e.g. no upstream set) is treated
// as "no upstream" rather than propagated.
func hasUpstream() bool {
	_, err := runGit("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
	return err == nil
}

// pushCurrent pushes the current branch to its configured upstream.
func pushCurrent() error {
	_, err := runGit("push")
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

// commitWithMessage writes the message to a stable, discoverable path
// under the repo's .git dir (rather than an os.CreateTemp auto-named
// file) and only removes it once git commit has actually succeeded, so a
// pre-commit hook failure leaves a resumable file behind instead of
// silently deleting the user's composed message (plan step 5).
//
// If the initial commit fails, the working tree is snapshotted before and
// after: if a pre-commit hook modified/reformatted tracked files (the
// snapshot differs), those paths are re-staged (git add -A, acceptable
// here since this is hook-recovery, not the original user-staging path)
// and the commit is retried exactly once. If nothing changed, or the
// retry also fails, the error and the message file's path are surfaced to
// the caller and the file is left in place for manual resume via
// `git commit -F <path>`.
func commitWithMessage(message string) error {
	root, err := repoRoot()
	if err != nil {
		return err
	}
	msgPath := path.Join(root, ".git", "KOMMIT_MSG.txt")
	if err := os.WriteFile(msgPath, []byte(message), 0o644); err != nil {
		return err
	}

	before, err := runGit("status", "--porcelain")
	if err != nil {
		return err
	}

	if _, commitErr := runGit("commit", "-F", msgPath); commitErr == nil {
		os.Remove(msgPath)
		return nil
	} else {
		warnf("commit failed, checking whether a pre-commit hook modified the tree: %v", commitErr)

		after, statusErr := runGit("status", "--porcelain")
		if statusErr != nil {
			warnf("could not re-check working tree after failed commit: %v", statusErr)
			return commitFailureError(commitErr, msgPath)
		}

		if after == before {
			debugf("working tree unchanged after hook failure; not retrying")
			return commitFailureError(commitErr, msgPath)
		}

		debugf("working tree changed after hook failure; re-staging and retrying commit once")
		if addErr := addAll(); addErr != nil {
			warnf("could not re-stage after hook modified files: %v", addErr)
			return commitFailureError(commitErr, msgPath)
		}

		if _, retryErr := runGit("commit", "-F", msgPath); retryErr != nil {
			return commitFailureError(retryErr, msgPath)
		}

		os.Remove(msgPath)
		statusf("commit succeeded on retry after a pre-commit hook modified files")
		return nil
	}
}

func commitFailureError(commitErr error, msgPath string) error {
	return fmt.Errorf("%w\ncommit message preserved at: %s\nresume with: git commit -F %s", commitErr, msgPath, msgPath)
}

func splitLines(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
