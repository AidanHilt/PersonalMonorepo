package main

import (
	"os"
	"path"
	"sort"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

type cogPackage struct {
	Path string `toml:"path"`
}

type cogConfig struct {
	Packages map[string]cogPackage `toml:"packages"`
}

func loadCogConfig(root string) (*cogConfig, error) {
	data, err := os.ReadFile(path.Join(root, "cog.toml"))
	if os.IsNotExist(err) {
		debugf("no cog.toml found at repo root, proceeding without packages")
		return &cogConfig{Packages: map[string]cogPackage{}}, nil
	}
	if err != nil {
		return nil, err
	}
	var cfg cogConfig
	if err := toml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// fileMatchesPackage checks whether a repo-relative file path belongs to a
// package's path. Plain directory paths are treated as prefixes; anything
// containing glob characters is matched with matchGlob.
func fileMatchesPackage(file string, pkgPath string) bool {
	pkgPath = strings.TrimSuffix(pkgPath, "/")
	if strings.ContainsAny(pkgPath, "*?[") {
		return matchGlob(pkgPath, file)
	}
	return file == pkgPath || strings.HasPrefix(file, pkgPath+"/")
}

// matchPackages partitions staged files into per-package buckets, plus a
// bucket of files matching no package. Files matching more than one package
// are assigned to the first match in sorted package-name order, and flagged
// via a debug warning since that's a config ambiguity worth knowing about.
func matchPackages(files []string, cfg *cogConfig) (touched map[string][]string, unmatched []string) {
	touched = map[string][]string{}

	names := make([]string, 0, len(cfg.Packages))
	for name := range cfg.Packages {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, file := range files {
		var matches []string
		for _, name := range names {
			if fileMatchesPackage(file, cfg.Packages[name].Path) {
				matches = append(matches, name)
			}
		}
		switch len(matches) {
		case 0:
			unmatched = append(unmatched, file)
		case 1:
			touched[matches[0]] = append(touched[matches[0]], file)
		default:
			warnf("%s matches multiple packages (%s), assigning to %s", file, strings.Join(matches, ", "), matches[0])
			touched[matches[0]] = append(touched[matches[0]], file)
		}
	}
	return touched, unmatched
}

func sortedPackageNames(touched map[string][]string) []string {
	names := make([]string, 0, len(touched))
	for name := range touched {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
