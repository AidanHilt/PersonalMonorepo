package main

import (
	"fmt"
	"strings"
)

// commitTypes is loaded from presets.json's "types" array (see
// presets.go/parsePresets) and set once in main's run(). It intentionally
// has no hardcoded default here so presets.json stays the single source
// of truth; the embedded presets.json still ships the historical 11
// types so out-of-the-box behavior is unchanged.
var commitTypes []string

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
	breaking      bool
	bodyOverride  string
	knownScopes   []string
}

// runInteractiveCommit walks the user through building and creating one
// commit covering the given (already staged) files.
//
// Flow (per plan step 4): build the head line, show it, and ask "Commit
// this?" (default yes) as the only step before committing in the happy
// path. Only if the user declines does $EDITOR open, pre-filled with the
// same template as before; whatever remains after the editor closes is
// committed immediately (aborting only if the head line ends up empty).
func runInteractiveCommit(files []string, defaults commitDefaults) error {
	commitType, err := resolveCommitType(defaults)
	if err != nil {
		return err
	}

	scope := defaults.scopeOverride
	if scope != "" {
		debugf("using --scope override: %s", scope)
	} else {
		scope = defaults.scopeDefault
		if scope == "" && isInteractiveTTY() {
			chosen, err := resolveScopeTUI(defaults.knownScopes)
			if err != nil {
				return err
			}
			scope = chosen
		}
	}

	description, err := requiredTextPrompt("Short description")
	if err != nil {
		return err
	}

	breaking := defaults.breaking

	head := buildCommitMessage(commitType, scope, description, breaking, "")
	message := head
	if strings.TrimSpace(defaults.bodyOverride) != "" {
		message = head + "\n\n" + strings.TrimSpace(defaults.bodyOverride)
	}

	fmt.Println("\n---")
	fmt.Println(message)
	fmt.Println("---")
	ok, err := confirmPrompt("Commit this?", true)
	if err != nil {
		return err
	}
	if ok {
		if err := commitWithMessage(message); err != nil {
			return err
		}
		statusf("committed: %s", head)
		return nil
	}

	template := buildEditorTemplate(commitType, scope, description, breaking, files)
	edited, err := editorPrompt(template)
	if err != nil {
		return err
	}
	editedHead, editedBody := splitEditedMessage(edited)
	if strings.TrimSpace(editedHead) == "" {
		return fmt.Errorf("commit aborted: empty commit message")
	}

	finalMessage := editedHead
	if body := strings.TrimSpace(editedBody); body != "" {
		finalMessage = editedHead + "\n\n" + body
	}

	if err := commitWithMessage(finalMessage); err != nil {
		return err
	}
	statusf("committed: %s", editedHead)
	return nil
}

// runNonInteractiveCommit implements the --non-interactive path (plan
// step 3): no prompts, no TUI, no editor. Type must come from --type or
// inference; scope resolves the same priority chain as the interactive
// path but is simply left empty if unresolved; description must come
// from --description; breaking/body only come from their respective
// flags.
func runNonInteractiveCommit(files []string, defaults commitDefaults, description string) error {
	commitType := defaults.typeOverride
	if commitType == "" {
		commitType = defaults.typeDefault
	}
	if commitType == "" {
		return fmt.Errorf("--non-interactive requires a commit type via --type or successful rule inference")
	}

	scope := defaults.scopeOverride
	if scope == "" {
		scope = defaults.scopeDefault
	}

	if strings.TrimSpace(description) == "" {
		return fmt.Errorf("--non-interactive requires --description")
	}

	message := buildCommitMessage(commitType, scope, description, defaults.breaking, defaults.bodyOverride)
	head := strings.SplitN(message, "\n", 2)[0]

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
// the rest of the body, since editorPrompt returns the whole stripped
// file. Unlike the previous implementation, an empty head line is
// returned as-is (empty) rather than silently falling back to a
// reconstructed default -- callers are expected to abort on an empty
// head, per plan step 4.
func splitEditedMessage(edited string) (head, body string) {
	lines := strings.SplitN(edited, "\n", 2)
	head = strings.TrimSpace(lines[0])
	if len(lines) > 1 {
		body = lines[1]
	}
	return head, body
}
