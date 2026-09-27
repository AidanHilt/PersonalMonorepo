package main

import (
	_ "embed"
	"flag"
	"fmt"
	"os"
	"strings"
)

//go:embed presets.json
var embeddedPresets []byte

//go:embed inference-rules.json
var embeddedRules []byte

type stringSliceFlag []string

func (s *stringSliceFlag) String() string {
	return strings.Join(*s, ",")
}

func (s *stringSliceFlag) Set(v string) error {
	*s = append(*s, v)
	return nil
}

func main() {
	presetName := flag.String("preset", "", "use a named preset from presets.json")
	typeFlag := flag.String("type", "", "commit type, skips the type prompt")
	scopeFlag := flag.String("scope", "", "commit scope, skips the scope prompt")
	presetsFile := flag.String("presets-file", "", "override the baked-in presets.json")
	rulesFile := flag.String("rules-file", "", "override the baked-in inference-rules.json")
	var addFileFlags stringSliceFlag
	flag.Var(&addFileFlags, "add-file", "stage this path instead of everything (repeatable)")
	flag.Usage = showHelp
	flag.Parse()

	if err := run(*presetName, *typeFlag, *scopeFlag, *presetsFile, *rulesFile, addFileFlags); err != nil {
		errorf("%v", err)
		os.Exit(1)
	}
}

func run(presetName, typeFlag, scopeFlag, presetsFilePath, rulesFilePath string, addFileFlags []string) error {
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
		return runPresetCommit(presetsCfg, presetName, addFileFlags)
	}

	if err := stagePaths(addFileFlags); err != nil {
		return err
	}

	files, err := stagedFiles()
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return fmt.Errorf("nothing to commit; no changes found")
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

func runPresetCommit(cfg *presetsConfig, name string, addFileFlags []string) error {
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

	if filled.Type == "" {
		debugf("preset %q has no type set, prompting", name)
		chosen, err := selectPrompt("Commit type:", commitTypes, -1)
		if err != nil {
			return err
		}
		filled.Type = chosen
	}
	if filled.Scope == "" {
		debugf("preset %q has no scope set, prompting", name)
		chosen, err := textPrompt("Scope (optional)", "")
		if err != nil {
			return err
		}
		filled.Scope = chosen
	}
	if filled.Description == "" {
		debugf("preset %q has no description set, prompting", name)
		chosen, err := requiredTextPrompt("Short description")
		if err != nil {
			return err
		}
		filled.Description = chosen
	}

	switch {
	case len(addFileFlags) > 0:
		if err := addFiles(addFileFlags); err != nil {
			return err
		}
	case len(filled.Paths) > 0:
		if staged := addFilesLenient(filled.Paths); len(staged) == 0 {
			warnf("none of this preset's default paths matched anything: %s", strings.Join(filled.Paths, ", "))
		}
	default:
		if err := addAll(); err != nil {
			return err
		}
	}

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
	fmt.Fprintln(os.Stderr, "By default stages everything in the working tree (including dotfiles)")
	fmt.Fprintln(os.Stderr, "before walking you through type/scope/description prompts, splitting")
	fmt.Fprintln(os.Stderr, "into one commit per cog.toml package if needed. Use --add-file to stage")
	fmt.Fprintln(os.Stderr, "specific paths instead.")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "OPTIONS:")
	flag.PrintDefaults()
}
