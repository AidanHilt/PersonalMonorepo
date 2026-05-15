{{- define "generateEnabledValues" -}}
{{- range $key, $value := .Values }}
{{- $excludedNames := (list "env" "hostnames" "defaultGitRepo" "gitRevision" "configuration")}}
{{- if eq $key "hostnames" }}
{{ $key }}:
{{ toYaml $value | indent 2 }}
{{- else if not (has $key $excludedNames) }}
{{ $key }}:
  enabled: {{ if hasKey $value "enabled" }}{{ $value.enabled }}{{ else }}false{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  Check if an app's groupName parent is enabled.
  Returns true if:
    - $app has no groupName key (not part of a group), OR
    - .Values.<groupName>.enabled is true

  Usage: {{- if include "common.isGroupEnabled" (dict "app" $app "Values" .Values) }}
*/}}
{{- define "common.isGroupEnabled" -}}
{{- $app := .app -}}
{{- $values := .Values -}}
{{- if hasKey $app "groupName" -}}
  {{- $group := get $values $app.groupName -}}
  {{- if and $group (get $group "enabled") -}}
    {{- true -}}
  {{- end -}}
{{- else -}}
  {{- true -}}
{{- end -}}
{{- end -}}