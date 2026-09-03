package main

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

type preset struct {
	Name        string `json:"name"`
	Type        string `json:"type"`
	Scope       string `json:"scope,omitempty"`
	Description string `json:"description"`
	Body        string `json:"body,omitempty"`
	Breaking    bool   `json:"breaking,omitempty"`
}

type presetsConfig struct {
	Presets []preset `json:"presets"`
}

func parsePresets(data []byte) (*presetsConfig, error) {
	var cfg presetsConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func findPreset(cfg *presetsConfig, name string) (*preset, bool) {
	for i := range cfg.Presets {
		if cfg.Presets[i].Name == name {
			return &cfg.Presets[i], true
		}
	}
	return nil, false
}

var placeholderPattern = regexp.MustCompile(`\{([a-zA-Z0-9_]+)\}`)

func presetPlaceholders(p *preset) []string {
	seen := map[string]bool{}
	var order []string
	for _, field := range []string{p.Type, p.Scope, p.Description, p.Body} {
		for _, m := range placeholderPattern.FindAllStringSubmatch(field, -1) {
			name := m[1]
			if !seen[name] {
				seen[name] = true
				order = append(order, name)
			}
		}
	}
	return order
}

func fillPreset(p preset, values map[string]string) preset {
	fill := func(s string) string {
		for k, v := range values {
			s = strings.ReplaceAll(s, fmt.Sprintf("{%s}", k), v)
		}
		return s
	}
	p.Type = fill(p.Type)
	p.Scope = fill(p.Scope)
	p.Description = fill(p.Description)
	p.Body = fill(p.Body)
	return p
}
