// pkg-broker is the single-purpose HTTP server behind the `pkg-broker`
// compose service (see nix/agentic-ai-stack/containers/pkg-broker/README.md
// and PROJECT-SPEC.md for the full design rationale). It exposes two narrow
// endpoints, both reachable only from the `internal` compose network:
//
//   - POST /resolve: given an exact nixpkgs attribute name, validates the
//     name, resolves it against this repo's pinned nixpkgs checkout (binary
//     cache first, build-from-source fallback — both are just `nix-build`'s
//     normal behavior), and publishes the resulting bin/* entries into the
//     shared `pkg-bin` volume so the `pi` container can find them on PATH.
//   - POST /lookup-binary: given a plain binary name (e.g. "protoc"),
//     validates it, then shells out to a lazily-invoked, prebuilt nix-index
//     database (via `nix run <ref>#nix-index-with-db -- ...`, see
//     nixIndexRef/PKG_BROKER_NIX_INDEX_REF) to find candidate nixpkgs
//     attributes that provide it. Returns candidates only -- it never
//     builds or publishes anything; callers make a separate /resolve call
//     with whichever candidate they want. See README.md/FOLLOWUP.md.
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
	"sort"
	"strings"
	"sync"
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

// Plain executable names, e.g. "protoc" or "rg": no '/' (not a path), no
// leading '-' (can't be mistaken for a flag), no whitespace or shell
// metacharacters. Same defense-in-depth posture as attrPattern above --
// this is also always passed as a single argv element, never through a
// shell. Deliberately does NOT allow '/' or ':' the way nixpkgs attrs
// (attrPattern) allow '.': a binary name is a single path component.
var binaryPattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.+-]*$`)

const maxBinaryLen = 100

type lookupRequest struct {
	Binary string `json:"binary"`
}

type lookupResponse struct {
	OK         bool     `json:"ok"`
	Binary     string   `json:"binary"`
	Candidates []string `json:"candidates,omitempty"`
	Error      string   `json:"error,omitempty"`
}

type server struct {
	nixpkgsPath string
	binDir      string
	buildTO     time.Duration
	// nixIndexRef is a flake ref (e.g. "github:Mic92/nix-index-database/<rev>")
	// to a prebuilt nix-index database, read from PKG_BROKER_NIX_INDEX_REF
	// (set by image.nix from flake.nix's nixIndexRef, see that file's
	// comments). Used only by /lookup-binary, invoked lazily at request time
	// via `nix run`. Empty means /lookup-binary is unavailable.
	nixIndexRef string
	// lookupTO is generous because the FIRST /lookup-binary call against a
	// given nixIndexRef downloads the whole nix-index database before it can
	// answer anything; later calls are fast (nix run's own eval/store cache).
	lookupTO time.Duration
	// dbMu serializes nix-locate invocations so concurrent first-time
	// /lookup-binary requests don't race to download the same database
	// independently. This also serializes later, already-cached lookups --
	// a deliberate simplicity-over-throughput tradeoff for a narrow,
	// infrequently-used endpoint.
	dbMu sync.Mutex
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

	nixIndexRef := os.Getenv("PKG_BROKER_NIX_INDEX_REF")
	if nixIndexRef == "" {
		log.Printf("pkg-broker: PKG_BROKER_NIX_INDEX_REF not set -- /lookup-binary will reject all requests")
	}

	s := &server{
		nixpkgsPath:   envOrDefault("PKG_BROKER_NIXPKGS_PATH", "/etc/pkg-broker/nixpkgs"),
		binDir:        envOrDefault("PKG_BROKER_BIN_DIR", "/srv/pkg-broker/bin"),
		buildTO:       20 * time.Minute, // generous enough for a cold build-from-source fallback
		nixIndexRef:   nixIndexRef,
		lookupTO:      10 * time.Minute, // generous enough for a cold nix-index-database download
		storeReadRoot: storeReadRoot,
	}

	if err := os.MkdirAll(s.binDir, 0o755); err != nil {
		log.Fatalf("pkg-broker: cannot create bin dir %s: %v", s.binDir, err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/resolve", s.handleResolve)
	mux.HandleFunc("/lookup-binary", s.handleLookupBinary)

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

// handleLookupBinary answers "which nixpkgs attribute(s) provide a binary
// named X" using a prebuilt nix-index database (s.nixIndexRef), invoked
// lazily via `nix run` (see nixLocate). It ALWAYS returns candidates only --
// it never builds or publishes anything, unlike handleResolve. Callers
// (pkg-install or a human) make a separate /resolve call with whichever
// candidate attribute they want; that second call goes through the exact
// same validateAttr + nix-build path as any other /resolve request, so a
// candidate surfaced here is never trusted/installed without being
// revalidated end to end.
func (s *server) handleLookupBinary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, lookupResponse{OK: false, Error: "only POST is supported"})
		return
	}

	if s.nixIndexRef == "" {
		writeJSON(w, http.StatusInternalServerError, lookupResponse{OK: false, Error: "pkg-broker was not configured with PKG_BROKER_NIX_INDEX_REF -- /lookup-binary is unavailable"})
		return
	}

	var req lookupRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	if err := dec.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, lookupResponse{OK: false, Error: fmt.Sprintf("invalid JSON body: %v", err)})
		return
	}

	binary := strings.TrimSpace(req.Binary)
	if err := validateBinaryName(binary); err != nil {
		writeJSON(w, http.StatusBadRequest, lookupResponse{OK: false, Binary: binary, Error: err.Error()})
		return
	}

	candidates, err := s.nixLocate(r.Context(), binary)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, lookupResponse{OK: false, Binary: binary, Error: err.Error()})
		return
	}

	if len(candidates) == 0 {
		writeJSON(w, http.StatusNotFound, lookupResponse{OK: false, Binary: binary, Error: fmt.Sprintf("no nixpkgs attribute found providing a binary named %q", binary)})
		return
	}

	writeJSON(w, http.StatusOK, lookupResponse{OK: true, Binary: binary, Candidates: candidates})
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

func validateBinaryName(binary string) error {
	if binary == "" {
		return errors.New("binary must not be empty")
	}
	if len(binary) > maxBinaryLen {
		return fmt.Errorf("binary must be at most %d characters", maxBinaryLen)
	}
	if !binaryPattern.MatchString(binary) {
		return errors.New("binary must be a plain executable name (letters, digits, dot, plus, hyphen, underscore; no slash, no leading hyphen, no whitespace or shell metacharacters)")
	}
	return nil
}

// knownOutputSuffixes are nix output names nix-locate's --minimal mode may
// append to an attribute path (e.g. "protobuf.out"). Candidates are
// returned as plain attrs (suffix stripped) so callers can feed them
// straight into /resolve, which resolves the default (.out-equivalent)
// output itself via plain `nix-build -A <attr>`.
var knownOutputSuffixes = []string{".out", ".bin", ".dev", ".lib", ".doc", ".man", ".debug", ".devdoc", ".info"}

// parseNixLocateOutput turns nix-locate --minimal output (one nixpkgs
// attribute path per line, optionally suffixed with a nix output name) into
// a deduplicated, sorted list of plain attribute names, dropping any line
// that does not pass validateAttr after suffix-stripping (defense in depth:
// this is untrusted-ish third-party tool output, never used for anything
// beyond display/candidate-listing here -- it is revalidated again by
// validateAttr inside handleResolve if a caller acts on a candidate).
func parseNixLocateOutput(raw string) []string {
	seen := make(map[string]struct{})
	var candidates []string
	for _, line := range strings.Split(raw, "\n") {
		attr := strings.TrimSpace(line)
		if attr == "" {
			continue
		}
		for _, suf := range knownOutputSuffixes {
			if strings.HasSuffix(attr, suf) {
				attr = strings.TrimSuffix(attr, suf)
				break
			}
		}
		if err := validateAttr(attr); err != nil {
			continue
		}
		if _, ok := seen[attr]; ok {
			continue
		}
		seen[attr] = struct{}{}
		candidates = append(candidates, attr)
	}
	sort.Strings(candidates)
	return candidates
}

// nixLocate invokes a prebuilt nix-index database lazily, at request time,
// via nix run <s.nixIndexRef>#nix-index-with-db -- <nix-locate flags>
// (requires nix.conf's flakes experimental feature; see its comments).
// This downloads the (sizeable) nix-index database on its first-ever
// invocation against a given nixIndexRef -- s.dbMu serializes calls so
// concurrent first-time requests don't race to download it independently.
// Flags: --at-root (match the binary at the root of an output, i.e.
// bin/<name> itself, not an arbitrary path containing <name>), --whole-name
// (match the whole file name, not a substring), --minimal (print bare
// attribute paths only, one per line -- see parseNixLocateOutput). Note:
// restriction to top-level nixpkgs attrs (as opposed to internal/nested
// derivations) is nix-locate's default behavior now -- --all would disable
// it; there is no --top-level flag to pass.
//
// Verified against nix-locate --help for the pinned nixIndexRef
// (nix-index-database rev 161d7c91): valid flags are -d/--db, -r/--regex,
// -p/--package, --hash, --all, -t/--type, --no-group, --color,
// -w/--whole-name, --at-root, --minimal. --top-level no longer exists for
// this pin and causes "unexpected argument --top-level".
func (s *server) nixLocate(ctx context.Context, binary string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, s.lookupTO)
	defer cancel()

	s.dbMu.Lock()
	defer s.dbMu.Unlock()

	target := "/bin/" + binary
	args := []string{
		"run", s.nixIndexRef + "#nix-index-with-db", "--",
		"--at-root", "--whole-name", "--minimal", "--", target,
	}
	cmd := exec.CommandContext(ctx, "nix", args...)
	// HOME=/var/empty (image.nix) isn't writable; nix needs a writable
	// HOME/XDG_CACHE_HOME for its eval/fetch cache (flake registry, the
	// downloaded nix-index-database tarball, etc.) when running nix run
	// against a flake ref, unlike plain nix-build -A in nixBuild below
	// (which doesn't need this). writableDirs (image.nix) bakes /tmp as a
	// writable, pkg-broker-owned directory for exactly this.
	cmd.Env = append(os.Environ(), "HOME=/tmp", "XDG_CACHE_HOME=/tmp/.cache")
	out, err := cmd.Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			stderr := strings.TrimSpace(string(exitErr.Stderr))
			if stderr == "" && len(strings.TrimSpace(string(out))) == 0 {
				// nix-locate exits non-zero with no output when it simply
				// found no matches -- not a hard failure, just zero candidates.
				return nil, nil
			}
			return nil, fmt.Errorf("nix run %s#nix-index-with-db -- nix-locate failed for binary %q: %s", s.nixIndexRef, binary, stderr)
		}
		return nil, fmt.Errorf("nix run %s#nix-index-with-db -- nix-locate failed for binary %q: %v", s.nixIndexRef, binary, err)
	}

	return parseNixLocateOutput(string(out)), nil
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
