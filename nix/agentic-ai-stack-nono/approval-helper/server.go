package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

const (
	defaultPromptTimeout = 120 * time.Second
	defaultDenyCacheTTL  = 30 * time.Second
)

// inflightPrompt lets concurrent requests for the same host:port share one
// in-progress prompt instead of each popping their own dialog (PLAN.md:
// "The helper should dedupe/rate-limit repeated prompts for the same
// host").
type inflightPrompt struct {
	done   chan struct{}
	result decision
}

// approvalServer implements nono's unsigned webhook v1 approval protocol
// over loopback HTTP. See PLAN.md's "Approval transport"/"Approval helper
// (host side)" decision rows and spikes/all/{handler.sh,
// approval.template.json} for the spike-verified request/response shape.
//
// Never logs the token: expectedPath() embeds it, but logf is only ever
// called after a request has already matched expectedPath(), and its
// arguments never include the token or the raw request path.
type approvalServer struct {
	token         string
	prompter      prompter
	promptTimeout time.Duration
	denyCacheTTL  time.Duration
	now           func() time.Time
	logger        *log.Logger

	mu            sync.Mutex
	inFlight      map[string]*inflightPrompt
	denyCache     map[string]decision
	denyExpiry    map[string]time.Time
	sessionGrants map[string]bool
}

func newApprovalServer(token string, p prompter, logger *log.Logger) *approvalServer {
	return &approvalServer{
		token:         token,
		prompter:      p,
		promptTimeout: defaultPromptTimeout,
		denyCacheTTL:  defaultDenyCacheTTL,
		now:           time.Now,
		logger:        logger,
		inFlight:      make(map[string]*inflightPrompt),
		denyCache:     make(map[string]decision),
		denyExpiry:    make(map[string]time.Time),
		sessionGrants: make(map[string]bool),
	}
}

func (s *approvalServer) expectedPath() string {
	return "/" + s.token
}

func (s *approvalServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Wrong path: 404 and log nothing at all -- this path segment IS the
	// bearer token, so even an access-log line would risk leaking it
	// (PLAN.md: "the helper returns 404 and logs nothing for a wrong
	// path").
	if r.URL.Path != s.expectedPath() {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body webhookRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad request body", http.StatusBadRequest)
		return
	}

	d := s.decide(r.Context(), body.Request)
	s.logf(
		"capability_type=%s host=%s port=%d protocol=%s decision=%s",
		body.Request.CapabilityType, body.Request.Host, body.Request.Port, body.Request.Protocol, d.Type,
	)

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(webhookResponse{Decision: d.Type, Reason: d.Reason}); err != nil {
		s.logf("error writing response: %v", err)
	}
}

func (s *approvalServer) logf(format string, args ...any) {
	if s.logger != nil {
		s.logger.Printf(format, args...)
	}
}

func hostPortKey(host string, port int) string {
	return fmt.Sprintf("%s:%d", host, port)
}

// decide resolves one approval request to a decision, applying (in
// order): the per-host granted_session cache (kept for the helper's whole
// lifetime), the per-host:port deny cache (expires after denyCacheTTL),
// and in-flight prompt dedupe, before falling back to showing a new
// prompt. See PLAN.md's "Approval helper (host side)" decision row.
func (s *approvalServer) decide(ctx context.Context, info capabilityInfo) decision {
	key := hostPortKey(info.Host, info.Port)

	s.mu.Lock()
	if s.sessionGrants[info.Host] {
		s.mu.Unlock()
		return decision{Type: "granted_session"}
	}
	if d, ok := s.denyCache[key]; ok {
		if s.now().Before(s.denyExpiry[key]) {
			s.mu.Unlock()
			return d
		}
		delete(s.denyCache, key)
		delete(s.denyExpiry, key)
	}
	if existing, ok := s.inFlight[key]; ok {
		s.mu.Unlock()
		<-existing.done
		return existing.result
	}
	mine := &inflightPrompt{done: make(chan struct{})}
	s.inFlight[key] = mine
	s.mu.Unlock()

	result := s.promptAndResolve(ctx, info)

	s.mu.Lock()
	delete(s.inFlight, key)
	switch result.Type {
	case "denied":
		s.denyCache[key] = result
		s.denyExpiry[key] = s.now().Add(s.denyCacheTTL)
	case "granted_session":
		s.sessionGrants[info.Host] = true
	}
	s.mu.Unlock()

	mine.result = result
	close(mine.done)
	return result
}

// promptAndResolve shows one prompt, bounded by promptTimeout, and maps
// the user's choice (or a UI failure/timeout) onto a decision. Never
// returns "granted"/"granted_session" on error -- fail closed.
func (s *approvalServer) promptAndResolve(parentCtx context.Context, info capabilityInfo) decision {
	ctx, cancel := context.WithTimeout(parentCtx, s.promptTimeout)
	defer cancel()

	choice, err := s.prompter.Prompt(ctx, info)
	if err != nil {
		return decision{Type: "denied", Reason: "approval UI error or timeout"}
	}
	switch choice {
	case choiceAllowOnce:
		return decision{Type: "granted"}
	case choiceAllowSession:
		return decision{Type: "granted_session"}
	default:
		return decision{Type: "denied", Reason: "denied by user"}
	}
}
