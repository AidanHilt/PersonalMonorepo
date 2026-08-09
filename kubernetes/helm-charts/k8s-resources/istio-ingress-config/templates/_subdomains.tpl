{{/*
Returns a JSON array of unique subdomain prefixes gathered from every top-level
values entry that defines a "subdomain" key. e.g. ["bento", "grafana"]
*/}}
{{- define "istio-ingress-config.subdomains" -}}
{{- $values := . -}}
{{- $result := list -}}
{{- range $appName, $app := $values }}
  {{- if and (kindIs "map" $app) (hasKey $app "subdomain") }}
    {{- $result = append $result $app.subdomain }}
  {{- end }}
{{- end }}
{{- $result | uniq | toJson -}}
{{- end -}}