package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// GitFunctionSpec defines the desired state of GitFunction.
type GitFunctionSpec struct {
	// RepoURL is the git repository containing the function source.
	RepoURL string `json:"repoURL"`

	// Ref is the git ref (branch, tag, or commit) to build from.
	// +optional
	// +kubebuilder:default="main"
	Ref string `json:"ref,omitempty"`
}

// GitFunctionStatus defines the observed state of GitFunction.
type GitFunctionStatus struct {
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName=gfn

// GitFunction is the Schema for the gitfunctions API.
type GitFunction struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   GitFunctionSpec   `json:"spec,omitempty"`
	Status GitFunctionStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// GitFunctionList contains a list of GitFunction.
type GitFunctionList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []GitFunction `json:"items"`
}

func init() {
	SchemeBuilder.Register(&GitFunction{}, &GitFunctionList{})
}
