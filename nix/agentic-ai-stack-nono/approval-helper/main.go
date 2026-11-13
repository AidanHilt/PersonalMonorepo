// Command approval-helper is the host-side process the nono launcher
// starts before each `nono run`, implementing nono's unsigned webhook v1
// approval protocol over a loopback-only HTTP listener (never the
// `unix://` transport -- see PLAN.md's "Approval transport" decision
// row). It never runs inside the sandbox itself.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"syscall"
	"time"
)

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "approval-helper:", err)
		os.Exit(1)
	}
}

// run contains all of main's logic other than the process exit itself,
// so it can be driven by a test with fake stdout/stderr writers.
func run(args []string, stdout, stderr io.Writer) error {
	fs := flag.NewFlagSet("approval-helper", flag.ContinueOnError)
	uiMode := fs.String("ui", "auto", "UI backend: auto|osascript|kdialog|tmux|deny-all")
	infoFile := fs.String("info-file", "", "optional path to also write the startup {port,token,url} JSON line to (written mode 0600)")
	parentPID := fs.Int("parent-pid", 0, "if set, shut down once this PID is no longer alive")
	timeoutSecs := fs.Int("timeout", int(defaultPromptTimeout.Seconds()), "seconds to wait for a user response before failing closed")
	denyCacheSecs := fs.Int("deny-cache-secs", int(defaultDenyCacheTTL.Seconds()), "seconds to cache a deny decision for the same host:port before prompting again")
	if err := fs.Parse(args); err != nil {
		return err
	}

	promptUI, err := selectPrompter(*uiMode, runtime.GOOS, exec.LookPath, os.Getenv)
	if err != nil {
		return err
	}

	token, err := newToken()
	if err != nil {
		return fmt.Errorf("generating token: %w", err)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return fmt.Errorf("binding loopback listener: %w", err)
	}

	logger := log.New(stderr, "approval-helper: ", log.LstdFlags)

	srv := newApprovalServer(token, promptUI, logger)
	srv.promptTimeout = time.Duration(*timeoutSecs) * time.Second
	srv.denyCacheTTL = time.Duration(*denyCacheSecs) * time.Second

	port := listener.Addr().(*net.TCPAddr).Port
	url := fmt.Sprintf("http://127.0.0.1:%d/%s", port, token)

	startupLine, err := json.Marshal(startupInfo{Port: port, Token: token, URL: url})
	if err != nil {
		return fmt.Errorf("encoding startup info: %w", err)
	}
	fmt.Fprintln(stdout, string(startupLine))

	if *infoFile != "" {
		if err := os.WriteFile(*infoFile, append(startupLine, '\n'), 0o600); err != nil {
			return fmt.Errorf("writing --info-file: %w", err)
		}
	}

	httpServer := &http.Server{Handler: srv}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigCh)
	go func() {
		select {
		case <-sigCh:
			logger.Println("received shutdown signal")
			cancel()
		case <-ctx.Done():
		}
	}()

	if *parentPID > 0 {
		go watchParent(ctx, *parentPID, cancel, logger)
	}

	serveErr := make(chan error, 1)
	go func() {
		serveErr <- httpServer.Serve(listener)
	}()

	select {
	case err := <-serveErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-ctx.Done():
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			logger.Printf("error during shutdown: %v", err)
		}
		<-serveErr
		return nil
	}
}

func newToken() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

// watchParent polls --parent-pid for liveness (signal 0 is a pure
// existence/permission check -- no signal is actually delivered) and
// cancels ctx once it's gone, so a `--detached` launcher's helper process
// exits along with the launcher that started it, instead of outliving it
// as an orphan. On other platforms where this doesn't apply in the same
// way, --parent-pid simply isn't passed by the launcher.
func watchParent(ctx context.Context, pid int, cancel context.CancelFunc, logger *log.Logger) {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			proc, err := os.FindProcess(pid)
			if err != nil {
				logger.Printf("parent pid %d no longer found: %v", pid, err)
				cancel()
				return
			}
			if err := proc.Signal(syscall.Signal(0)); err != nil {
				logger.Printf("parent pid %d no longer alive: %v", pid, err)
				cancel()
				return
			}
		}
	}
}
