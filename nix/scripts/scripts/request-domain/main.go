// request-domain is a thin CLI that runs inside the `pi` sandbox
// container and makes a single blocking HTTP call to the domain-gate
// service (nix/agentic-ai-stack/containers/proxy/domain-gate/) running
// inside the `proxy` container, asking it to add one exact hostname to
// squid's egress allowlist for the lifetime of the current proxy
// container (session-scoped only -- cleared on proxy restart; see
// nix/agentic-ai-stack/README.md's "Requesting an extra domain at
// runtime" section and PROJECT-SPEC.md §3.2.1).
//
// There is no pending-request queue here: approval is entirely pi's own
// permission system. request-domain is deliberately NOT allow-listed in
// pi's permission policy by default (see
// nix/agentic-ai-stack/config/pi/extensions/pi-permission-system/config.json),
// so every invocation prompts a human before this binary ever runs --
// once it does run, the call itself applies the change.
//
// Stdlib only (no third-party deps), matching the project's existing
// `pkg-install`/mkGo convention for scripts that need more than a shell
// one-liner (see nix/scripts/flake.nix's mkScripts).
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

type allowRequest struct {
	Domain string `json:"domain"`
	Reason string `json:"reason"`
}

type allowResponse struct {
	OK     bool   `json:"ok"`
	Domain string `json:"domain,omitempty"`
	Error  string `json:"error,omitempty"`
}

func showHelp() {
	fmt.Fprintln(os.Stderr, `Usage:
  request-domain <domain> -reason "<why>"

Asks the proxy container's domain-gate sidecar to add <domain> (exactly
one hostname, no wildcards/subdomains) to squid's egress allowlist.
This only lasts for the current proxy container's lifetime -- the
grant is cleared the next time the proxy container restarts. For a
permanent addition, edit
nix/agentic-ai-stack/containers/proxy/allowed-domains.txt and rebuild
the proxy image instead.

Approval happens via pi's own permission prompt on this command itself
-- there is no separate queue or review step. Exits 0 once the domain
is live on the allowlist, non-zero with a clear message on
rejection/error/timeout.

Env overrides:
  DOMAIN_GATE_URL                base URL of domain-gate (default: http://proxy:8081)
  REQUEST_DOMAIN_TIMEOUT_SECONDS HTTP client timeout (default: 30)
`)
}

func main() {
	flag.Usage = showHelp
	reason := flag.String("reason", "", "why this domain needs to be reachable (required)")
	timeoutFlag := flag.Int("timeout", 0, "HTTP client timeout in seconds (default: 30, or REQUEST_DOMAIN_TIMEOUT_SECONDS)")

	// flag.Parse() stops at the first non-flag argument, so flags and the
	// positional <domain> argument can appear in any order (e.g.
	// `-reason x domain`, `domain -reason x`, or `-timeout 5 domain
	// -reason x`). Repeatedly parse, stashing away each positional arg
	// encountered, until there's nothing left to parse.
	fs := flag.CommandLine
	argv := os.Args[1:]
	var positional []string
	for {
		if err := fs.Parse(argv); err != nil {
			os.Exit(2)
		}
		if fs.NArg() == 0 {
			break
		}
		positional = append(positional, fs.Arg(0))
		argv = fs.Args()[1:]
	}

	if len(positional) != 1 || positional[0] == "" || *reason == "" {
		showHelp()
		os.Exit(2)
	}
	domain := positional[0]

	baseURL := os.Getenv("DOMAIN_GATE_URL")
	if baseURL == "" {
		baseURL = "http://proxy:8081"
	}

	timeout := 30 * time.Second
	if *timeoutFlag > 0 {
		timeout = time.Duration(*timeoutFlag) * time.Second
	} else if v := os.Getenv("REQUEST_DOMAIN_TIMEOUT_SECONDS"); v != "" {
		var secs int
		if _, err := fmt.Sscanf(v, "%d", &secs); err == nil && secs > 0 {
			timeout = time.Duration(secs) * time.Second
		}
	}

	if err := requestDomain(baseURL, domain, *reason, timeout); err != nil {
		fmt.Fprintf(os.Stderr, "request-domain: FAIL: %v\n", err)
		os.Exit(1)
	}
}

// requestDomain posts to domain-gate's /allow endpoint. It deliberately
// does NOT go through HTTPS_PROXY/HTTP_PROXY: "proxy" is already in
// pi's NO_PROXY (compose.yaml), so Go's default
// http.ProxyFromEnvironment already bypasses the proxy for this host --
// but a bare http.Client{Timeout: ...} (no Transport override) is used
// here specifically so that default, env-driven behavior governs
// instead of silently hardcoding an assumption that could drift from
// compose.yaml's NO_PROXY value.
func requestDomain(baseURL, domain, reason string, timeout time.Duration) error {
	body, err := json.Marshal(allowRequest{Domain: domain, Reason: reason})
	if err != nil {
		return fmt.Errorf("encoding request: %w", err)
	}

	client := &http.Client{Timeout: timeout}

	fmt.Printf("request-domain: requesting %q via %s/allow (reason: %q)...\n", domain, baseURL, reason)

	resp, err := client.Post(baseURL+"/allow", "application/json", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("calling domain-gate at %s: %w", baseURL, err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("reading domain-gate response: %w", err)
	}

	var res allowResponse
	if err := json.Unmarshal(raw, &res); err != nil {
		return fmt.Errorf("domain-gate returned an unparseable response (status %d): %s", resp.StatusCode, string(raw))
	}

	if !res.OK {
		if res.Error != "" {
			return fmt.Errorf("%s", res.Error)
		}
		return fmt.Errorf("domain-gate rejected the request (status %d)", resp.StatusCode)
	}

	fmt.Printf("request-domain: PASS: %q is now allowed through the proxy for this session (cleared on next proxy restart)\n", res.Domain)
	return nil
}
