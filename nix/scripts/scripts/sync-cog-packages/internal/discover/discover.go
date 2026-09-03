// Package discover walks the custom-images directory tree looking for
// packages that meet the project's "releasable container" standard. A
// direct subdirectory of the images root containing a values.nix is a
// package if that file has exactly one of two literal-string fields:
//
//   - tag ("Category A"): version comes from cocogitto, via
//     conventional-commit-driven semver bumps. This tool syncs these
//     into cog.toml's generated [packages.*] section.
//
//   - versionPackage ("Category B"): version instead tracks a
//     nixpkgs attribute path (the resolution mechanism for that is
//     implemented elsewhere). These packages are rebuilt whenever
//     changed and are never registered with cocogitto.
//
// A values.nix with neither field is treated as "not a package yet"
// (e.g. still being scaffolded) and silently skipped. A values.nix
// with both fields, or with either field present but not a plain
// string literal, is a hard error — the standard requires both
// fields to be literals so tooling can read and (for tag) rewrite
// them safely.
package discover

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Category identifies which release model a package follows.
type Category int

const (
	// InternalVersioned packages are versioned by cocogitto via the `tag` field.
	InternalVersioned Category = iota
	// ExternalPkgVersioned packages track a nixpkgs attribute via `versionPackage`
	// and are rebuilt whenever their content changes, independent of
	// cocogitto.
	ExternalPkgVersioned
)

func (c Category) String() string {
	switch c {
	case InternalVersioned:
		return "internalVersioned"
	case ExternalPkgVersioned:
		return "externalPkgVersioned"
	default:
		return "unknown"
	}
}

// Package represents one discovered releasable image.
type Package struct {
	// Name is the directory basename, used as the cog.toml package key
	// (Category A) or matrix identifier (both categories).
	Name string
	// Dir is the path to the package directory, relative to repo root.
	Dir string
	// ValuesNixPath is the path to values.nix, relative to repo root.
	ValuesNixPath string
	// Category indicates which of Tag / VersionPackage is populated.
	Category Category
	// Tag is the current literal tag value (Category A only).
	Tag string
	// VersionPackage is the nixpkgs attribute path this package tracks
	// (Category B only).
	VersionPackage string
}

// TagPrefix returns the cocogitto tag prefix this package would use
// (Category A only, but harmless to compute for either).
func (p Package) TagPrefix() string {
	return p.Name + "-"
}

// bareStringLiteralRe matches a bare double-quoted string literal with
// no interpolation. Nix string interpolation uses ${...}, which is
// explicitly rejected: both `tag` and `versionPackage` must be plain
// literals so this tool (and cocogitto's bump hooks) can read and
// rewrite them with simple text tools rather than a real Nix evaluator.
var bareStringLiteralRe = regexp.MustCompile(`^"([^"$]*)"$`)

// FieldConflictError is returned when a values.nix sets both `tag`
// and `versionPackage` — a package must be exactly one category.
type FieldConflictError struct {
	ValuesNixPath string
}

func (e *FieldConflictError) Error() string {
	return fmt.Sprintf(
		"%s: has both `tag` and `versionPackage` set — a package must be "+
			"exactly one of Category A (tag) or Category B (versionPackage), not both",
		e.ValuesNixPath,
	)
}

// NonLiteralFieldError is returned when `tag` or `versionPackage` is
// present but isn't a plain string literal.
type NonLiteralFieldError struct {
	ValuesNixPath string
	Field         string
	RawExpr       string
}

func (e *NonLiteralFieldError) Error() string {
	return fmt.Sprintf(
		"%s: `%s` field is not a plain string literal (found: %s) — "+
			"the project standard requires a literal string so tooling can read and rewrite it safely",
		e.ValuesNixPath, e.Field, e.RawExpr,
	)
}

// fieldAssignRe builds a regex matching a top-level `<field> = <expr>;`
// line for the given field name. Line-based and deliberately simple —
// not a real Nix parser — because the standard requires values.nix to
// be a flat attrset with literal string fields.
func fieldAssignRe(field string) *regexp.Regexp {
	return regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(field) + `\s*=\s*(.+?)\s*;\s*$`)
}

var tagRe = fieldAssignRe("tag")
var versionPackageRe = fieldAssignRe("versionPackage")

// extractLiteralField looks for `<field> = "...";` in content. Returns
// found=false if the field isn't present at all. Returns an error if
// the field is present but its value isn't a bare string literal.
func extractLiteralField(re *regexp.Regexp, fieldName, valuesNixPath, content string) (value string, found bool, err error) {
	m := re.FindStringSubmatch(content)
	if m == nil {
		return "", false, nil
	}
	raw := strings.TrimSpace(m[1])
	lit := bareStringLiteralRe.FindStringSubmatch(raw)
	if lit == nil {
		return "", true, &NonLiteralFieldError{ValuesNixPath: valuesNixPath, Field: fieldName, RawExpr: raw}
	}
	return lit[1], true, nil
}

// Discover walks imagesDir (relative to root) one level deep and
// returns every eligible package (both categories), sorted by name
// for deterministic output. It returns an error (FieldConflictError
// or NonLiteralFieldError) on the first package that violates the
// standard.
func Discover(root, imagesDir string) ([]Package, error) {
	absImagesDir := filepath.Join(root, imagesDir)

	entries, err := os.ReadDir(absImagesDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("images directory %s does not exist", absImagesDir)
		}
		return nil, fmt.Errorf("reading images directory %s: %w", absImagesDir, err)
	}

	var pkgs []Package
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		dirRel := filepath.Join(imagesDir, name)
		valuesRel := filepath.Join(dirRel, "values.nix")
		valuesAbs := filepath.Join(root, valuesRel)

		content, err := os.ReadFile(valuesAbs)
		if err != nil {
			if os.IsNotExist(err) {
				// No values.nix -> not a package under the standard, skip.
				continue
			}
			return nil, fmt.Errorf("reading %s: %w", valuesRel, err)
		}
		contentStr := string(content)

		tagVal, tagFound, err := extractLiteralField(tagRe, "tag", valuesRel, contentStr)
		if err != nil {
			return nil, err
		}
		vpVal, vpFound, err := extractLiteralField(versionPackageRe, "versionPackage", valuesRel, contentStr)
		if err != nil {
			return nil, err
		}

		switch {
		case tagFound && vpFound:
			return nil, &FieldConflictError{ValuesNixPath: valuesRel}
		case !tagFound && !vpFound:
			// Neither field present -> not a package yet, skip.
			continue
		case tagFound:
			pkgs = append(pkgs, Package{
				Name:          name,
				Dir:           dirRel,
				ValuesNixPath: valuesRel,
				Category:      InternalVersioned,
				Tag:           tagVal,
			})
		default: // vpFound
			pkgs = append(pkgs, Package{
				Name:           name,
				Dir:            dirRel,
				ValuesNixPath:  valuesRel,
				Category:       ExternalPkgVersioned,
				VersionPackage: vpVal,
			})
		}
	}

	sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].Name < pkgs[j].Name })
	return pkgs, nil
}

// FilterCategory returns the subset of pkgs matching the given category.
func FilterCategory(pkgs []Package, cat Category) []Package {
	var out []Package
	for _, p := range pkgs {
		if p.Category == cat {
			out = append(out, p)
		}
	}
	return out
}
