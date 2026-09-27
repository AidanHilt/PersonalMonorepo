package main

import (
	"fmt"
	"strings"
)

// runSplit unstages everything and walks the user through one commit per
// touched package, followed by a final commit for files matching no
// package (if any).
func runSplit(touched map[string][]string, unmatched []string, rules []inferenceRule, overrideType, overrideScope string) error {
	var allOriginal []string
	for _, files := range touched {
		allOriginal = append(allOriginal, files...)
	}
	allOriginal = append(allOriginal, unmatched...)

	partial, err := partiallyStagedFiles()
	if err != nil {
		return err
	}
	var flagged []string
	for _, f := range allOriginal {
		if partial[f] {
			flagged = append(flagged, f)
		}
	}
	if len(flagged) > 0 {
		warnf("these files have staged AND unstaged changes; splitting will re-stage the whole file, not just the originally staged hunk:")
		for _, f := range flagged {
			fmt.Printf("    %s\n", f)
		}
		ok, err := confirmPrompt("Continue with the split anyway?", false)
		if err != nil {
			return err
		}
		if !ok {
			return fmt.Errorf("split aborted")
		}
	}

	if err := resetStaged(); err != nil {
		return err
	}

	for _, pkgName := range sortedPackageNames(touched) {
		files := touched[pkgName]
		fmt.Printf("\n== package: %s (%d file(s)) ==\n", pkgName, len(files))
		if err := addFiles(files); err != nil {
			return err
		}
		addedLines := collectAddedLines(files)
		typeDefault, _ := inferType(files, addedLines, rules)
		defaults := commitDefaults{
			typeOverride:  overrideType,
			scopeOverride: overrideScope,
			typeDefault:   typeDefault,
			scopeDefault:  pkgName,
		}
		// scope is the package name for a split commit; don't let a blank
		// --scope override erase that unless explicitly given.
		if overrideScope != "" {
			defaults.scopeOverride = overrideScope
		} else {
			defaults.scopeOverride = pkgName
		}
		if err := runInteractiveCommit(files, defaults); err != nil {
			return err
		}
	}

	if len(unmatched) > 0 {
		fmt.Printf("\n== remaining files matching no package (%d file(s)) ==\n", len(unmatched))
		if err := addFiles(unmatched); err != nil {
			return err
		}
		addedLines := collectAddedLines(unmatched)
		typeDefault, _ := inferType(unmatched, addedLines, rules)
		defaults := commitDefaults{
			typeOverride:  overrideType,
			scopeOverride: overrideScope,
			typeDefault:   typeDefault,
			scopeDefault:  "",
		}
		if err := runInteractiveCommit(unmatched, defaults); err != nil {
			return err
		}
	}

	return nil
}

func collectAddedLines(files []string) map[string][]string {
	result := map[string][]string{}
	for _, f := range files {
		lines, err := stagedAddedLines(f)
		if err != nil {
			warnf("could not read diff for %s: %v", f, err)
			continue
		}
		result[f] = lines
	}
	return result
}

func describeFiles(files []string) string {
	return strings.Join(files, ", ")
}
