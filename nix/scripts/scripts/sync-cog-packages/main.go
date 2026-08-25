// Command sync-cog-packages discovers releasable container packages
// under a nix images directory and syncs their [packages.*] entries
// into the generated section of cog.toml, leaving the hand-maintained
// fixed section untouched.
package main

import (
	"flag"
	"fmt"
	"os"

	"sync-cog-packages/internal/cogtoml"
	"sync-cog-packages/internal/discover"
)

func main() {
	root := flag.String("root", ".", "repo root")
	imagesDir := flag.String("images-dir", "nix/custom-images/images", "images directory, relative to root")
	cogTomlPath := flag.String("cog-toml", "cog.toml", "path to cog.toml, relative to root")
	check := flag.Bool("check", false, "report whether changes are needed without writing; exit 1 if so")
	flag.Parse()

	if err := run(*root, *imagesDir, *cogTomlPath, *check); err != nil {
		fmt.Fprintln(os.Stderr, "sync-cog-packages: error:", err)
		os.Exit(2)
	}
}

func run(root, imagesDir, cogTomlRel string, check bool) error {
	pkgs, err := discover.Discover(root, imagesDir)
	if err != nil {
		return err
	}

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

	newPkgs := cogtoml.Build(pkgs, extras)
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

	fmt.Printf("sync-cog-packages: wrote %d package(s) to %s\n", len(newPkgs), cogTomlRel)
	for _, p := range newPkgs {
		fmt.Printf("  - %s (tag_prefix=%s)\n", p.Name, p.TagPrefix)
	}
	return nil
}
