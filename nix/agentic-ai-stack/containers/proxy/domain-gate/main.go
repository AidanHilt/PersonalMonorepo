// domain-gate is a small HTTP service that runs INSIDE the `proxy`
// container (supervised alongside squid by supervise.sh), giving `pi` a
// narrow, session-scoped way to add exactly one exact hostname to the
// egress allowlist at runtime, without rebuilding/reloading the proxy
// image. See nix/agentic-ai-stack/README.md's "Requesting an extra
// domain at runtime" section and PROJECT-SPEC.md §3.2.1.
//
// Approval model: there is no queue or separate approval step here --
// pi's own permission system is the approval gate (the `request-domain`
// CLI that calls this endpoint is deliberately NOT allow-listed in pi's
// permission policy, so each call prompts a human). Once a call reaches
// this service, it is already approved; this service's job is purely to
// validate the hostname and apply the change safely.
//
// Entries are written to /tmp/proxy-runtime/dynamic-domains.txt, which
// lives on the container's tmpfs /tmp -- NOT the static,
// image-baked /etc/squid/allowed-domains.txt -- so every dynamic grant
// is wiped the moment the proxy container restarts. Permanent additions
// still go through the static file and an image rebuild, same as today.
//
// Stdlib only, matching the project's Go convention (see
// nix/scripts/scripts/pkg-install and containers/pkg-broker/main.go).
// This service is itself part of the trust boundary (it is the only
// thing on the internal network allowed to rewrite squid's dynamic ACL
// file and trigger a reconfigure), so validation here is deliberately
// strict and conservative: reject on any doubt rather than guess.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
)

const (
	dynamicDomainsPath = "/tmp/proxy-runtime/dynamic-domains.txt"
	squidConfigPath    = "/etc/proxy/squid.conf"
	maxDynamicDomains  = 50
	maxDomainLength    = 253
	maxLabelLength     = 63
	maxReasonLength    = 500
)

// Suffixes that indicate an internal/non-routable name rather than a real
// external hostname -- these must never land in the egress allowlist.
var internalSuffixes = []string{
	".local", ".internal", ".lan", ".svc", ".cluster.local", ".home.arpa",
}

// Known compose service names on the `internal`/`external` networks.
// Defense in depth: bare service names are already rejected by the
// single-label check below, but this also catches them if ever
// referenced with a trailing dot or similar.
var internalServiceNames = map[string]bool{
	"proxy":              true,
	"pkg-broker":         true,
	"pi":                 true,
	"login":              true,
	"workspace-mounter":  true,
	"nix-store-mounter":  true,
	"localhost":          true,
}

type allowRequest struct {
	Domain string `json:"domain"`
	Reason string `json:"reason"`
}

type allowResponse struct {
	OK     bool   `json:"ok"`
	Domain string `json:"domain,omitempty"`
	Error  string `json:"error,omitempty"`
}

// mu serializes the whole read-check-append-reconfigure-rollback sequence
// so concurrent requests can't interleave writes to dynamic-domains.txt
// or race on `squid -k reconfigure`.
var mu sync.Mutex

func main() {
	listen := os.Getenv("DOMAIN_GATE_LISTEN")
	if listen == "" {
		listen = "0.0.0.0:8081"
	}

	if err := ensureDynamicDomainsFile(); err != nil {
		log.Fatalf("domain-gate: cannot initialize %s: %v", dynamicDomainsPath, err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/allow", handleAllow)
	mux.HandleFunc("/healthz", handleHealthz)

	log.Printf("domain-gate: listening on %s", listen)
	if err := http.ListenAndServe(listen, mux); err != nil {
		log.Fatalf("domain-gate: server exited: %v", err)
	}
}

// ensureDynamicDomainsFile creates an empty dynamic-domains.txt if it
// doesn't exist yet. Normally supervise.sh already does this before
// starting either squid or domain-gate (squid's dstdomain ACL fails to
// start if the file is missing), but this is a harmless belt-and-braces
// check in case domain-gate starts first or is run standalone.
func ensureDynamicDomainsFile() error {
	if _, err := os.Stat(dynamicDomainsPath); err == nil {
		return nil
	}
	return os.WriteFile(dynamicDomainsPath, nil, 0644)
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func handleAllow(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, allowResponse{OK: false, Error: "POST only"})
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<16))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, allowResponse{OK: false, Error: "reading request body: " + err.Error()})
		return
	}

	var req allowRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, allowResponse{OK: false, Error: "invalid JSON: " + err.Error()})
		return
	}

	domain, err := normalizeAndValidateDomain(req.Domain)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, allowResponse{OK: false, Domain: req.Domain, Error: err.Error()})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		writeJSON(w, http.StatusBadRequest, allowResponse{OK: false, Domain: domain, Error: "reason is required"})
		return
	}
	if len(reason) > maxReasonLength {
		writeJSON(w, http.StatusBadRequest, allowResponse{OK: false, Domain: domain, Error: fmt.Sprintf("reason exceeds %d characters", maxReasonLength)})
		return
	}

	if err := grantDomain(domain, reason); err != nil {
		writeJSON(w, http.StatusInternalServerError, allowResponse{OK: false, Domain: domain, Error: err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, allowResponse{OK: true, Domain: domain})
}

func writeJSON(w http.ResponseWriter, status int, resp allowResponse) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(resp)
}

// normalizeAndValidateDomain lowercases, trims a trailing dot, and rejects
// anything that isn't a plausible single, external hostname: wildcards,
// leading dots, IP literals, localhost, single-label names, known
// internal suffixes/service names, and anything outside RFC 1035's
// charset/length/label limits.
func normalizeAndValidateDomain(raw string) (string, error) {
	d := strings.ToLower(strings.TrimSpace(raw))
	if d == "" {
		return "", errors.New("domain is required")
	}
	d = strings.TrimSuffix(d, ".")

	if strings.Contains(d, "*") {
		return "", errors.New("wildcard domains are not allowed")
	}
	if strings.HasPrefix(d, ".") {
		return "", errors.New("leading dot (implicit wildcard) is not allowed")
	}
	if len(d) > maxDomainLength {
		return "", fmt.Errorf("domain exceeds %d characters", maxDomainLength)
	}
	if strings.Contains(d, ":") || strings.Contains(d, "[") || strings.Contains(d, "]") {
		return "", errors.New("IP literals are not allowed, only hostnames")
	}
	if ip := net.ParseIP(d); ip != nil {
		return "", errors.New("IP literals are not allowed, only hostnames")
	}

	labels := strings.Split(d, ".")
	if len(labels) < 2 {
		return "", errors.New("single-label hostnames are not allowed (internal service names must go through the static allowlist, not this endpoint)")
	}

	for _, label := range labels {
		if label == "" {
			return "", errors.New("empty label (consecutive dots) is not allowed")
		}
		if len(label) > maxLabelLength {
			return "", fmt.Errorf("label %q exceeds %d characters", label, maxLabelLength)
		}
		for _, c := range label {
			if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
				return "", fmt.Errorf("domain contains invalid character %q (only a-z, 0-9, - and . are allowed)", c)
			}
		}
		if label[0] == '-' || label[len(label)-1] == '-' {
			return "", errors.New("labels may not start or end with a hyphen")
		}
	}

	if internalServiceNames[d] {
		return "", fmt.Errorf("%q looks like an internal compose service name, not an external hostname", d)
	}
	for _, suffix := range internalSuffixes {
		if strings.HasSuffix(d, suffix) {
			return "", fmt.Errorf("%q has an internal-looking suffix (%s) and is not allowed", d, suffix)
		}
	}

	return d, nil
}

// grantDomain is idempotent: a domain already present in the dynamic list
// returns success immediately without touching the file or reconfiguring
// squid again. Otherwise it appends, reconfigures squid, and rolls the
// file back to its previous contents if reconfigure fails -- squid's
// running config must never diverge from what's actually on disk.
func grantDomain(domain, reason string) error {
	mu.Lock()
	defer mu.Unlock()

	existing, err := readDomains()
	if err != nil {
		return fmt.Errorf("reading %s: %w", dynamicDomainsPath, err)
	}

	for _, d := range existing {
		if d == domain {
			log.Printf("domain-gate: %q already allowed, reason=%q (idempotent, no reconfigure)", domain, reason)
			return nil
		}
	}

	if len(existing) >= maxDynamicDomains {
		return fmt.Errorf("dynamic allowlist is full (%d entries, max %d) -- restart the proxy container to clear it", len(existing), maxDynamicDomains)
	}

	updated := append(existing, domain)
	if err := writeDomains(updated); err != nil {
		return fmt.Errorf("writing %s: %w", dynamicDomainsPath, err)
	}

	if err := reconfigureSquid(); err != nil {
		if rbErr := writeDomains(existing); rbErr != nil {
			log.Printf("domain-gate: ROLLBACK FAILED for %q after reconfigure error (%v): %v", domain, err, rbErr)
		}
		return fmt.Errorf("squid reconfigure failed, change rolled back: %w", err)
	}

	log.Printf("domain-gate: GRANTED domain=%q reason=%q dynamic_entries=%d", domain, reason, len(updated))
	return nil
}

func readDomains() ([]string, error) {
	data, err := os.ReadFile(dynamicDomainsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			out = append(out, line)
		}
	}
	return out, nil
}

func writeDomains(domains []string) error {
	var buf bytes.Buffer
	for _, d := range domains {
		buf.WriteString(d)
		buf.WriteByte('\n')
	}
	tmp := dynamicDomainsPath + ".tmp"
	if err := os.WriteFile(tmp, buf.Bytes(), 0644); err != nil {
		return err
	}
	return os.Rename(tmp, dynamicDomainsPath)
}

func reconfigureSquid() error {
	cmd := exec.Command("squid", "-f", squidConfigPath, "-k", "reconfigure")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
