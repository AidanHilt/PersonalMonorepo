{{- define "common.generateEnabledValues" -}}
{{- $passThroughKeys := .passThroughKeys -}}
{{- $values := .Values | toJson | fromJson -}}
{{- range $key, $value := $values }}
{{- if has $key $passThroughKeys }}
{{ $key }}:
{{ toYaml $value | indent 2 }}
{{- else if and (kindIs "map" $value) (hasKey $value "destinationNamespace") }}
  {{- $enabled := get $value "enabled" | default false -}}
  {{- $groupEnabled := false -}}
  {{- if hasKey $value "groupName" -}}
    {{- $groupName := get $value "groupName" -}}
    {{- $group := get ($values | toJson | fromJson) $groupName -}}
    {{- if $group -}}
      {{- if get $group "enabled" -}}
        {{- $groupEnabled = true -}}
      {{- else -}}
        {{- $groupApp := get $group $key -}}
        {{- $checkApp := $groupApp | default dict }}
        {{- if get $checkApp "enabled" -}}
          {{- $groupEnabled = true -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if or $enabled $groupEnabled }}
{{ $key }}:
  enabled: {{ or $enabled $groupEnabled }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  Check if an app is enabled.
  Returns true if:
    1. app.groupName is not set AND app.enabled is true
    2. app.groupName is set AND (app.enabled OR .Values.<groupName>.enabled) is true
  Otherwise returns false.

  Usage: {{- if include "common.isAppEnabled" (dict "app" $app "Values" $.Values) }}
*/}}
{{- define "common.isAppEnabled" -}}
{{- $app := .app -}}
{{- $values := .Values | toJson | fromJson -}}
{{- if hasKey $app "groupName" -}}
  {{- $group := get $values $app.groupName -}}
  {{- if or (get $app "enabled") (and $group (get $group "enabled")) -}}
    {{- true -}}
  {{- end -}}
{{- else -}}
  {{- if get $app "enabled" -}}
    {{- true -}}
  {{- end -}}
{{- end -}}
{{- end -}}