package main

import (
	"fmt"
	"strings"
)

var commitTypes = []string{
	"feat", "fix", "chore", "docs", "style", "refactor",
	"perf", "test", "build", "ci", "revert",
}

func buildCommitMessage(commitType, scope, description string, breaking bool, body string) string {
	var head strings.Builder
	head.WriteString(commitType)
	if scope != "" {
		head.WriteString("(")
		head.WriteString(scope)
		head.WriteString(")")
	}
	if breaking {
		head.WriteString("!")
	}
	head.WriteString(": ")
	head.WriteString(description)

	parts := []string{head.String()}
	if strings.TrimSpace(body) != "" {
		parts = append(parts, strings.TrimSpace(body))
	}
	return strings.Join(parts, "\n\n")
}

type commitDefaults struct {
	typeOverride  string
	scopeOverride string
	typeDefault   string
	scopeDefault  string
}

// runInteractiveCommit walks the user through building and creating one
// commit covering the given (already staged) files.
func runInteractiveCommit(files []string, defaults commitDefaults) error {
	commitType := defaults.typeOverride
	if commitType == "" {
		idx := 0
		for i, t := range commitTypes {
			if t == defaults.typeDefault {
				idx = i
			}
		}
		if defaults.typeDefault == "" {
			idx = -1
		}
		chosen, err := selectPrompt("Commit type:", commitTypes, idx)
		if err != nil {
			return err
		}
		commitType = chosen
	} else {
		debugf("using --type override: %s", commitType)
	}

	scope := defaults.scopeOverride
	if scope == "" {
		chosen, err := textPrompt("Scope (optional)", defaults.scopeDefault)
		if err != nil {
			return err
		}
		scope = chosen
	} else {
		debugf("using --scope override: %s", scope)
	}

	description, err := requiredTextPrompt("Short description")
	if err != nil {
		return err
	}

	breaking, err := confirmPrompt("Breaking change?", false)
	if err != nil {
		return err
	}

	template := buildEditorTemplate(commitType, scope, description, breaking, files)
	body, err := editorPrompt(template)
	if err != nil {
		return err
	}
	// The first non-comment line the editor produced is the head line;
	// anything the user added below it is the body.
	head, editedBody := splitEditedMessage(body, commitType, scope, description, breaking)

	message := head
	if strings.TrimSpace(editedBody) != "" {
		message = head + "\n\n" + strings.TrimSpace(editedBody)
	}

	fmt.Println("\n---")
	fmt.Println(message)
	fmt.Println("---")
	ok, err := confirmPrompt("Commit this?", true)
	if err != nil {
		return err
	}
	if !ok {
		warnf("commit aborted")
		return nil
	}

	if err := commitWithMessage(message); err != nil {
		return err
	}
	statusf("committed: %s", head)
	return nil
}

func buildEditorTemplate(commitType, scope, description string, breaking bool, files []string) string {
	head := buildCommitMessage(commitType, scope, description, breaking, "")
	var b strings.Builder
	b.WriteString(head)
	b.WriteString("\n\n")
	b.WriteString("# Add a longer body above the comment lines if useful.\n")
	b.WriteString("# Lines starting with '#' are stripped.\n")
	b.WriteString("#\n")
	b.WriteString("# Files in this commit:\n")
	for _, f := range files {
		b.WriteString("#   " + f + "\n")
	}
	return b.String()
}

// splitEditedMessage separates the (possibly user-edited) head line from
// the rest of the body, since editorPrompt returns the whole stripped file.
func splitEditedMessage(edited, fallbackType, fallbackScope, fallbackDescription string, fallbackBreaking bool) (head, body string) {
	lines := strings.SplitN(edited, "\n", 2)
	head = strings.TrimSpace(lines[0])
	if head == "" {
		head = buildCommitMessage(fallbackType, fallbackScope, fallbackDescription, fallbackBreaking, "")
	}
	if len(lines) > 1 {
		body = lines[1]
	}
	return head, body
}
