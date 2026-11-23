package controller

import (
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	miurav1alpha1 "miura/api/v1alpha1"
)

const (
	reasonReady    = "Ready"
	reasonNotReady = "ComponentNotReady"
)

// presentConditionTypes returns the condition types expected for fn's
// current spec. SourceResolved and Built are always present once
// reconciliation has run past the paused check; Routed is only present
// when triggers.http is set. AuthConfigured is deliberately excluded:
// JWT auth (triggers.http.auth.mode: Jwt) is out of scope for this
// round's reconciler (see IMPLEMENTERS.md) and is never set, so
// including it here would wedge Ready at False forever for every
// Function, not just ones using it.
func presentConditionTypes(fn *miurav1alpha1.Function) []string {
	types := []string{miurav1alpha1.ConditionSourceResolved, miurav1alpha1.ConditionBuilt}
	if fn.Spec.Triggers.HTTP != nil {
		types = append(types, miurav1alpha1.ConditionRouted)
	}
	return types
}

// computeReady sets the Ready condition to the logical AND of whichever
// of presentConditionTypes(fn) are currently True, taking the reason and
// message of the first non-True condition found when it isn't.
func computeReady(fn *miurav1alpha1.Function) {
	status := metav1.ConditionTrue
	reason := reasonReady
	message := "all components ready"

	for _, t := range presentConditionTypes(fn) {
		c := meta.FindStatusCondition(fn.Status.Conditions, t)
		if c != nil && c.Status == metav1.ConditionTrue {
			continue
		}
		status = metav1.ConditionFalse
		if c != nil {
			reason = c.Reason
			message = c.Message
		} else {
			reason = reasonNotReady
			message = t + " has not been reconciled yet"
		}
		break
	}

	meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
		Type:               miurav1alpha1.ConditionReady,
		Status:             status,
		Reason:             reason,
		Message:            message,
		ObservedGeneration: fn.Generation,
	})
}

// setPaused sets Ready=False/Paused and leaves every other condition
// (and any existing Knative Service/VirtualService) untouched, per
// spec.paused's documented behavior in docs/function.md.
func setPaused(fn *miurav1alpha1.Function) {
	meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
		Type:               miurav1alpha1.ConditionReady,
		Status:             metav1.ConditionFalse,
		Reason:             miurav1alpha1.ReasonReadyPaused,
		Message:            "spec.paused is true; polling and new builds are stopped",
		ObservedGeneration: fn.Generation,
	})
}
