package controller

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	git "github.com/go-git/go-git/v5"
	gitconfig "github.com/go-git/go-git/v5/config"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/transport"
	"github.com/go-git/go-git/v5/storage/memory"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"

	miurav1alpha1 "miura/api/v1alpha1"
)

// refResolutionRetryInterval is how soon a failed source.ref lookup is
// retried when no poll interval applies (e.g. polling is disabled, or
// the ref hasn't ever resolved yet) — otherwise a transient lookup
// failure (or a typo in source.ref that later gets fixed) would never
// be retried.
const refResolutionRetryInterval = 30 * time.Second

// isFullSHA reports whether ref looks like a full, 40-character
// hexadecimal git commit SHA. Full SHAs are resolved directly, without a
// remote lookup: docs/function.md says pollInterval is ignored for both
// tags and SHAs since neither can produce a new commit to detect, and
// unlike a branch/tag name there is no ref to list a SHA against in the
// first place (`git ls-remote` only advertises refs, not arbitrary
// reachable commits).
func isFullSHA(ref string) bool {
	if len(ref) != 40 {
		return false
	}
	for _, r := range ref {
		if !strings.ContainsRune("0123456789abcdefABCDEF", r) {
			return false
		}
	}
	return true
}

// isAuthError reports whether err indicates the remote rejected the
// request for authentication/authorization reasons, as opposed to the
// ref simply not existing. source.secretRef (private repository
// support) is out of scope for this round, so this only ever fires for
// a repository that requires auth miura never attempts to supply.
func isAuthError(err error) bool {
	return errors.Is(err, transport.ErrAuthenticationRequired) || errors.Is(err, transport.ErrAuthorizationFailed)
}

// effectivePollInterval returns fn's configured source poll interval,
// falling back to the operator-wide default when unset.
func (r *FunctionReconciler) effectivePollInterval(fn *miurav1alpha1.Function) time.Duration {
	if fn.Spec.Source.PollInterval != nil {
		return fn.Spec.Source.PollInterval.Duration
	}
	return r.Config.DefaultPollInterval
}

// lsRemote lists refs advertised by the repository at url (an in-process
// equivalent of `git ls-remote`, never touching disk) and resolves ref
// against them: first as a branch, then as a tag. It reports whether the
// match was a branch (the only ref kind worth polling).
func lsRemote(url, ref string) (commit string, isBranch bool, err error) {
	remote := git.NewRemote(memory.NewStorage(), &gitconfig.RemoteConfig{
		Name: "origin",
		URLs: []string{url},
	})
	refs, err := remote.List(&git.ListOptions{})
	if err != nil {
		return "", false, fmt.Errorf("list remote refs: %w", err)
	}

	branchName := plumbing.NewBranchReferenceName(ref)
	tagName := plumbing.NewTagReferenceName(ref)

	var tagCommit string
	for _, rf := range refs {
		switch rf.Name() {
		case branchName:
			return rf.Hash().String(), true, nil
		case tagName:
			tagCommit = rf.Hash().String()
		}
	}
	if tagCommit != "" {
		// A lightweight tag's ref hash is the commit itself; an
		// annotated tag's ref hash is the tag object, not the commit it
		// points at. Peeling annotated tags to their target commit is
		// not implemented in this round (undocumented/deferred edge
		// case — see IMPLEMENTERS.md).
		return tagCommit, false, nil
	}
	return "", false, fmt.Errorf("ref %q not found in %s", ref, url)
}

// resolveSource resolves fn.Spec.Source.Ref against the remote
// repository, updates fn.Status.Source and the SourceResolved condition,
// and returns how soon to requeue to notice a new commit (0 when no
// polling is needed). A failed lookup is reported via the condition, not
// a returned error, so the reconciler's normal error-backoff path isn't
// used for an ordinary "ref not found yet" state.
func (r *FunctionReconciler) resolveSource(ctx context.Context, fn *miurav1alpha1.Function) (time.Duration, error) {
	logger := log.FromContext(ctx)

	ref := fn.Spec.Source.Ref
	if ref == "" {
		ref = "main"
	}

	if isFullSHA(ref) {
		fn.Status.Source.ResolvedCommit = ref
		fn.Status.Source.LastPolledTime = &metav1.Time{Time: time.Now()}
		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionSourceResolved,
			Status:             metav1.ConditionTrue,
			Reason:             miurav1alpha1.ReasonSourceResolved,
			Message:            fmt.Sprintf("source.ref %q is a commit SHA; no polling.", ref),
			ObservedGeneration: fn.Generation,
		})
		return 0, nil
	}

	commit, isBranch, lookupErr := lsRemote(fn.Spec.Source.URL, ref)
	fn.Status.Source.LastPolledTime = &metav1.Time{Time: time.Now()}

	if lookupErr != nil {
		reason := miurav1alpha1.ReasonSourceRefNotFound
		if isAuthError(lookupErr) {
			reason = miurav1alpha1.ReasonSourceAuthFailed
		}
		meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
			Type:               miurav1alpha1.ConditionSourceResolved,
			Status:             metav1.ConditionFalse,
			Reason:             reason,
			Message:            lookupErr.Error(),
			ObservedGeneration: fn.Generation,
		})
		logger.Info("source ref resolution failed", "ref", ref, "reason", reason, "error", lookupErr)

		interval := r.effectivePollInterval(fn)
		if interval <= 0 {
			interval = refResolutionRetryInterval
		}
		return interval, nil
	}

	fn.Status.Source.ResolvedCommit = commit
	meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
		Type:               miurav1alpha1.ConditionSourceResolved,
		Status:             metav1.ConditionTrue,
		Reason:             miurav1alpha1.ReasonSourceResolved,
		Message:            fmt.Sprintf("resolved %q to %s", ref, commit),
		ObservedGeneration: fn.Generation,
	})

	if !isBranch {
		return 0, nil // tags/SHAs are immutable; no need to poll
	}
	interval := r.effectivePollInterval(fn)
	if interval <= 0 {
		return 0, nil // polling explicitly disabled
	}
	return interval, nil
}
