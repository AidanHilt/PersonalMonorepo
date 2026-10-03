// pkg-broker is the single-purpose HTTP server behind the `pkg-broker`
// compose service (see nix/agentic-ai-stack/containers/pkg-broker/README.md
// and PROJECT-SPEC.md for the full design rationale). It exposes exactly
// one narrow endpoint, reachable only from the `internal` compose network:
// given an exact nixpkgs attribute name, it validates the name, resolves
// it against this repo's pinned nixpkgs checkout (binary cache first,
// build-from-source fallback — both are just `nix-build`'s normal
// behavior), and publishes the resulting bin/* entries into the shared
// `pkg-bin` volume so the `pi` container can find them on PATH.
//
// Deliberately minimal and dependency-free (stdlib only) in the same
// spirit as the `proxy` container: this is new trust-boundary-adjacent
// surface, so it stays small and easy to read in one sitting.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Nixpkgs attribute paths are dot-separated identifiers (e.g.
// "ripgrep" or "nodePackages.typescript"). This is intentionally strict:
// no arbitrary flake refs (no "#", no ":"), no shell metacharacters, no
// arbitrary nix expressions. The attribute is also always passed as a
// single argv element to `nix-build -A`, never through a shell, so this
// regex is defense-in-depth on top of that, not the only thing standing
// between a caller and arbitrary eval.
var attrPattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_'-]*(\.[A-Za-z0-9_][A-Za-z0-9_'-]*)*$`)

const maxAttrLen = 200

type resolveRequest struct {
	Attr string `json:"attr"`
}

type resolveResponse struct {
	OK         bool     `json:"ok"`
	Attr       string   `json:"attr"`
	StorePaths []string `json:"storePaths,omitempty"`
	Binaries   []string `json:"binaries,omitempty"`
	Error      string   `json:"error,omitempty"`
}

type server struct {
	nixpkgsPath string
	binDir      string
	buildTO     time.Duration
	// storeReadRoot is the PHYSICAL filesystem root that logical nix store
	// paths (as reported by nix-build, e.g. /nix/store/...) actually live
	// under, from this process's own point of view. entrypoint.sh sets this
	// via PKG_BROKER_STORE_READ_ROOT: "/" in host-store mode (logical and
	// physical coincide -- the host's real /nix is mounted here too), or the
	// chroot store's $ROOT in the default chroot-store mode (logical paths
	// are physically at $ROOT/nix/store/..., not at this container's own
	// /nix/store). See publishBinaries.
	storeReadRoot string
}

func main() {
	storeReadRoot, ok := os.LookupEnv("PKG_BROKER_STORE_READ_ROOT")
	if !ok || storeReadRoot == "" {
		log.Printf("pkg-broker: PKG_BROKER_STORE_READ_ROOT not set, defaulting to \"/\" -- entrypoint.sh is expected to set this")
		storeReadRoot = "/"
	}

	s := &server{
		nixpkgsPath:   envOrDefault("PKG_BROKER_NIXPKGS_PATH", "/etc/pkg-broker/nixpkgs"),
		binDir:        envOrDefault("PKG_BROKER_BIN_DIR", "/srv/pkg-broker/bin"),
		buildTO:       20 * time.Minute, // generous enough for a cold build-from-source fallback
		storeReadRoot: storeReadRoot,
	}

	if err := os.MkdirAll(s.binDir, 0o755); err != nil {
		log.Fatalf("pkg-broker: cannot create bin dir %s: %v", s.binDir, err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/resolve", s.handleResolve)

	addr := envOrDefault("PKG_BROKER_LISTEN", ":8080")
	log.Printf("pkg-broker: listening on %s (nixpkgs=%s, bin-dir=%s, store-read-root=%s)", addr, s.nixpkgsPath, s.binDir, s.storeReadRoot)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func envOrDefault(name, def string) string {
	if v, ok := os.LookupEnv(name); ok && v != "" {
		return v
	}
	return def
}

func (s *server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func (s *server) handleResolve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, resolveResponse{OK: false, Error: "only POST is supported"})
		return
	}

	var req resolveRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	if err := dec.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, resolveResponse{OK: false, Error: fmt.Sprintf("invalid JSON body: %v", err)})
		return
	}

	attr := strings.TrimSpace(req.Attr)
	if err := validateAttr(attr); err != nil {
		writeJSON(w, http.StatusBadRequest, resolveResponse{OK: false, Attr: attr, Error: err.Error()})
		return
	}

	storePaths, err := s.nixBuild(r.Context(), attr)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, resolveResponse{OK: false, Attr: attr, Error: err.Error()})
		return
	}

	binaries, err := s.publishBinaries(storePaths)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, resolveResponse{OK: false, Attr: attr, StorePaths: storePaths, Error: err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, resolveResponse{
		OK:         true,
		Attr:       attr,
		StorePaths: storePaths,
		Binaries:   binaries,
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func validateAttr(attr string) error {
	if attr == "" {
		return errors.New("attr must not be empty")
	}
	if len(attr) > maxAttrLen {
		return fmt.Errorf("attr must be at most %d characters", maxAttrLen)
	}
	if !attrPattern.MatchString(attr) {
		return errors.New("attr must be a plain dot-separated nixpkgs attribute path (letters, digits, '_', '-', '\\''; no flake refs, no expressions)")
	}
	return nil
}

// nixBuild resolves attr against the pinned nixpkgs checkout baked into
// this image (s.nixpkgsPath). This is plain `nix-build -A`, not a flake
// reference and not `nix eval`/`nix run` against an arbitrary expression —
// the only input that varies per request is the already-validated
// attribute name. Binary-cache-first / build-from-source-fallback is
// simply nix-build's normal substituter behavior (see nix.conf baked
// into the image), not special-cased here.
func (s *server) nixBuild(ctx context.Context, attr string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, s.buildTO)
	defer cancel()

	cmd := exec.CommandContext(ctx, "nix-build", "--no-out-link", "-A", attr, s.nixpkgsPath)
	cmd.Env = os.Environ()
	out, err := cmd.Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return nil, fmt.Errorf("nix-build failed for attr %q: %s", attr, strings.TrimSpace(string(exitErr.Stderr)))
		}
		return nil, fmt.Errorf("nix-build failed for attr %q: %v", attr, err)
	}

	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	var paths []string
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" {
			paths = append(paths, l)
		}
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("nix-build produced no output paths for attr %q", attr)
	}
	return paths, nil
}

// publishBinaries symlinks every entry under each store path's bin/
// directory (if present) into the shared pkg-bin volume (s.binDir),
// which is mounted read-only onto an existing-on-PATH directory inside
// the `pi` container (see compose.yaml).
//
// nix-build reports LOGICAL store paths (/nix/store/...), but this
// process's own filesystem view of where those paths physically live
// depends on which store backend entrypoint.sh set up:
//   - host-store mode: logical and physical coincide (storeReadRoot "/"),
//     since the host's real /nix is mounted here too.
//   - chroot-store mode (default): logical paths are physically at
//     $ROOT/nix/store/..., not at this container's own /nix/store, so
//     reads must go through storeReadRoot while symlink targets stay
//     logical.
//
// All READS here go through the physical path (s.storeReadRoot joined
// with the logical path); the symlink TARGETS published to s.binDir
// stay the LOGICAL path, since `pi` resolves /nix/store/... via its own
// overlay/bind of the same store (see decision 4 in .AGENT-PLAN.md /
// PROJECT-SPEC.md) — this is what lets the binaries' RPATH/dynamic-linker
// dependency references resolve inside `pi`.
func (s *server) publishBinaries(storePaths []string) ([]string, error) {
	var published []string
	for _, sp := range storePaths {
		phys := filepath.Join(s.storeReadRoot, sp)
		if _, err := os.Stat(phys); err != nil {
			if os.IsNotExist(err) {
				return published, fmt.Errorf("store path %s not found at physical location %s (check PKG_BROKER_STORE_READ_ROOT)", sp, phys)
			}
			return published, fmt.Errorf("stat %s: %w", phys, err)
		}

		binDir := filepath.Join(sp, "bin")
		physBinDir := filepath.Join(phys, "bin")
		entries, err := os.ReadDir(physBinDir)
		if err != nil {
			if os.IsNotExist(err) {
				continue // not every derivation ships a bin/ dir (e.g. libraries)
			}
			return published, fmt.Errorf("reading %s: %w", physBinDir, err)
		}
		for _, e := range entries {
			name := e.Name()
			target := filepath.Join(binDir, name)
			link := filepath.Join(s.binDir, name)

			tmp := link + ".pkg-broker-tmp"
			_ = os.Remove(tmp)
			if err := os.Symlink(target, tmp); err != nil {
				return published, fmt.Errorf("symlinking %s -> %s: %w", link, target, err)
			}
			if err := os.Rename(tmp, link); err != nil {
				return published, fmt.Errorf("installing symlink %s: %w", link, err)
			}
			published = append(published, name)
		}
	}
	return published, nil
}
