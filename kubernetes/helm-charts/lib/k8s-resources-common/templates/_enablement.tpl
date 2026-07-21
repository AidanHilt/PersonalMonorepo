{{/*
  Check if an app is enabled.
  Returns true if:
    1. app.groupName is not set AND app.enabled is true
    2. app.groupName is set AND (app.enabled OR .Values.<groupName>.enabled) is true
  Otherwise returns false.

  Usage: {{- if include "common.isAppEnabled" (dict "app" $app "Values" $.Values) }}
*/}}
{{- define "common.isItemEnabled" -}}
{{- $item := .item -}}
{{- $values := .Values | toJson | fromJson -}}
{{- if hasKey $item "groupName" -}}
  {{- $group := get $values $item.groupName -}}
  {{- if or (get $item "enabled") (and $group (get $group "enabled")) -}}
    {{- true -}}
  {{- end -}}
{{- else -}}
  {{- if get $item "enabled" -}}
    {{- true -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
common.mergeGroupOverrides
----------------------------
Merges group-level override values into an application's own values, if the
app declares a "groupName". Overrides are looked up by exact app name first,
falling back to a "default" entry within that group if no app-specific
override exists.

Parameters (passed in as a dict via "item"):
  item    (dict, required)        - The item's own values/definition.
                                    May optionally contain a "groupName" key.
  itemName  (string, required)    - The key/name of this item, used to look
                                      up an app-specific override within its group.


Behavior:
  - If item has no "groupName" key, item is returned unchanged.
  - If item.groupName is set, looks up .Values[groupName].
      - If that group has a key matching itemName, those values are
        merged on top of item (overwriting matching keys).
      - Else if that group has a "default" key, those values are merged
        on top of item instead.
      - If neither exists, item.app is returned unchanged.

Returns:
  YAML-encoded $appDetails. Decode with `fromYaml` at the call site.

Usage:
  {{- $appDetails := include "common.mergeGroupOverrides" (dict "item" (dict "app" $app "appName" $appName)) | fromYaml }}
*/}}
{{- define "common.mergeGroupOverrides" -}}
{{- $item := .item -}}
{{- $itemName := .itemName }}
{{- $itemDetails := $item -}}
{{- if hasKey $item "groupName" -}}
  {{- $group := index ($.Values | toJson | fromJson) $item.groupName -}}
  {{- $groupOverrides := dict -}}
  {{- if and $group (index $group $itemName) -}}
    {{- $groupOverrides = index $group $itemName -}}
  {{- else if and $group (index $group "default") -}}
    {{- $groupOverrides = index $group "default" -}}
  {{- end -}}
  {{- $itemDetails = mergeOverwrite $groupOverrides $item -}}
{{- end -}}
{{- $itemDetails | toYaml -}}
{{- end -}}