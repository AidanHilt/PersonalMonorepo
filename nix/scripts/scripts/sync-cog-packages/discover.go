// Package discover walks the custom-images directory tree looking for
// packages that meet the project's "releasable container" standard: a
// direct subdirectory of the images root containing a values.nix file
// with a top-level `tag = "...";` field.
package discover

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Package represents one discovered releasable image.
type Package struct {
	// Name is the directory basename, used as the cog.toml package key.
	Name string
	// Dir is the path to the package directory, relative to repo root.
	Dir string
	// ValuesNixPath is the path to values.nix, relative to repo root.
	ValuesNixPath string
	// Tag is the current literal tag value found in values.nix.
	Tag string
}

// tagAssignRe finds a top-level `tag = <expr>;` assignment. It is
// deliberately simple (line-based, not a real Nix parser) because the
// standard requires values.nix to be a flat attrset with a literal
// string tag field.
var tagAssignRe = regexp.MustCompile(`(?m)^\s*tag\s*=\s*(.+?)\s*;\s*$`)

// tagLiteralRe matches a bare double-quoted string literal with no
// interpolation. Nix string interpolation uses ${...}, which we
// explicitly reject.
var tagLiteralRe = regexp.MustCompile(`^"([^"$]*)"$`)

// Error returned when a values.nix has a tag field that isn't a plain
// string literal. This is treated as a hard failure rather than a
// silent skip, per the project standard: tag must always be a literal
// so sync-cog-packages can safely rewrite it during bump hooks.
type NonLiteralTagError struct {
	ValuesNixPath string
	RawExpr       string
}

func (e *NonLiteralTagError) Error() string {
	return fmt.Sprintf(
		"%s: tag field is not a plain string literal (found: %s) — "+
			"the project standard requires a literal string so bump hooks can rewrite it safely",
		e.ValuesNixPath, e.RawExpr,
	)
}

// Discover walks imagesDir (relative to root) one level deep and
// returns every eligible package, sorted by name for deterministic
// output. It returns a NonLiteralTagError (wrapped) on the first
// package whose tag field isn't a literal string.
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

		match := tagAssignRe.FindStringSubmatch(string(content))
		if match == nil {
			// values.nix exists but has no top-level tag field -> skip.
			continue
		}

		rawExpr := strings.TrimSpace(match[1])
		literal := tagLiteralRe.FindStringSubmatch(rawExpr)
		if literal == nil {
			return nil, &NonLiteralTagError{ValuesNixPath: valuesRel, RawExpr: rawExpr}
		}

		pkgs = append(pkgs, Package{
			Name:          name,
			Dir:           dirRel,
			ValuesNixPath: valuesRel,
			Tag:           literal[1],
		})
	}

	sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].Name < pkgs[j].Name })
	return pkgs, nil
}
