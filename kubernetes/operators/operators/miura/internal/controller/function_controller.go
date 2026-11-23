// Package controller implements miura's Function reconciler: resolving
// spec.source.ref to a commit, building it with ko in a batch/v1 Job,
// and reconciling the generated Knative Service and Istio VirtualService
// — see docs/function.md (authoritative spec) and IMPLEMENTERS.md
// (design rationale) for the full picture. Reconciliation logic is
// split by concern: source.go (ref resolution/polling), build.go (the
// build Job), serving.go (the Knative Service), routing.go (the Istio
// VirtualService), and status.go (the Ready condition). This file holds
// the top-level Reconcile orchestration and manager wiring.
package controller

import (
	"context"
	"fmt"

	batchv1 "k8s.io/api/batch/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	miurav1alpha1 "miura/api/v1alpha1"
	"miura/internal/config"
)

// FunctionReconciler reconciles a Function object.
type FunctionReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	Config *config.Config
}

// Markers below are what controller-gen reads to produce RBAC. If this
// reconciler starts touching a new resource kind, add a marker here or the
// generated role silently won't grant access to it.
//
// +kubebuilder:rbac:groups=miura.io,resources=functions,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=miura.io,resources=functions/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=batch,resources=jobs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch
// +kubebuilder:rbac:groups=serving.knative.dev,resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=networking.istio.io,resources=virtualservices,verbs=get;list;watch;create;update;patch;delete

func (r *FunctionReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var fn miurav1alpha1.Function
	if err := r.Get(ctx, req.NamespacedName, &fn); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	original := fn.DeepCopy()
	fn.Status.ObservedGeneration = fn.Generation

	result, reconcileErr := r.doReconcile(ctx, &fn)

	if statusErr := r.Status().Patch(ctx, &fn, client.MergeFrom(original)); statusErr != nil {
		logger.Error(statusErr, "failed to update Function status")
		if reconcileErr == nil {
			reconcileErr = fmt.Errorf("update status: %w", statusErr)
		}
	}

	return result, reconcileErr
}

// doReconcile holds the actual reconciliation steps. It is kept separate
// from Reconcile so the status patch above always happens exactly once,
// regardless of which step below returns early.
func (r *FunctionReconciler) doReconcile(ctx context.Context, fn *miurav1alpha1.Function) (ctrl.Result, error) {
	if fn.Spec.Paused {
		setPaused(fn)
		return ctrl.Result{}, nil
	}

	pollRequeue, err := r.resolveSource(ctx, fn)
	if err != nil {
		computeReady(fn)
		return ctrl.Result{}, fmt.Errorf("resolve source: %w", err)
	}
	if fn.Status.Source.ResolvedCommit == "" {
		// Never successfully resolved (e.g. a brand new Function whose
		// ref doesn't exist yet): nothing to build/serve/route yet.
		computeReady(fn)
		return ctrl.Result{RequeueAfter: pollRequeue}, nil
	}

	buildRequeue, err := r.reconcileBuild(ctx, fn)
	if err != nil {
		computeReady(fn)
		return ctrl.Result{}, fmt.Errorf("reconcile build: %w", err)
	}

	if err := r.reconcileServing(ctx, fn); err != nil {
		computeReady(fn)
		return ctrl.Result{}, fmt.Errorf("reconcile serving: %w", err)
	}

	if err := r.reconcileRouting(ctx, fn); err != nil {
		computeReady(fn)
		return ctrl.Result{}, fmt.Errorf("reconcile routing: %w", err)
	}

	computeReady(fn)

	requeueAfter := pollRequeue
	if buildRequeue > 0 && (requeueAfter == 0 || buildRequeue < requeueAfter) {
		requeueAfter = buildRequeue
	}
	return ctrl.Result{RequeueAfter: requeueAfter}, nil
}

func (r *FunctionReconciler) SetupWithManager(mgr ctrl.Manager) error {
	ksvc := &unstructured.Unstructured{}
	ksvc.SetGroupVersionKind(knativeServiceGVK)

	vs := &unstructured.Unstructured{}
	vs.SetGroupVersionKind(istioVirtualServiceGVK)

	return ctrl.NewControllerManagedBy(mgr).
		For(&miurav1alpha1.Function{}).
		Owns(&batchv1.Job{}).
		Owns(ksvc).
		Owns(vs).
		Complete(r)
}
