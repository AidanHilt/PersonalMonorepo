package main

import (
	_ "embed"
	"flag"
	"fmt"
	"os"
)

//go:embed presets.json
var embeddedPresets []byte

//go:embed inference-rules.json
var embeddedRules []byte

func main() {
	presetName := flag.String("preset", "", "use a named preset from presets.json")
	typeFlag := flag.String("type", "", "commit type, skips the type prompt")
	scopeFlag := flag.String("scope", "", "commit scope, skips the scope prompt")
	presetsFile := flag.String("presets-file", "", "override the baked-in presets.json")
	rulesFile := flag.String("rules-file", "", "override the baked-in inference-rules.json")
	flag.Usage = showHelp
	flag.Parse()

	if err := run(*presetName, *typeFlag, *scopeFlag, *presetsFile, *rulesFile); err != nil {
		errorf("%v", err)
		os.Exit(1)
	}
}

func run(presetName, typeFlag, scopeFlag, presetsFilePath, rulesFilePath string) error {
	presetsData := embeddedPresets
	if presetsFilePath != "" {
		data, err := os.ReadFile(presetsFilePath)
		if err != nil {
			return err
		}
		presetsData = data
	}
	presetsCfg, err := parsePresets(presetsData)
	if err != nil {
		return fmt.Errorf("parsing presets: %w", err)
	}

	if presetName != "" {
		return runPresetCommit(presetsCfg, presetName)
	}

	files, err := stagedFiles()
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return fmt.Errorf("no staged changes; stage something first")
	}

	root, err := repoRoot()
	if err != nil {
		return err
	}
	cogCfg, err := loadCogConfig(root)
	if err != nil {
		return fmt.Errorf("parsing cog.toml: %w", err)
	}

	rulesData := embeddedRules
	if rulesFilePath != "" {
		data, err := os.ReadFile(rulesFilePath)
		if err != nil {
			return err
		}
		rulesData = data
	}
	rulesCfg, err := parseInferenceRules(rulesData)
	if err != nil {
		return fmt.Errorf("parsing inference rules: %w", err)
	}

	touched, unmatched := matchPackages(files, cogCfg)

	if len(touched) > 1 {
		debugf("staged changes touch %d packages, offering a split", len(touched))
		return runSplit(touched, unmatched, rulesCfg.Rules, typeFlag, scopeFlag)
	}

	scopeDefault := ""
	for name := range touched {
		scopeDefault = name
	}

	addedLines := collectAddedLines(files)
	typeDefault, ok := inferType(files, addedLines, rulesCfg.Rules)
	if ok {
		debugf("inferred type %q from rules", typeDefault)
	}

	defaults := commitDefaults{
		typeOverride:  typeFlag,
		scopeOverride: scopeFlag,
		typeDefault:   typeDefault,
		scopeDefault:  scopeDefault,
	}
	return runInteractiveCommit(files, defaults)
}

func runPresetCommit(cfg *presetsConfig, name string) error {
	p, ok := findPreset(cfg, name)
	if !ok {
		return fmt.Errorf("no preset named %q", name)
	}

	placeholders := presetPlaceholders(p)
	values := map[string]string{}
	for _, ph := range placeholders {
		val, err := requiredTextPrompt(ph)
		if err != nil {
			return err
		}
		values[ph] = val
	}

	filled := fillPreset(*p, values)
	message := buildCommitMessage(filled.Type, filled.Scope, filled.Description, filled.Breaking, filled.Body)

	fmt.Println("\n---")
	fmt.Println(message)
	fmt.Println("---")
	ok2, err := confirmPrompt("Commit this?", true)
	if err != nil {
		return err
	}
	if !ok2 {
		warnf("commit aborted")
		return nil
	}

	if err := commitWithMessage(message); err != nil {
		return err
	}
	statusf("committed via preset %q", name)
	return nil
}

func showHelp() {
	fmt.Fprintln(os.Stderr, "Usage: kommit [OPTIONS]")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "Interactive wrapper around cocogitto for building conventional commits.")
	fmt.Fprintln(os.Stderr, "With no flags, walks staged changes through type/scope/description")
	fmt.Fprintln(os.Stderr, "prompts, splitting into one commit per cog.toml package if needed.")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "OPTIONS:")
	flag.PrintDefaults()
}
