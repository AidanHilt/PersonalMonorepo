package main

import (
	"encoding/json"
	"regexp"
)

type inferenceRule struct {
	Type    string `json:"type"`
	Path    string `json:"path,omitempty"`
	Content string `json:"content,omitempty"`
}

type inferenceRulesConfig struct {
	Rules []inferenceRule `json:"rules"`
}

func parseInferenceRules(data []byte) (*inferenceRulesConfig, error) {
	var cfg inferenceRulesConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// candidateTypesForFile returns the set of types any rule assigns to a
// single file, given that file's staged added lines (for content matching).
func candidateTypesForFile(file string, addedLines []string, rules []inferenceRule) map[string]bool {
	candidates := map[string]bool{}
	for _, rule := range rules {
		if rule.Path == "" && rule.Content == "" {
			continue
		}
		if rule.Path != "" && !matchGlob(rule.Path, file) {
			continue
		}
		if rule.Content != "" {
			re, err := regexp.Compile(rule.Content)
			if err != nil {
				warnf("invalid content regex in rule for type %q: %v", rule.Type, err)
				continue
			}
			matched := false
			for _, line := range addedLines {
				if re.MatchString(line) {
					matched = true
					break
				}
			}
			if !matched {
				continue
			}
		}
		candidates[rule.Type] = true
	}
	return candidates
}

// inferType applies the unanimous-or-abstain policy: every staged file must
// resolve to the exact same single candidate type for a suggestion to be
// offered. Any disagreement, or any file matching nothing, means abstain.
func inferType(files []string, addedLinesByFile map[string][]string, rules []inferenceRule) (string, bool) {
	if len(files) == 0 {
		return "", false
	}
	var intersection map[string]bool
	for _, file := range files {
		candidates := candidateTypesForFile(file, addedLinesByFile[file], rules)
		if len(candidates) == 0 {
			return "", false
		}
		if intersection == nil {
			intersection = candidates
			continue
		}
		next := map[string]bool{}
		for t := range intersection {
			if candidates[t] {
				next[t] = true
			}
		}
		intersection = next
		if len(intersection) == 0 {
			return "", false
		}
	}
	if len(intersection) != 1 {
		return "", false
	}
	for t := range intersection {
		return t, true
	}
	return "", false
}
