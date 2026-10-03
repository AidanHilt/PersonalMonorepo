// pkg-install is a thin CLI that runs inside the `pi` sandbox container
// and makes a single blocking HTTP call to the `pkg-broker` sidecar
// service (nix/agentic-ai-stack/containers/pkg-broker/) to resolve a
// nixpkgs attribute name and publish its binaries onto `pi`'s PATH.
//
// This is the only new surface pkg-broker's capability is exposed
// through to `pi` — `pi` itself is never given nix/network permissions
// directly (see nix/agentic-ai-stack/.AGENT-PLAN.md decision 5/6 and
// PROJECT-SPEC.md). pkg-install is deliberately NOT allow-listed in
// pi's own permission policy by default; a human operator runs it
// manually (e.g. via `nix run .#shell-agent`) until that's revisited.
//
// Stdlib only (no third-party deps), matching the project's existing
// `kommit`/mkGo convention for scripts that need more than a shell one-
// liner (see nix/scripts/flake.nix's mkScripts).
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

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

func showHelp() {
	fmt.Fprintln(os.Stderr, `Usage:
  pkg-install <attr>

Resolves exactly one nixpkgs attribute (e.g. "ripgrep",
"nodePackages.typescript") against the pkg-broker sidecar service and
publishes its bin/* entries onto this container's PATH. Blocks until
pkg-broker responds (build-from-source fallback can take a while on a
cache miss) and prints a clear pass/fail result.

Env overrides:
  PKG_BROKER_URL   base URL of pkg-broker (default: http://pkg-broker:8080)
  PKG_INSTALL_TIMEOUT_SECONDS   HTTP client timeout (default: 1800, i.e. 30m)
`)
}

func main() {
	flag.Usage = showHelp
	flag.Parse()

	args := flag.Args()
	if len(args) != 1 || args[0] == "" {
		showHelp()
		os.Exit(2)
	}
	attr := args[0]

	baseURL := os.Getenv("PKG_BROKER_URL")
	if baseURL == "" {
		baseURL = "http://pkg-broker:8080"
	}

	timeout := 30 * time.Minute
	if v := os.Getenv("PKG_INSTALL_TIMEOUT_SECONDS"); v != "" {
		var secs int
		if _, err := fmt.Sscanf(v, "%d", &secs); err == nil && secs > 0 {
			timeout = time.Duration(secs) * time.Second
		}
	}

	if err := install(baseURL, attr, timeout); err != nil {
		fmt.Fprintf(os.Stderr, "pkg-install: FAIL: %v\n", err)
		os.Exit(1)
	}
}

func install(baseURL, attr string, timeout time.Duration) error {
	body, err := json.Marshal(resolveRequest{Attr: attr})
	if err != nil {
		return fmt.Errorf("encoding request: %w", err)
	}

	client := &http.Client{Timeout: timeout}

	fmt.Printf("pkg-install: resolving %q via %s/resolve (this blocks until done)...\n", attr, baseURL)

	resp, err := client.Post(baseURL+"/resolve", "application/json", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("calling pkg-broker at %s: %w", baseURL, err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("reading pkg-broker response: %w", err)
	}

	var res resolveResponse
	if err := json.Unmarshal(raw, &res); err != nil {
		return fmt.Errorf("pkg-broker returned an unparseable response (status %d): %s", resp.StatusCode, string(raw))
	}

	if !res.OK {
		if res.Error != "" {
			return fmt.Errorf("%s", res.Error)
		}
		return fmt.Errorf("pkg-broker rejected the request (status %d)", resp.StatusCode)
	}

	if len(res.Binaries) == 0 {
		fmt.Printf("pkg-install: PASS: %q resolved (%v) but published no binaries (no bin/ in the output -- a library, maybe?)\n", attr, res.StorePaths)
		return nil
	}

	fmt.Printf("pkg-install: PASS: %q resolved -- now on PATH: %v\n", attr, res.Binaries)
	return nil
}
