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

// cliOptions bundles the parsed command-line flags. It's threaded through
// run()/runPresetCommit instead of growing a long positional-argument
// list as new flags (--non-interactive, --description, --body, --breaking,
// --preset-value) were added.
type cliOptions struct {
	presetName     string
	typeFlag       string
	scopeFlag      string
	presetsFile    string
	rulesFile      string
	addFiles       stringSliceFlag
	nonInteractive bool
	description    string
	body           string
	breaking       bool
	presetValues   stringSliceFlag
	noPush         bool
}

func main() {
	var opts cliOptions
	flag.StringVar(&opts.presetName, "preset", "", "use a named preset from presets.json")
	flag.StringVar(&opts.typeFlag, "type", "", "commit type, skips the type prompt/TUI")
	flag.StringVar(&opts.scopeFlag, "scope", "", "commit scope, skips the scope prompt/TUI")
	flag.StringVar(&opts.presetsFile, "presets-file", "", "override the baked-in presets.json")
	flag.StringVar(&opts.rulesFile, "rules-file", "", "override the baked-in inference-rules.json")
	flag.Var(&opts.addFiles, "add-file", "stage this path instead of everything (repeatable)")
	flag.BoolVar(&opts.nonInteractive, "non-interactive", false, "never prompt or open a TUI/editor; requires --type (or inference) and --description, errors otherwise")
	flag.StringVar(&opts.description, "description", "", "commit description; required in --non-interactive mode when not otherwise resolvable")
	flag.StringVar(&opts.body, "body", "", "commit body text (optional; editor is never opened in --non-interactive mode)")
	flag.BoolVar(&opts.breaking, "breaking", false, "mark the commit as a breaking change")
	flag.Var(&opts.presetValues, "preset-value", "supply a preset placeholder as name=value (repeatable); required for all placeholders in --non-interactive mode")
	flag.BoolVar(&opts.noPush, "no-push", false, "skip pushing after commit")
	flag.Usage = showHelp
	flag.Parse()

	if envNoPush() {
		opts.noPush = true
	}

	if err := run(opts); err != nil {
		errorf("%v", err)
		os.Exit(1)
	}
}

// envNoPush treats KOMMIT_NO_PUSH as opting out of the default push
// unless it's unset, empty, "0", or "false" (case-insensitive).
func envNoPush() bool {
	v := strings.TrimSpace(os.Getenv("KOMMIT_NO_PUSH"))
	if v == "" {
		return false
	}
	switch strings.ToLower(v) {
	case "0", "false":
		return false
	default:
		return true
	}
}

func parsePresetValues(raw []string) (map[string]string, error) {
	values := map[string]string{}
	for _, kv := range raw {
		name, val, ok := strings.Cut(kv, "=")
		if !ok || name == "" {
			return nil, fmt.Errorf("invalid --preset-value %q, expected name=value", kv)
		}
		values[name] = val
	}
	return values, nil
}

// run wraps runCommit with the default post-commit push (plan step 4):
// on a successful commit (nil error from runCommit), it attempts to push
// unless opted out. A failed or aborted commit never triggers a push.
func run(opts cliOptions) error {
	if err := runCommit(opts); err != nil {
		return err
	}
	return maybePush(opts)
}

func runCommit(opts cliOptions) error {
	presetsData := embeddedPresets
	if opts.presetsFile != "" {
		data, err := os.ReadFile(opts.presetsFile)
		if err != nil {
			return err
		}
		presetsData = data
	}
	presetsCfg, err := parsePresets(presetsData)
	if err != nil {
		return fmt.Errorf("parsing presets: %w", err)
	}
	if len(presetsCfg.Types) > 0 {
		commitTypes = presetsCfg.Types
	}

	presetValues, err := parsePresetValues(opts.presetValues)
	if err != nil {
		return err
	}

	if opts.presetName != "" {
		return runPresetCommit(presetsCfg, opts.presetName, presetRunOptions{
			addFileFlags:   opts.addFiles,
			nonInteractive: opts.nonInteractive,
			breaking:       opts.breaking,
			body:           opts.body,
			presetValues:   presetValues,
			typeFlag:       opts.typeFlag,
			scopeFlag:      opts.scopeFlag,
			description:    opts.description,
		})
	}

	if err := stagePaths(opts.addFiles); err != nil {
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
	if opts.rulesFile != "" {
		data, err := os.ReadFile(opts.rulesFile)
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
	knownScopes := knownScopeValues(cogCfg, rulesCfg.Rules)

	if len(touched) > 1 {
		if opts.nonInteractive {
			return fmt.Errorf("--non-interactive does not support splitting across multiple cog.toml packages; stage a single package's files at a time")
		}
		debugf("staged changes touch %d packages, offering a split", len(touched))
		return runSplit(touched, unmatched, rulesCfg.Rules, knownScopes, opts.typeFlag, opts.scopeFlag)
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

	if scopeDefault == "" {
		if s, ok := inferScope(files, addedLines, rulesCfg.Rules); ok {
			debugf("inferred scope %q from rules", s)
			scopeDefault = s
		}
	}

	defaults := commitDefaults{
		typeOverride:  opts.typeFlag,
		scopeOverride: opts.scopeFlag,
		typeDefault:   typeDefault,
		scopeDefault:  scopeDefault,
		breaking:      opts.breaking,
		bodyOverride:  opts.body,
		knownScopes:   knownScopes,
	}

	if opts.nonInteractive {
		return runNonInteractiveCommit(files, defaults, opts.description)
	}
	return runInteractiveCommit(files, defaults)
}

type presetRunOptions struct {
	addFileFlags   []string
	nonInteractive bool
	breaking       bool
	body           string
	presetValues   map[string]string
	typeFlag       string
	scopeFlag      string
	description    string
}

func runPresetCommit(cfg *presetsConfig, name string, opts presetRunOptions) error {
	p, ok := findPreset(cfg, name)
	if !ok {
		return fmt.Errorf("no preset named %q", name)
	}

	placeholders := presetPlaceholders(p)
	values := map[string]string{}
	for _, ph := range placeholders {
		if v, ok := opts.presetValues[ph]; ok {
			values[ph] = v
			continue
		}
		if opts.nonInteractive {
			return fmt.Errorf("preset %q requires placeholder %q; supply it with --preset-value %s=<value> in --non-interactive mode", name, ph, ph)
		}
		val, err := requiredTextPrompt(ph)
		if err != nil {
			return err
		}
		values[ph] = val
	}

	filled := fillPreset(*p, values)

	if opts.typeFlag != "" {
		filled.Type = opts.typeFlag
	}
	if opts.scopeFlag != "" {
		filled.Scope = opts.scopeFlag
	}
	if opts.description != "" {
		filled.Description = opts.description
	}
	if opts.body != "" {
		filled.Body = opts.body
	}
	breaking := filled.Breaking || opts.breaking

	if filled.Type == "" {
		if opts.nonInteractive {
			return fmt.Errorf("preset %q has no type; supply one via --type in --non-interactive mode", name)
		}
		debugf("preset %q has no type set, prompting", name)
		chosen, err := resolveCommitType(commitDefaults{})
		if err != nil {
			return err
		}
		filled.Type = chosen
	}
	if filled.Scope == "" && !opts.nonInteractive {
		debugf("preset %q has no scope set, prompting", name)
		chosen, err := textPrompt("Scope (optional)", "")
		if err != nil {
			return err
		}
		filled.Scope = chosen
	}
	if filled.Description == "" {
		if opts.nonInteractive {
			return fmt.Errorf("preset %q has no description; supply one via --description in --non-interactive mode", name)
		}
		debugf("preset %q has no description set, prompting", name)
		chosen, err := requiredTextPrompt("Short description")
		if err != nil {
			return err
		}
		filled.Description = chosen
	}

	switch {
	case len(opts.addFileFlags) > 0:
		if err := addFiles(opts.addFileFlags); err != nil {
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

	message := buildCommitMessage(filled.Type, filled.Scope, filled.Description, breaking, filled.Body)

	if opts.nonInteractive {
		head := strings.SplitN(message, "\n", 2)[0]
		if err := commitWithMessage(message); err != nil {
			return err
		}
		statusf("committed via preset %q: %s", name, head)
		return nil
	}

	fmt.Println("\n---")
	fmt.Println(message)
	fmt.Println("---")
	ok2, err := confirmPrompt("Commit this?", true)
	if err != nil {
		return err
	}
	if ok2 {
		if err := commitWithMessage(message); err != nil {
			return err
		}
		statusf("committed via preset %q", name)
		return nil
	}

	files, _ := stagedFiles()
	template := buildEditorTemplate(filled.Type, filled.Scope, filled.Description, breaking, files)
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
	statusf("committed via preset %q: %s", name, editedHead)
	return nil
}

// maybePush implements the default post-commit push (plan step 3): a
// no-op when opted out via --no-push/KOMMIT_NO_PUSH, a skip-with-warning
// when the current branch has no upstream, and otherwise a best-effort
// `git push` whose failure is only ever warned about (exit stays 0).
func maybePush(opts cliOptions) error {
	if opts.noPush {
		return nil
	}
	if !hasUpstream() {
		warnf("no upstream configured for current branch; skipping push")
		return nil
	}
	if err := pushCurrent(); err != nil {
		warnf("%v", err)
		return nil
	}
	statusf("pushed")
	return nil
}

func showHelp() {
	fmt.Fprintln(os.Stderr, "Usage: kommit [OPTIONS]")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "Interactive wrapper around cocogitto for building conventional commits.")
	fmt.Fprintln(os.Stderr, "By default stages everything in the working tree (including dotfiles)")
	fmt.Fprintln(os.Stderr, "before walking you through type/scope/description prompts (TUI pickers")
	fmt.Fprintln(os.Stderr, "when stdin/stdout are a terminal), splitting into one commit per")
	fmt.Fprintln(os.Stderr, "cog.toml package if needed. Use --add-file to stage specific paths")
	fmt.Fprintln(os.Stderr, "instead.")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "Use --non-interactive for fully scripted commits: type must come from")
	fmt.Fprintln(os.Stderr, "--type or rule inference, description from --description, breaking from")
	fmt.Fprintln(os.Stderr, "--breaking, and body (optional) from --body; no editor is ever opened.")
	fmt.Fprintln(os.Stderr, "With --preset in --non-interactive mode, every preset placeholder must")
	fmt.Fprintln(os.Stderr, "be supplied via a repeatable --preset-value name=value flag.")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "After a successful commit (or set of split commits), kommit pushes the")
	fmt.Fprintln(os.Stderr, "current branch by default, skipping with a warning if no upstream is")
	fmt.Fprintln(os.Stderr, "configured and warning (without failing) if the push itself fails. Use")
	fmt.Fprintln(os.Stderr, "--no-push or set KOMMIT_NO_PUSH (to anything other than empty/0/false)")
	fmt.Fprintln(os.Stderr, "to skip pushing.")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "OPTIONS:")
	flag.PrintDefaults()
}
