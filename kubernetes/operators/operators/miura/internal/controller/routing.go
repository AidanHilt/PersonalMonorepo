package controller

import (
	"context"
	"fmt"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	miurav1alpha1 "miura/api/v1alpha1"
)

// istioVirtualServiceGVK is the GVK of the Istio VirtualService this
// reconciler manages as unstructured.Unstructured (see IMPLEMENTERS.md's
// style guide: no typed istio.io client dependency).
var istioVirtualServiceGVK = schema.GroupVersionKind{
	Group:   "networking.istio.io",
	Version: "v1beta1",
	Kind:    "VirtualService",
}

const (
	reasonRoutedConfigured = "Configured"
	reasonRoutedFailed     = "Failed"

	// knativeLocalGatewayHost is the cluster-local Service every
	// Knative Route is reachable through inside the mesh. Routing
	// external traffic to it — rather than addressing a Knative-managed
	// Service/VirtualService directly — is the documented pattern for
	// fronting a Knative Service with a hand-authored Istio
	// VirtualService on a custom (non-Knative-owned) Gateway: the
	// generated VirtualService below forwards matched requests to this
	// gateway Service with the Host header rewritten to the Knative
	// Service's own cluster-local hostname
	// ("<name>.<namespace>.svc.cluster.local"), and Knative's internal
	// routing (sidecar-injected, Host-header-based) takes it from
	// there. See IMPLEMENTERS.md for more on this choice and the
	// alternative considered (addressing the Knative-generated child
	// objects directly).
	knativeLocalGatewayHost = "knative-local-gateway.istio-system.svc.cluster.local"
	knativeLocalGatewayPort = 80
)

// reconcileRouting creates or updates fn's VirtualService when
// triggers.http is set, deletes it when triggers.http has been removed,
// and sets the Routed condition and status.url accordingly.
func (r *FunctionReconciler) reconcileRouting(ctx context.Context, fn *miurav1alpha1.Function) error {
	http := fn.Spec.Triggers.HTTP
	if http == nil {
		fn.Status.URL = ""
		// Routed is only meant to be present when triggers.http is set
		// (docs/function.md); remove it if a previous reconcile set it.
		meta.RemoveStatusCondition(&fn.Status.Conditions, miurav1alpha1.ConditionRouted)
		return r.deleteVirtualService(ctx, fn)
	}

	host := http.Hostname
	if host == "" {
		host = fmt.Sprintf("%s.%s", fn.Name, r.Config.DefaultDomain)
	}
	pathPrefix := http.PathPrefix
	if pathPrefix == "" {
		pathPrefix = "/"
	}
	gwName := r.Config.DefaultGatewayName
	gwNamespace := r.Config.DefaultGatewayNamespace
	if http.Gateway != nil {
		if http.Gateway.Name != "" {
			gwName = http.Gateway.Name
		}
		if http.Gateway.Namespace != "" {
			gwNamespace = http.Gateway.Namespace
		}
	}

	vs := &unstructured.Unstructured{}
	vs.SetGroupVersionKind(istioVirtualServiceGVK)
	vs.SetName(fn.Name)
	vs.SetNamespace(fn.Namespace)

	_, reconcileErr := controllerutil.CreateOrUpdate(ctx, r.Client, vs, func() error {
		if err := controllerutil.SetControllerReference(fn, vs, r.Scheme); err != nil {
			return err
		}
		return unstructured.SetNestedMap(vs.Object, map[string]interface{}{
			"hosts":    []interface{}{host},
			"gateways": []interface{}{fmt.Sprintf("%s/%s", gwNamespace, gwName)},
			"http": []interface{}{
				map[string]interface{}{
					"match": []interface{}{
						map[string]interface{}{
							"uri": map[string]interface{}{"prefix": pathPrefix},
						},
					},
					"route": []interface{}{
						map[string]interface{}{
							"destination": map[string]interface{}{
								"host": knativeLocalGatewayHost,
								"port": map[string]interface{}{"number": int64(knativeLocalGatewayPort)},
							},
							"headers": map[string]interface{}{
								"request": map[string]interface{}{
									"set": map[string]interface{}{
										"Host": fmt.Sprintf("%s.%s.svc.cluster.local", fn.Name, fn.Namespace),
									},
								},
							},
						},
					},
				},
			},
		}, "spec")
	})

	status := metav1.ConditionTrue
	reason := reasonRoutedConfigured
	message := fmt.Sprintf("routed %s%s", host, pathPrefix)
	if reconcileErr != nil {
		status = metav1.ConditionFalse
		reason = reasonRoutedFailed
		message = reconcileErr.Error()
	}
	meta.SetStatusCondition(&fn.Status.Conditions, metav1.Condition{
		Type:               miurav1alpha1.ConditionRouted,
		Status:             status,
		Reason:             reason,
		Message:            message,
		ObservedGeneration: fn.Generation,
	})
	if reconcileErr != nil {
		return fmt.Errorf("reconcile virtual service: %w", reconcileErr)
	}

	// No TLS/certificate configuration exists anywhere in the Function
	// API today, so status.url is reported as plain http://; see
	// IMPLEMENTERS.md.
	fn.Status.URL = fmt.Sprintf("http://%s%s", host, pathPrefix)
	return nil
}

// deleteVirtualService removes fn's VirtualService, if any, used when
// triggers.http has been unset from a Function that previously had it.
func (r *FunctionReconciler) deleteVirtualService(ctx context.Context, fn *miurav1alpha1.Function) error {
	vs := &unstructured.Unstructured{}
	vs.SetGroupVersionKind(istioVirtualServiceGVK)
	if err := r.Get(ctx, client.ObjectKey{Namespace: fn.Namespace, Name: fn.Name}, vs); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("get virtual service for deletion: %w", err)
	}
	if err := r.Delete(ctx, vs); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete virtual service: %w", err)
	}
	return nil
}
