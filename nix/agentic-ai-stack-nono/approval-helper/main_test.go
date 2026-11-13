package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// fakePrompter is the injectable test double for prompter: it records how
// many times it was called, can block until released (to deterministically
// test in-flight dedupe), and returns a fixed choice/error.
type fakePrompter struct {
	mu      sync.Mutex
	calls   int
	choice  promptChoice
	err     error
	started chan struct{} // closed once, the first time Prompt is entered
	block   chan struct{} // if non-nil, Prompt blocks on this (or ctx.Done)
}

func (f *fakePrompter) Prompt(ctx context.Context, info capabilityInfo) (promptChoice, error) {
	f.mu.Lock()
	f.calls++
	first := f.calls == 1
	f.mu.Unlock()

	if first && f.started != nil {
		close(f.started)
	}
	if f.block != nil {
		select {
		case <-f.block:
		case <-ctx.Done():
			return 0, ctx.Err()
		}
	}
	return f.choice, f.err
}

func (f *fakePrompter) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

func TestServeHTTP_WrongPathIs404AndLogsNothing(t *testing.T) {
	var logBuf bytes.Buffer
	s := newApprovalServer("secret-token", &fakePrompter{}, log.New(&logBuf, "", 0))

	req := httptest.NewRequest("POST", "http://127.0.0.1/wrong-token", bytes.NewBufferString(`{}`))
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)

	if rec.Code != 404 {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
	if logBuf.Len() != 0 {
		t.Fatalf("expected no log output for a wrong-path request, got: %q", logBuf.String())
	}
}

func TestServeHTTP_WrongMethodIs405(t *testing.T) {
	s := newApprovalServer("tok", &fakePrompter{}, nil)
	req := httptest.NewRequest("GET", "http://127.0.0.1/tok", nil)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != 405 {
		t.Fatalf("expected 405, got %d", rec.Code)
	}
}

func TestServeHTTP_BadJSONIs400(t *testing.T) {
	s := newApprovalServer("tok", &fakePrompter{}, nil)
	req := httptest.NewRequest("POST", "http://127.0.0.1/tok", bytes.NewBufferString(`not json`))
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestServeHTTP_DecisionMapping(t *testing.T) {
	cases := []struct {
		name         string
		choice       promptChoice
		promptErr    error
		wantDecision string
		wantReason   string
	}{
		{"allow once", choiceAllowOnce, nil, "granted", ""},
		{"allow for session", choiceAllowSession, nil, "granted_session", ""},
		{"deny", choiceDeny, nil, "denied", "denied by user"},
		{"ui error fails closed", choiceAllowOnce, errors.New("boom"), "denied", "approval UI error or timeout"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := newApprovalServer("tok", &fakePrompter{choice: tc.choice, err: tc.promptErr}, nil)
			body, _ := json.Marshal(webhookRequest{
				Backend: "dialog",
				Request: capabilityInfo{Host: "example.com", Port: 443, Protocol: "https", CapabilityType: "network"},
			})
			req := httptest.NewRequest("POST", "http://127.0.0.1/tok", bytes.NewReader(body))
			rec := httptest.NewRecorder()
			s.ServeHTTP(rec, req)

			if rec.Code != 200 {
				t.Fatalf("expected 200, got %d (%s)", rec.Code, rec.Body.String())
			}
			var resp webhookResponse
			if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
				t.Fatalf("decoding response: %v", err)
			}
			if resp.Decision != tc.wantDecision {
				t.Fatalf("decision = %q, want %q", resp.Decision, tc.wantDecision)
			}
			if resp.Reason != tc.wantReason {
				t.Fatalf("reason = %q, want %q", resp.Reason, tc.wantReason)
			}
		})
	}
}

func TestDecide_SessionGrantCachedPerHost(t *testing.T) {
	fp := &fakePrompter{choice: choiceAllowSession}
	s := newApprovalServer("tok", fp, nil)

	info := capabilityInfo{Host: "example.com", Port: 443}
	d1 := s.decide(context.Background(), info)
	if d1.Type != "granted_session" {
		t.Fatalf("first decision = %q, want granted_session", d1.Type)
	}

	// A second request to the SAME HOST on a DIFFERENT PORT must reuse the
	// session grant without prompting again.
	info2 := capabilityInfo{Host: "example.com", Port: 8443}
	d2 := s.decide(context.Background(), info2)
	if d2.Type != "granted_session" {
		t.Fatalf("second decision = %q, want granted_session", d2.Type)
	}
	if fp.callCount() != 1 {
		t.Fatalf("expected exactly 1 prompt call, got %d", fp.callCount())
	}
}

func TestDecide_DenyCachedThenExpires(t *testing.T) {
	fp := &fakePrompter{choice: choiceDeny}
	s := newApprovalServer("tok", fp, nil)
	s.denyCacheTTL = 10 * time.Second

	now := time.Unix(1000, 0)
	s.now = func() time.Time { return now }

	info := capabilityInfo{Host: "evil.example", Port: 443}
	d1 := s.decide(context.Background(), info)
	if d1.Type != "denied" {
		t.Fatalf("first decision = %q, want denied", d1.Type)
	}
	if fp.callCount() != 1 {
		t.Fatalf("expected 1 prompt call, got %d", fp.callCount())
	}

	// Still within the deny-cache TTL: no second prompt.
	d2 := s.decide(context.Background(), info)
	if d2.Type != "denied" {
		t.Fatalf("second decision = %q, want denied", d2.Type)
	}
	if fp.callCount() != 1 {
		t.Fatalf("expected deny cache to suppress a second prompt, got %d calls", fp.callCount())
	}

	// Advance past the TTL: a third call must prompt again.
	now = now.Add(11 * time.Second)
	d3 := s.decide(context.Background(), info)
	if d3.Type != "denied" {
		t.Fatalf("third decision = %q, want denied", d3.Type)
	}
	if fp.callCount() != 2 {
		t.Fatalf("expected the deny cache to expire and re-prompt, got %d calls", fp.callCount())
	}
}

func TestDecide_InFlightDedupe(t *testing.T) {
	started := make(chan struct{})
	block := make(chan struct{})
	fp := &fakePrompter{choice: choiceAllowOnce, started: started, block: block}
	s := newApprovalServer("tok", fp, nil)

	joined := make(chan struct{}, 1)
	s.onJoinInFlight = func() { joined <- struct{}{} }

	info := capabilityInfo{Host: "example.com", Port: 443}

	result1 := make(chan decision, 1)
	result2 := make(chan decision, 1)

	go func() { result1 <- s.decide(context.Background(), info) }()
	<-started // the first call is now inside Prompt(), blocked on `block`.

	go func() { result2 <- s.decide(context.Background(), info) }()
	// Unlike relying on happens-before reasoning about when goroutine 2
	// reaches its s.mu.Lock() (which is NOT guaranteed to happen before
	// goroutine 1 finishes and deletes the in-flight entry), we wait for
	// an explicit signal -- onJoinInFlight -- fired only once goroutine 2
	// has actually observed and is about to wait on the shared in-flight
	// entry. Only once that's confirmed do we unblock the prompt, so
	// goroutine 1 cannot finish (and clear the entry) before goroutine 2
	// has joined it.
	select {
	case <-joined:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the second call to join the in-flight prompt")
	}
	close(block)

	d1 := <-result1
	d2 := <-result2
	if d1.Type != "granted" || d2.Type != "granted" {
		t.Fatalf("expected both results granted, got %q and %q", d1.Type, d2.Type)
	}
	if fp.callCount() != 1 {
		t.Fatalf("expected exactly 1 prompt call (deduped), got %d", fp.callCount())
	}
}

func TestDecide_InFlightDedupe_ManyJoiners(t *testing.T) {
	const joiners = 5

	started := make(chan struct{})
	block := make(chan struct{})
	fp := &fakePrompter{choice: choiceAllowOnce, started: started, block: block}
	s := newApprovalServer("tok", fp, nil)

	joined := make(chan struct{}, joiners)
	s.onJoinInFlight = func() { joined <- struct{}{} }

	info := capabilityInfo{Host: "example.com", Port: 443}

	results := make(chan decision, joiners+1)

	go func() { results <- s.decide(context.Background(), info) }()
	<-started // the first call is now inside Prompt(), blocked on `block`.

	for i := 0; i < joiners; i++ {
		go func() { results <- s.decide(context.Background(), info) }()
	}
	// Wait for all `joiners` goroutines to have joined the single
	// in-flight prompt before releasing it, so none of them can race
	// ahead and start a second prompt of their own.
	for i := 0; i < joiners; i++ {
		select {
		case <-joined:
		case <-time.After(5 * time.Second):
			t.Fatalf("timed out waiting for joiner %d to join the in-flight prompt", i)
		}
	}
	close(block)

	for i := 0; i < joiners+1; i++ {
		d := <-results
		if d.Type != "granted" {
			t.Fatalf("expected result %d granted, got %q", i, d.Type)
		}
	}
	if fp.callCount() != 1 {
		t.Fatalf("expected exactly 1 prompt call (deduped across %d joiners), got %d", joiners, fp.callCount())
	}
}

func TestSelectPrompter(t *testing.T) {
	found := func(name string) (string, error) { return "/usr/bin/" + name, nil }
	notFound := func(string) (string, error) { return "", errors.New("not found") }
	only := func(have string) func(string) (string, error) {
		return func(name string) (string, error) {
			if name == have {
				return "/usr/bin/" + name, nil
			}
			return "", errors.New("not found")
		}
	}
	noEnv := func(string) string { return "" }
	withDisplay := func(k string) string {
		if k == "DISPLAY" {
			return ":0"
		}
		return ""
	}

	cases := []struct {
		name     string
		mode     string
		goos     string
		lookPath func(string) (string, error)
		getenv   func(string) string
		want     any // the concrete type we expect back, via a type switch below
	}{
		{"explicit deny-all", "deny-all", "linux", notFound, noEnv, denyAllPrompter{}},
		{"explicit osascript", "osascript", "linux", found, noEnv, &osascriptPrompter{}},
		{"explicit kdialog", "kdialog", "linux", found, noEnv, &kdialogPrompter{}},
		{"explicit tmux", "tmux", "linux", found, noEnv, &tmuxPrompter{}},
		{"auto on darwin picks osascript", "auto", "darwin", found, noEnv, &osascriptPrompter{}},
		{"auto on darwin falls back without osascript", "auto", "darwin", only("tmux"), noEnv, &tmuxPrompter{}},
		{"auto on linux with DISPLAY picks kdialog", "auto", "linux", found, withDisplay, &kdialogPrompter{}},
		{"auto on linux without a desktop picks tmux", "auto", "linux", only("tmux"), noEnv, &tmuxPrompter{}},
		{"auto with nothing available denies", "auto", "linux", notFound, noEnv, denyAllPrompter{}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p, err := selectPrompter(tc.mode, tc.goos, tc.lookPath, tc.getenv)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			switch tc.want.(type) {
			case denyAllPrompter:
				if _, ok := p.(denyAllPrompter); !ok {
					t.Fatalf("got %T, want denyAllPrompter", p)
				}
			case *osascriptPrompter:
				if _, ok := p.(*osascriptPrompter); !ok {
					t.Fatalf("got %T, want *osascriptPrompter", p)
				}
			case *kdialogPrompter:
				if _, ok := p.(*kdialogPrompter); !ok {
					t.Fatalf("got %T, want *kdialogPrompter", p)
				}
			case *tmuxPrompter:
				if _, ok := p.(*tmuxPrompter); !ok {
					t.Fatalf("got %T, want *tmuxPrompter", p)
				}
			}
		})
	}
}

func TestSelectPrompter_UnknownModeErrors(t *testing.T) {
	_, err := selectPrompter("not-a-real-mode", "linux", func(string) (string, error) { return "", errors.New("n/a") }, func(string) string { return "" })
	if err == nil {
		t.Fatal("expected an error for an unknown --ui mode")
	}
}

func TestParseButtonOutput(t *testing.T) {
	cases := map[string]promptChoice{
		"button returned:Allow for session": choiceAllowSession,
		"button returned:Allow once":        choiceAllowOnce,
		"button returned:Deny":              choiceDeny,
		"":                                  choiceDeny,
	}
	for out, want := range cases {
		if got := parseButtonOutput(out); got != want {
			t.Errorf("parseButtonOutput(%q) = %v, want %v", out, got, want)
		}
	}
}

func TestNewToken(t *testing.T) {
	tok, err := newToken()
	if err != nil {
		t.Fatalf("newToken: %v", err)
	}
	if len(tok) != 32 {
		t.Fatalf("expected a 32-char hex token (16 random bytes), got len %d: %q", len(tok), tok)
	}
	for _, r := range tok {
		if !((r >= '0' && r <= '9') || (r >= 'a' && r <= 'f')) {
			t.Fatalf("token contains a non-hex character: %q", tok)
		}
	}

	tok2, err := newToken()
	if err != nil {
		t.Fatalf("newToken: %v", err)
	}
	if tok == tok2 {
		t.Fatal("two calls to newToken produced the same token")
	}
}

func TestHostPortKey(t *testing.T) {
	if got := hostPortKey("example.com", 443); got != "example.com:443" {
		t.Fatalf("hostPortKey = %q", got)
	}
}

func TestRun_UnknownUIModeErrorsBeforeBindingAnyPort(t *testing.T) {
	var stdout, stderr bytes.Buffer
	err := run([]string{"--ui", "not-a-real-mode"}, &stdout, &stderr)
	if err == nil {
		t.Fatal("expected an error for an unknown --ui mode")
	}
	if stdout.Len() != 0 {
		t.Fatalf("expected no startup line to be printed on a flag-validation error, got: %q", stdout.String())
	}
}
