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