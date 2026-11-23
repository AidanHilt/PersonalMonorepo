package controller

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	miurav1alpha1 "miura/api/v1alpha1"
)

// knativeServiceGVK is the GVK of the Knative Serving Service this
// reconciler manages as unstructured.Unstructured, deliberately avoiding
// a knative.dev/serving client dependency (see IMPLEMENTERS.md's style
// guide).
var knativeServiceGVK = schema.GroupVersionKind{
	Group:   "serving.knative.dev",
	Version: "v1",
	Kind:    "Service",
}

const (
	knativeVisibilityLabel       = "networking.knative.dev/visibility"
	knativeVisibilityClusterOnly = "cluster-local"

	knativeMinScaleAnnotation = "autoscaling.knative.dev/min-scale"
	knativeMaxScaleAnnotation = "autoscaling.knative.dev/max-scale"

	defaultRuntimePort = 8080
)

// reconcileServing creates or updates fn's Knative Service once a built
// image is known (fn.Status.Image is set); it is a no-op before the
// first successful build.
func (r *FunctionReconciler) reconcileServing(ctx context.Context, fn *miurav1alpha1.Function) error {
	if fn.Status.Image == "" {
		return nil
	}

	svc := &unstructured.Unstructured{}
	svc.SetGroupVersionKind(knativeServiceGVK)
	svc.SetName(fn.Name)
	svc.SetNamespace(fn.Namespace)

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		if err := controllerutil.SetControllerReference(fn, svc, r.Scheme); err != nil {
			return err
		}
		return r.populateKnativeService(fn, svc)
	})
	if err != nil {
		return fmt.Errorf("reconcile knative service: %w", err)
	}
	return nil
}

// populateKnativeService fills in svc's labels and spec.template from
// fn. If triggers.http is unset, the Service is labeled cluster-local so
// it receives no ingress traffic and routing.go creates no
// VirtualService for it.
func (r *FunctionReconciler) populateKnativeService(fn *miurav1alpha1.Function, svc *unstructured.Unstructured) error {
	labels := svc.GetLabels()
	if labels == nil {
		labels = map[string]string{}
	}
	if fn.Spec.Triggers.HTTP == nil {
		labels[knativeVisibilityLabel] = knativeVisibilityClusterOnly
	} else {
		delete(labels, knativeVisibilityLabel)
	}
	svc.SetLabels(labels)

	port := fn.Spec.Runtime.Port
	if port == 0 {
		port = defaultRuntimePort
	}

	container := map[string]interface{}{
		"image": fn.Status.Image,
		"ports": []interface{}{
			map[string]interface{}{"containerPort": int64(port)},
		},
	}
	if len(fn.Spec.Runtime.Env) > 0 {
		v, err := toJSONValue(fn.Spec.Runtime.Env)
		if err != nil {
			return fmt.Errorf("convert runtime.env: %w", err)
		}
		container["env"] = v
	}
	if len(fn.Spec.Runtime.EnvFrom) > 0 {
		v, err := toJSONValue(fn.Spec.Runtime.EnvFrom)
		if err != nil {
			return fmt.Errorf("convert runtime.envFrom: %w", err)
		}
		container["envFrom"] = v
	}
	if resourcesSet(fn.Spec.Runtime.Resources) {
		v, err := toJSONValue(fn.Spec.Runtime.Resources)
		if err != nil {
			return fmt.Errorf("convert runtime.resources: %w", err)
		}
		container["resources"] = v
	}
	if fn.Spec.Runtime.Probes != nil {
		if fn.Spec.Runtime.Probes.Liveness != nil {
			v, err := toJSONValue(fn.Spec.Runtime.Probes.Liveness)
			if err != nil {
				return fmt.Errorf("convert runtime.probes.liveness: %w", err)
			}
			container["livenessProbe"] = v
		}
		if fn.Spec.Runtime.Probes.Readiness != nil {
			v, err := toJSONValue(fn.Spec.Runtime.Probes.Readiness)
			if err != nil {
				return fmt.Errorf("convert runtime.probes.readiness: %w", err)
			}
			container["readinessProbe"] = v
		}
	}

	templateSpec := map[string]interface{}{
		"containers": []interface{}{container},
	}
	if fn.Spec.Runtime.ServiceAccountName != "" {
		templateSpec["serviceAccountName"] = fn.Spec.Runtime.ServiceAccountName
	}
	if fn.Spec.Runtime.Concurrency != nil {
		templateSpec["containerConcurrency"] = int64(*fn.Spec.Runtime.Concurrency)
	}
	if fn.Spec.Runtime.Timeout != nil {
		templateSpec["timeoutSeconds"] = int64(fn.Spec.Runtime.Timeout.Duration.Seconds())
	}

	templateAnnotations := map[string]interface{}{}
	maxScale := r.Config.DefaultMaxScale
	if fn.Spec.Runtime.MaxScale != nil {
		maxScale = *fn.Spec.Runtime.MaxScale
	}
	if maxScale > 0 {
		templateAnnotations[knativeMaxScaleAnnotation] = fmt.Sprintf("%d", maxScale)
	}
	if fn.Spec.Runtime.MinScale != nil {
		templateAnnotations[knativeMinScaleAnnotation] = fmt.Sprintf("%d", *fn.Spec.Runtime.MinScale)
	}

	template := map[string]interface{}{
		"spec": templateSpec,
	}
	if len(templateAnnotations) > 0 {
		template["metadata"] = map[string]interface{}{
			"annotations": templateAnnotations,
		}
	}

	return unstructured.SetNestedMap(svc.Object, map[string]interface{}{
		"template": template,
	}, "spec")
}

// resourcesSet reports whether res has any field set, so an entirely
// zero-value ResourceRequirements is omitted rather than rendered as an
// explicit empty object.
func resourcesSet(res corev1.ResourceRequirements) bool {
	return len(res.Limits) > 0 || len(res.Requests) > 0 || len(res.Claims) > 0
}
