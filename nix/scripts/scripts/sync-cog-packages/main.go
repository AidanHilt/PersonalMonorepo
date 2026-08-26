// Command sync-cog-packages discovers releasable container packages
// under a nix images directory.
//
// Category A packages (values.nix has a literal `tag` field) have
// their [packages.*] entries synced into the generated section of
// cog.toml, leaving the hand-maintained fixed section untouched.
//
// Category B packages (values.nix has a literal `versionPackage`
// field instead) are never written to cog.toml — they're excluded
// from cocogitto entirely, since their version tracks a nixpkgs
// attribute rather than conventional-commit history.
//
// -list=internalVersion / -list=externalPkgVersioned print the discovered packages of
// that category as JSON, for consumption by a GH Actions build matrix.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"sync-cog-packages/internal/cogtoml"
	"sync-cog-packages/internal/discover"
)

func main() {
	root := flag.String("root", ".", "repo root")
	imagesDir := flag.String("images-dir", "nix/mono-flake/custom-images/images", "images directory, relative to root")
	cogTomlPath := flag.String("cog-toml", "cog.toml", "path to cog.toml, relative to root")
	check := flag.Bool("check", false, "report whether cog.toml changes are needed without writing; exit 1 if so (Category A only)")
	list := flag.String("list", "", `print discovered packages as JSON instead of syncing cog.toml; one of "internalVersion" or "externalPkgVersioned"`)
	flag.Parse()

	if err := run(*root, *imagesDir, *cogTomlPath, *check, *list); err != nil {
		fmt.Fprintln(os.Stderr, "sync-cog-packages: error:", err)
		os.Exit(2)
	}
}

func run(root, imagesDir, cogTomlRel string, check bool, list string) error {
	pkgs, err := discover.Discover(root, imagesDir)
	if err != nil {
		return err
	}

	if list != "" {
		return printList(pkgs, list)
	}

	// cog.toml only ever reflects Category A — Category B is
	// intentionally invisible to cocogitto.
	internalVersion := discover.FilterCategory(pkgs, discover.InternalVersion)
	return syncCogToml(root, cogTomlRel, internalVersion, check)
}

// listEntry is the JSON shape emitted by -list. Fields irrelevant to
// a given category are simply omitted (empty string) rather than
// having two separate types, to keep consumption on the Actions side
// (fromJson(...)) straightforward regardless of category.
type listEntry struct {
	Name           string `json:"name"`
	Dir            string `json:"dir"`
	ValuesNixPath  string `json:"valuesNixPath"`
	TagPrefix      string `json:"tagPrefix"`
	Tag            string `json:"tag,omitempty"`
	VersionPackage string `json:"versionPackage,omitempty"`
}

func printList(pkgs []discover.Package, list string) error {
	var cat discover.Category
	switch list {
	case "internalVersion":
		cat = discover.InternalVersion
	case "externalPkgVersioned":
		cat = discover.ExternalPkgVersioned
	default:
		return fmt.Errorf(`invalid -list value %q, must be "internalVersion" or "externalPkgVersioned"`, list)
	}

	filtered := discover.FilterCategory(pkgs, cat)
	entries := make([]listEntry, 0, len(filtered))
	for _, p := range filtered {
		entries = append(entries, listEntry{
			Name:           p.Name,
			Dir:            p.Dir,
			ValuesNixPath:  p.ValuesNixPath,
			TagPrefix:      p.TagPrefix(),
			Tag:            p.Tag,
			VersionPackage: p.VersionPackage,
		})
	}

	enc := json.NewEncoder(os.Stdout)
	return enc.Encode(entries)
}

func syncCogToml(root, cogTomlRel string, internalVersion []discover.Package, check bool) error {
	cogTomlAbs := root + string(os.PathSeparator) + cogTomlRel
	rawBytes, err := os.ReadFile(cogTomlAbs)
	if err != nil {
		return fmt.Errorf("reading %s: %w", cogTomlRel, err)
	}

	fixedPrefix, generatedSuffix, err := cogtoml.Split(string(rawBytes))
	if err != nil {
		return err
	}

	extras, err := cogtoml.ParseExistingExtras(generatedSuffix)
	if err != nil {
		return err
	}

	newPkgs := cogtoml.Build(internalVersion, extras)
	newSuffix := cogtoml.Render(newPkgs)

	if check {
		oldPkgs, err := cogtoml.ParseExistingPackagesForDiff(generatedSuffix)
		if err != nil {
			return err
		}
		diff := cogtoml.ComputeDiff(oldPkgs, newPkgs)
		if diff.Empty() {
			fmt.Println("sync-cog-packages: cog.toml is up to date")
			return nil
		}
		if len(diff.Added) > 0 {
			fmt.Println("would add:   ", diff.Added)
		}
		if len(diff.Removed) > 0 {
			fmt.Println("would remove:", diff.Removed)
		}
		if len(diff.Changed) > 0 {
			fmt.Println("would change:", diff.Changed)
		}
		os.Exit(1)
	}

	if generatedSuffix == newSuffix {
		fmt.Println("sync-cog-packages: cog.toml already up to date, no changes")
		return nil
	}

	if err := cogtoml.WriteFile(cogTomlAbs, fixedPrefix, newSuffix); err != nil {
		return fmt.Errorf("writing %s: %w", cogTomlRel, err)
	}

	fmt.Printf("sync-cog-packages: wrote %d Category A package(s) to %s\n", len(newPkgs), cogTomlRel)
	for _, p := range newPkgs {
		fmt.Printf("  - %s (tag_prefix=%s)\n", p.Name, p.TagPrefix)
	}
	return nil
}
