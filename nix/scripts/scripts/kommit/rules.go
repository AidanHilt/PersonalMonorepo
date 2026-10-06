package main

import (
	"encoding/json"
	"regexp"
)

// inferenceRule is schema-additive over the original type-only rules: a
// rule with no "field" (or field == "type") behaves exactly as before and
// is expected to set "type". A rule with field == "scope" is expected to
// set "scope" instead. Existing inference-rules.json files with no "field"
// key keep working unchanged.
type inferenceRule struct {
	Field   string `json:"field,omitempty"`
	Type    string `json:"type,omitempty"`
	Scope   string `json:"scope,omitempty"`
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

// field returns the rule's target field, defaulting to "type" for
// untouched/legacy rule entries.
func (r inferenceRule) field() string {
	if r.Field == "" {
		return "type"
	}
	return r.Field
}

// value returns the value this rule contributes for its target field.
func (r inferenceRule) value() string {
	if r.field() == "scope" {
		return r.Scope
	}
	return r.Type
}

// candidateValuesForFile returns the set of values any rule targeting
// field assigns to a single file, given that file's staged added lines
// (for content matching).
func candidateValuesForFile(file string, addedLines []string, rules []inferenceRule, field string) map[string]bool {
	candidates := map[string]bool{}
	for _, rule := range rules {
		if rule.field() != field {
			continue
		}
		if rule.Path == "" && rule.Content == "" {
			continue
		}
		if rule.Path != "" && !matchGlob(rule.Path, file) {
			continue
		}
		if rule.Content != "" {
			re, err := regexp.Compile(rule.Content)
			if err != nil {
				warnf("invalid content regex in %s rule %q: %v", field, rule.value(), err)
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
		val := rule.value()
		if val == "" {
			continue
		}
		candidates[val] = true
	}
	return candidates
}

// inferField applies the unanimous-or-abstain policy for the given field:
// every staged file must resolve to the exact same single candidate value
// for a suggestion to be offered. Any disagreement, or any file matching
// nothing, means abstain.
func inferField(files []string, addedLinesByFile map[string][]string, rules []inferenceRule, field string) (string, bool) {
	if len(files) == 0 {
		return "", false
	}
	var intersection map[string]bool
	for _, file := range files {
		candidates := candidateValuesForFile(file, addedLinesByFile[file], rules, field)
		if len(candidates) == 0 {
			return "", false
		}
		if intersection == nil {
			intersection = candidates
			continue
		}
		next := map[string]bool{}
		for v := range intersection {
			if candidates[v] {
				next[v] = true
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
	for v := range intersection {
		return v, true
	}
	return "", false
}

// inferType is the field == "type" convenience wrapper, kept for callers
// that only care about commit type inference.
func inferType(files []string, addedLinesByFile map[string][]string, rules []inferenceRule) (string, bool) {
	return inferField(files, addedLinesByFile, rules, "type")
}

// inferScope is the field == "scope" convenience wrapper.
func inferScope(files []string, addedLinesByFile map[string][]string, rules []inferenceRule) (string, bool) {
	return inferField(files, addedLinesByFile, rules, "scope")
}
