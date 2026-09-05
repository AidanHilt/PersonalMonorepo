package controller

import (
	"context"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	gitfunctionv1alpha1 "github.com/example/gitfunction-operator/api/v1alpha1"
)

// GitFunctionReconciler reconciles a GitFunction object.
type GitFunctionReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// Markers below are what controller-gen reads to produce RBAC. If this
// reconciler starts touching a new resource kind, add a marker here or the
// generated role silently won't grant access to it.
//
// +kubebuilder:rbac:groups=git.example.com,resources=gitfunctions,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=git.example.com,resources=gitfunctions/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

func (r *GitFunctionReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	// Business logic for this operator is out of scope for the build-tooling
	// spec this scaffold exists to exercise.
	return ctrl.Result{}, nil
}

func (r *GitFunctionReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&gitfunctionv1alpha1.GitFunction{}).
		Complete(r)
}
