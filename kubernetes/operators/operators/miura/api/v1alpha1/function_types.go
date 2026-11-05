package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Condition types set on Function.status.conditions.
//
// Routed and AuthConfigured are only present when applicable: Routed is
// only set when spec.triggers.http is configured, and AuthConfigured is
// only set when spec.triggers.http.auth.mode is Jwt. Ready is the logical
// AND of whichever of SourceResolved/Built/Routed/AuthConfigured are
// present for the current spec.
const (
	// ConditionSourceResolved tracks whether spec.source.ref has been
	// resolved to a commit.
	ConditionSourceResolved = "SourceResolved"
	// ConditionBuilt tracks whether the resolved commit has a successful
	// build.
	ConditionBuilt = "Built"
	// ConditionRouted tracks whether HTTP routing (VirtualService) has
	// been reconciled. Only present when spec.triggers.http is set.
	ConditionRouted = "Routed"
	// ConditionAuthConfigured tracks whether JWT authentication objects
	// (RequestAuthentication/AuthorizationPolicy) have been reconciled.
	// Only present when spec.triggers.http.auth.mode is Jwt.
	ConditionAuthConfigured = "AuthConfigured"
	// ConditionReady is the overall health condition: the AND of
	// whichever of the above conditions are present for the current spec.
	ConditionReady = "Ready"
)

// Condition reasons set alongside the condition types above.
const (
	// ReasonSourceResolved is set on SourceResolved when source.ref was
	// resolved to a commit successfully.
	ReasonSourceResolved = "Resolved"
	// ReasonSourceRefNotFound is set on SourceResolved when source.ref
	// could not be found in the repository.
	ReasonSourceRefNotFound = "RefNotFound"
	// ReasonSourceAuthFailed is set on SourceResolved when source
	// authentication (source.secretRef) failed.
	ReasonSourceAuthFailed = "AuthFailed"
	// ReasonBuilding is set on Built while the build Job is running.
	ReasonBuilding = "Building"
	// ReasonBuildSucceeded is set on Built when the most recent build
	// completed successfully.
	ReasonBuildSucceeded = "Succeeded"
	// ReasonBuildFailed is set on Built when the most recent build
	// failed.
	ReasonBuildFailed = "Failed"
	// ReasonReadyPaused is set on Ready (status False) when
	// spec.paused is true.
	ReasonReadyPaused = "Paused"
)

// AuthMode selects how triggers.http requests are authenticated.
// +kubebuilder:validation:Enum=None;Jwt
type AuthMode string

const (
	// AuthModeNone allows unauthenticated HTTP requests.
	AuthModeNone AuthMode = "None"
	// AuthModeJwt requires a valid JWT, validated via a generated
	// RequestAuthentication/AuthorizationPolicy pair.
	AuthModeJwt AuthMode = "Jwt"
)

// SourceSpec describes where a Function's source lives and how it is
// polled for changes.
type SourceSpec struct {
	// URL is the git repository containing the function source. It must
	// use the https:// or ssh:// scheme and is immutable after creation.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="source.url is immutable"
	// +kubebuilder:validation:XValidation:rule="self.matches('^(https|ssh)://')",message="source.url must be an https:// or ssh:// URL"
	URL string `json:"url"`

	// Ref is the git ref (branch, tag, or commit SHA) to build from.
	// pollInterval is ignored (no polling occurs) when ref resolves to a
	// tag or a commit SHA, since neither can produce a new commit to
	// detect.
	// +optional
	// +kubebuilder:default="main"
	Ref string `json:"ref,omitempty"`

	// Path is the directory within the repository that is the function's
	// module root, relative to the repository root. It must be a
	// relative path and must not contain ".." segments.
	// +optional
	// +kubebuilder:default="."
	// +kubebuilder:validation:XValidation:rule="!self.startsWith('/') && !self.split('/').exists(s, s == '..')",message="source.path must be a relative path with no '..' segments"
	Path string `json:"path,omitempty"`

	// SecretRef references a Secret in the same namespace holding git
	// credentials for a private repository. See IMPLEMENTERS.md for the
	// expected secret key(s); this is documented, not enforced.
	// +optional
	SecretRef *corev1.LocalObjectReference `json:"secretRef,omitempty"`

	// PollInterval controls how often `git ls-remote` is polled to detect
	// a new commit on ref. 0 disables polling; otherwise the minimum is
	// 30s. When unset, the operator-wide default applies. Any change to
	// source, ref, path, or build.* triggers an immediate rebuild
	// independent of polling.
	// +optional
	// +kubebuilder:validation:XValidation:rule="self == duration('0s') || self >= duration('30s')",message="source.pollInterval must be 0 or at least 30s"
	PollInterval *metav1.Duration `json:"pollInterval,omitempty"`
}

// BuildSpec describes how a Function's source is built into a
// container image with `ko`.
type BuildSpec struct {
	// MainPackage is the Go package to build, relative to source.path,
	// e.g. "./cmd/hello".
	// +optional
	// +kubebuilder:default="."
	MainPackage string `json:"mainPackage,omitempty"`

	// BaseImage overrides the operator-wide default base image (a
	// distroless static image) that `ko` builds on top of.
	// +optional
	BaseImage string `json:"baseImage,omitempty"`

	// Env sets additional environment variables for the build itself
	// (e.g. CGO_ENABLED, GOFLAGS) — not to be confused with
	// runtime.env, which configures the running function.
	// +optional
	Env map[string]string `json:"env,omitempty"`

	// Registry is the container registry images are pushed to. When
	// unset, the operator-wide configured external registry is used;
	// miura ships no in-chart registry and assumes pushed images are
	// public.
	// +optional
	Registry string `json:"registry,omitempty"`

	// ImageRepository is the repository path within Registry. When
	// unset it defaults to "<namespace>/<name>".
	// +optional
	ImageRepository string `json:"imageRepository,omitempty"`

	// PushSecretRef references a Secret in the same namespace holding
	// registry push credentials. When unset, the operator-wide default
	// is used. See IMPLEMENTERS.md for the expected secret key(s); this
	// is documented, not enforced.
	// +optional
	PushSecretRef *corev1.LocalObjectReference `json:"pushSecretRef,omitempty"`
}

// RuntimeProbes overrides the liveness/readiness probes on the generated
// Knative Service's container. When unset, Knative's own defaults apply.
type RuntimeProbes struct {
	// Liveness is the container liveness probe.
	// +optional
	Liveness *corev1.Probe `json:"liveness,omitempty"`

	// Readiness is the container readiness probe.
	// +optional
	Readiness *corev1.Probe `json:"readiness,omitempty"`
}

// RuntimeSpec describes how a Function's built image is run as a
// Knative Service.
// +kubebuilder:validation:XValidation:rule="!has(self.minScale) || !has(self.maxScale) || self.minScale <= self.maxScale",message="runtime.minScale must be <= runtime.maxScale when both are set"
type RuntimeSpec struct {
	// ServiceAccountName is the ServiceAccount the generated Knative
	// Service's Pods run as. When unset, the namespace default is used.
	// +optional
	ServiceAccountName string `json:"serviceAccountName,omitempty"`

	// Port is the TCP port the function listens on. It is passed to the
	// container as the $PORT environment variable (the standard Knative
	// Serving contract) and used as the container port.
	// +optional
	// +kubebuilder:default=8080
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	Port int32 `json:"port,omitempty"`

	// Env sets additional environment variables on the running function
	// container.
	// +optional
	Env []corev1.EnvVar `json:"env,omitempty"`

	// EnvFrom populates environment variables on the running function
	// container from ConfigMaps/Secrets.
	// +optional
	EnvFrom []corev1.EnvFromSource `json:"envFrom,omitempty"`

	// Resources sets compute resource requirements on the running
	// function container.
	// +optional
	Resources corev1.ResourceRequirements `json:"resources,omitempty"`

	// MinScale is the minimum number of Knative revision replicas.
	// +optional
	// +kubebuilder:default=0
	// +kubebuilder:validation:Minimum=0
	MinScale *int32 `json:"minScale,omitempty"`

	// MaxScale is the maximum number of Knative revision replicas. When
	// unset, the operator-wide default applies.
	// +optional
	// +kubebuilder:validation:Minimum=1
	MaxScale *int32 `json:"maxScale,omitempty"`

	// Concurrency is the maximum number of concurrent requests per
	// replica. When unset, Knative's own default applies.
	// +optional
	// +kubebuilder:validation:Minimum=1
	Concurrency *int32 `json:"concurrency,omitempty"`

	// Timeout is the per-request timeout. When unset, Knative's own
	// default applies.
	// +optional
	Timeout *metav1.Duration `json:"timeout,omitempty"`

	// Probes overrides the generated container's liveness/readiness
	// probes.
	// +optional
	Probes *RuntimeProbes `json:"probes,omitempty"`
}

// GatewayRef names the Istio Gateway a Function's VirtualService is
// attached to.
type GatewayRef struct {
	// Name is the Gateway's name. When unset, the operator-wide default
	// applies.
	// +optional
	Name string `json:"name,omitempty"`

	// Namespace is the Gateway's namespace. When unset, the
	// operator-wide default applies.
	// +optional
	Namespace string `json:"namespace,omitempty"`
}

// JWTAuthSpec configures JWT validation for triggers.http when
// auth.mode is Jwt.
// +kubebuilder:validation:XValidation:rule="has(self.issuer) == has(self.jwksUri)",message="jwt.issuer and jwt.jwksUri must both be set or both unset"
type JWTAuthSpec struct {
	// Audiences is the list of acceptable token audiences; at least one
	// must match.
	// +kubebuilder:validation:MinItems=1
	Audiences []string `json:"audiences"`

	// RequiredGroups lists groups read from the token's "groups" claim.
	// The token is accepted if it carries at least one of the listed
	// groups (any-of).
	// +optional
	RequiredGroups []string `json:"requiredGroups,omitempty"`

	// RequiredScopes lists scopes read from the token's "scope" claim.
	// The token is accepted only if it carries every listed scope
	// (all-of).
	// +optional
	RequiredScopes []string `json:"requiredScopes,omitempty"`

	// Issuer overrides the operator-wide default JWT issuer. Must be set
	// together with JWKSURI, or not at all.
	// +optional
	Issuer string `json:"issuer,omitempty"`

	// JWKSURI overrides the operator-wide default JWKS URI. Must be set
	// together with Issuer, or not at all.
	// +optional
	JWKSURI string `json:"jwksUri,omitempty"`
}

// AuthSpec configures authentication for triggers.http.
// +kubebuilder:validation:XValidation:rule="(self.mode == 'Jwt') == has(self.jwt)",message="auth.jwt must be set if and only if auth.mode is Jwt"
type AuthSpec struct {
	// Mode selects the authentication mode. Required whenever
	// triggers.http is set; has no default.
	Mode AuthMode `json:"mode"`

	// JWT configures JWT validation. Required when Mode is Jwt, and must
	// be unset otherwise.
	// +optional
	JWT *JWTAuthSpec `json:"jwt,omitempty"`
}

// HTTPTrigger configures HTTP ingress for a Function via a generated
// Istio VirtualService.
type HTTPTrigger struct {
	// Hostname is the DNS name routed to this function. When unset, it
	// defaults to "<name>.<operator-default-domain>".
	// +optional
	Hostname string `json:"hostname,omitempty"`

	// PathPrefix is the URL path prefix routed to this function; it is
	// passed through to the generated VirtualService unchanged (no
	// rewriting).
	// +optional
	// +kubebuilder:default="/"
	// +kubebuilder:validation:Pattern=`^/`
	PathPrefix string `json:"pathPrefix,omitempty"`

	// Gateway names the Istio Gateway routed through. When unset, the
	// operator-wide default applies.
	// +optional
	Gateway *GatewayRef `json:"gateway,omitempty"`

	// Auth configures authentication for requests arriving through this
	// trigger.
	Auth AuthSpec `json:"auth"`
}

// EventTrigger configures a Knative Trigger delivering events from a
// Broker to this Function. One Knative Trigger named
// "<name>-trigger-<hash8>" is generated per entry.
type EventTrigger struct {
	// Broker is the name of a Knative Broker in the same namespace as
	// the Function.
	Broker string `json:"broker"`

	// Filter is a CloudEvents attribute filter: every entry must match
	// exactly (no wildcards/patterns) for an event to be delivered.
	// +optional
	Filter map[string]string `json:"filter,omitempty"`
}

// ScheduleTrigger configures a Knative PingSource delivering a
// CloudEvent on a cron schedule. One Knative PingSource named
// "<name>-pingsource-<hash8>" is generated per entry, where the hash is
// derived from cron+data since entries have no name field.
type ScheduleTrigger struct {
	// Cron is the schedule, in standard cron syntax.
	Cron string `json:"cron"`

	// Data is the CloudEvent payload delivered on each tick.
	// +optional
	Data string `json:"data,omitempty"`

	// ContentType is the CloudEvent data content type.
	// +optional
	// +kubebuilder:default="application/json"
	ContentType string `json:"contentType,omitempty"`

	// Timezone is the IANA timezone the cron schedule is evaluated in.
	// When unset, the PingSource's own default applies.
	// +optional
	Timezone string `json:"timezone,omitempty"`
}

// TriggersSpec configures how traffic reaches a Function. At least one
// of HTTP, Events, or Schedules must be set.
// +kubebuilder:validation:XValidation:rule="has(self.http) || size(self.events) > 0 || size(self.schedules) > 0",message="at least one of triggers.http, triggers.events, triggers.schedules must be set"
type TriggersSpec struct {
	// HTTP configures HTTP ingress. When unset, the generated Knative
	// Service is cluster-local and no VirtualService is created.
	// +optional
	HTTP *HTTPTrigger `json:"http,omitempty"`

	// Events configures Knative Triggers consuming from Brokers.
	// +optional
	Events []EventTrigger `json:"events,omitempty"`

	// Schedules configures Knative PingSources delivering events on a
	// cron schedule.
	// +optional
	// +listType=atomic
	Schedules []ScheduleTrigger `json:"schedules,omitempty"`
}

// FunctionSpec defines the desired state of a Function: where its
// source lives, how it is built, how it runs, and how traffic reaches
// it.
type FunctionSpec struct {
	// Paused stops polling for new commits and stops starting new
	// builds. It does not affect the currently running Knative Service
	// or its routes, which continue serving the last successful build
	// unchanged.
	// +optional
	// +kubebuilder:default=false
	Paused bool `json:"paused,omitempty"`

	// Source describes where the function's code lives.
	Source SourceSpec `json:"source"`

	// Build describes how the function is built into an image.
	// +optional
	Build BuildSpec `json:"build,omitempty"`

	// Runtime describes how the built image is run.
	// +optional
	Runtime RuntimeSpec `json:"runtime,omitempty"`

	// Triggers describes how traffic reaches the function.
	Triggers TriggersSpec `json:"triggers"`
}

// FunctionSourceStatus reports what source commit is currently built
// and when it was last polled.
type FunctionSourceStatus struct {
	// ResolvedCommit is the commit SHA last resolved from spec.source.ref.
	// +optional
	ResolvedCommit string `json:"resolvedCommit,omitempty"`

	// LastPolledTime is the last time `git ls-remote` was polled.
	// +optional
	LastPolledTime *metav1.Time `json:"lastPolledTime,omitempty"`
}

// FunctionBuildStatus records one entry in a Function's build history.
type FunctionBuildStatus struct {
	// Commit is the source commit that was built.
	Commit string `json:"commit,omitempty"`

	// Image is the resulting image reference, including digest.
	// +optional
	Image string `json:"image,omitempty"`

	// StartTime is when the build Job started.
	// +optional
	StartTime *metav1.Time `json:"startTime,omitempty"`

	// CompletionTime is when the build Job finished.
	// +optional
	CompletionTime *metav1.Time `json:"completionTime,omitempty"`

	// Result is the build outcome, e.g. "Succeeded" or "Failed".
	// +optional
	Result string `json:"result,omitempty"`

	// JobName is the name of the backing build Job. The build Job is
	// cleaned up automatically via ttlSecondsAfterFinished; JobName may
	// therefore reference a Job that no longer exists.
	// +optional
	JobName string `json:"jobName,omitempty"`
}

// FunctionStatus defines the observed state of a Function.
//
// A failed build leaves the previously successful revision serving
// unchanged — status.image only ever reflects a successful build.
// Status never echoes auth configuration (audiences, groups, scopes,
// issuer, JWKS URI); that information lives only in spec.
type FunctionStatus struct {
	// ObservedGeneration is the generation most recently observed by the
	// controller.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Conditions follows the standard Kubernetes condition shape. See
	// the Condition* constants in this package for the types and
	// reasons this operator sets.
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// Source reports the currently resolved source commit and polling
	// time.
	// +optional
	Source FunctionSourceStatus `json:"source,omitempty"`

	// Image is the built image reference (including digest) currently
	// deployed.
	// +optional
	Image string `json:"image,omitempty"`

	// URL is the externally reachable URL, set only when
	// spec.triggers.http is configured.
	// +optional
	URL string `json:"url,omitempty"`

	// Builds is recent build history, capped at an operator-wide default
	// number of entries.
	// +optional
	Builds []FunctionBuildStatus `json:"builds,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName=fn
// +kubebuilder:printcolumn:name="Ready",type="string",JSONPath=".status.conditions[?(@.type=='Ready')].status"
// +kubebuilder:printcolumn:name="Image",type="string",JSONPath=".status.image"
// +kubebuilder:printcolumn:name="URL",type="string",JSONPath=".status.url"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
// +kubebuilder:validation:XValidation:rule="size(self.metadata.name) <= 40",message="metadata.name must be at most 40 characters"

// Function is the Schema for the functions API. It describes a single
// Knative function: where its source lives, how to build it, how it
// runs, and how traffic (HTTP, events, schedules) reaches it.
type Function struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   FunctionSpec   `json:"spec,omitempty"`
	Status FunctionStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// FunctionList contains a list of Function.
type FunctionList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Function `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Function{}, &FunctionList{})
}
