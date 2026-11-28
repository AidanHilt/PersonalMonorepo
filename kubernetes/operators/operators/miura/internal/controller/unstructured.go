package controller

import "encoding/json"

// toJSONValue round-trips v through JSON to produce a plain
// map[string]interface{}/[]interface{}/scalar tree suitable for
// embedding directly into an unstructured.Unstructured object's Object
// map. This is how serving.go embeds typed corev1 fields (env, envFrom,
// resources, probes) into the unstructured Knative Service this operator
// manages, without taking on a knative.dev/serving client dependency
// (see IMPLEMENTERS.md's style guide: "No typed knative/istio client
// imports").
func toJSONValue(v interface{}) (interface{}, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	var out interface{}
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}
