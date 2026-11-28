#!/bin/bash
# Harness for agent-plan-classify + agent-format, run as the flake check
# "<name>-test" (see mkTest in nix/scripts/flake.nix). The builder inlines
# both libs above this text via #include, so these scenarios exercise exactly
# the code agent-validate builds and runs.
#
# Nothing here invokes Nix, Git, agent-validate, or a project formatter or
# linter: every fixture is a throwaway tree created below and every check
# only calls the classification/emission functions. Classification globals
# (BASH_FILES, YAML_FILES, AFFECTED_FLAKE_DIRS, ...) are shared, so each
# scenario resets them first; assertion helpers always return 0 and only
# count failures, so one broken expectation cannot hide the rest under the
# builder's errexit.

#include agent-plan-classify
#include agent-format

failures=0

# --- assertion helpers -----------------------------------------------------

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

reset_state() {
  BASH_FILES=()
  GO_MODULE_DIRS=()
  YAML_FILES=()
  HELM_TEMPLATE_FILES=()
  HELM_CHART_DIRS=()
  NIX_FILES=()
  TF_DIRS=()
  DOCKERFILES=()
  AFFECTED_FLAKE_DIRS=()
  FLAKE_CHECK_DIRS=()
  # Only ever written by the lib (callers read it), so shellcheck would see
  # this reset as the array's only appearance.
  #shellcheck disable=SC2034
  UNKNOWN_PATHS=()
  NIX_SYSTEM=""
}

describe_array() {
  local -n _describe_arr="$1"
  local x out=""
  for x in "${_describe_arr[@]+"${_describe_arr[@]}"}"; do
    out+="$(printf '%q' "$x") "
  done
  printf '[%s]' "${out% }"
}

assert_contains() {
  # assert_contains <array-name> <expected> <label>
  local -n _contains_arr="$1"
  local needle="$2" label="$3" x
  for x in "${_contains_arr[@]+"${_contains_arr[@]}"}"; do
    if [[ "$x" == "$needle" ]]; then
      return 0
    fi
  done
  fail "$label: expected $(printf '%q' "$needle") in $1 = $(describe_array "$1")"
  return 0
}

assert_not_contains() {
  local -n _not_contains_arr="$1"
  local needle="$2" label="$3" x
  for x in "${_not_contains_arr[@]+"${_not_contains_arr[@]}"}"; do
    if [[ "$x" == "$needle" ]]; then
      fail "$label: did not expect $(printf '%q' "$needle") in $1 = $(describe_array "$1")"
      return 0
    fi
  done
  return 0
}

assert_empty() {
  local -n _empty_arr="$1"
  local label="$2"
  if [[ ${#_empty_arr[@]} -ne 0 ]]; then
    fail "$label: expected no entries in $1, got $(describe_array "$1")"
  fi
  return 0
}

assert_count() {
  local -n _count_arr="$1"
  local expected="$2" label="$3"
  if [[ ${#_count_arr[@]} -ne $expected ]]; then
    fail "$label: expected $expected entries in $1, got ${#_count_arr[@]}: $(describe_array "$1")"
  fi
  return 0
}

assert_output_contains() {
  local out="$1" needle="$2" label="$3"
  if [[ "$out" != *"$needle"* ]]; then
    fail "$label: expected emitted output to contain '$needle'; got:"
    printf '%s\n' "$out" >&2
  fi
  return 0
}

assert_output_not_contains() {
  local out="$1" needle="$2" label="$3"
  if [[ "$out" == *"$needle"* ]]; then
    fail "$label: emitted output must not contain '$needle'; got:"
    printf '%s\n' "$out" >&2
  fi
  return 0
}

line_with() {
  # Prints the first line of <output> containing <marker>, if any.
  local out="$1" marker="$2" line
  while IFS= read -r line; do
    if [[ "$line" == *"$marker"* ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<<"$out"
  return 0
}

assert_tool_required() {
  local tool_list="$1" tool="$2" label="$3"
  if ! printf '%s\n' "$tool_list" | grep -qx -- "$tool"; then
    fail "$label: expected required tool '$tool'; got:"
    printf '%s\n' "$tool_list" >&2
  fi
  return 0
}

assert_tool_not_required() {
  local tool_list="$1" tool="$2" label="$3"
  if printf '%s\n' "$tool_list" | grep -qx -- "$tool"; then
    fail "$label: tool '$tool' should not be required; got:"
    printf '%s\n' "$tool_list" >&2
  fi
  return 0
}

# --- fixtures -------------------------------------------------------------
#
# $ROOT is the repo root for every classification below. It deliberately has
# no flake.nix, so $PLAIN is a non-flake area while $FLAKED has its own flake
# root (plus a nested one holding only docs).
ROOT="$(realpath -m -- "$(mktemp -d)")"
PLAIN="$ROOT/plain"
FLAKED="$ROOT/flaked"
# A filename with an embedded newline: classification must carry it through
# unsplit, so it is kept in a variable rather than written inline.
NEWLINE_YAML_NAME=$'line\nbreak.yaml'

cleanup() {
  rm -rf "$ROOT"
}
trap cleanup EXIT

# mkfile <path>: create an empty file and its parents. Only names and
# extensions matter to classification (the extensionless shebang sniff is not
# exercised here).
mkfile() {
  mkdir -p "$(dirname "$1")"
  : >"$1"
}

# A chart: Chart.yaml, values, crds/ and templates/ sources.
mkfile "$PLAIN/chart/Chart.yaml"
mkfile "$PLAIN/chart/values.yaml"
mkfile "$PLAIN/chart/crds/crd.yaml"
mkfile "$PLAIN/chart/templates/deploy.yaml"
mkfile "$PLAIN/chart/templates/service.yml"
mkfile "$PLAIN/chart/templates/_helpers.tpl"
mkfile "$PLAIN/chart/templates/NOTES.gotmpl"
# A chart-root .gotmpl doc: not below templates/, so not a template source.
mkfile "$PLAIN/chart/docs/example.gotmpl"

# Non-flake shells and Nix files.
mkfile "$PLAIN/script.sh"
mkfile "$PLAIN/tool.nix"

# Filenames with a space and with a newline.
mkfile "$PLAIN/spaces/with space.yaml"
mkfile "$PLAIN/spaces/$NEWLINE_YAML_NAME"

# Flake-owned area, including a nested flake root that holds only docs.
mkfile "$FLAKED/flake.nix"
mkfile "$FLAKED/script.sh"
mkfile "$FLAKED/README.md"
mkfile "$FLAKED/nested/flake.nix"
mkfile "$FLAKED/nested/notes.md"

# --- scenarios ------------------------------------------------------------

# Chart layout: Chart.yaml/values/crds are plain YAML, only *.yaml/*.yml/
# *.tpl/*.gotmpl below templates/ are Helm template sources, chart-root docs
# are ignored by traversal, yamlfmt and helmfmt each get their own set, and a
# non-flake chart keeps its legacy lint/build checks.
scenario_chart_profiles() {
  reset_state

  local chart="$PLAIN/chart"
  classify_paths "$ROOT" "$chart"

  assert_contains YAML_FILES "$chart/Chart.yaml" "chart: Chart.yaml is plain YAML"
  assert_contains YAML_FILES "$chart/values.yaml" "chart: values.yaml is plain YAML"
  assert_contains YAML_FILES "$chart/crds/crd.yaml" "chart: crds/ is plain YAML"
  assert_count HELM_CHART_DIRS 1 "chart: every chart path records the same chart root once"
  assert_contains HELM_CHART_DIRS "$chart" "chart: the chart root is recorded"

  local tpl
  for tpl in deploy.yaml service.yml _helpers.tpl NOTES.gotmpl; do
    assert_contains HELM_TEMPLATE_FILES "$chart/templates/$tpl" "chart: templates/$tpl is a Helm template source"
    assert_not_contains YAML_FILES "$chart/templates/$tpl" "chart: templates/$tpl must stay out of YAML_FILES"
  done

  assert_not_contains HELM_TEMPLATE_FILES "$chart/docs/example.gotmpl" "chart: chart-root docs/*.gotmpl is not a template source"
  assert_not_contains YAML_FILES "$chart/docs/example.gotmpl" "chart: chart-root docs/*.gotmpl is not plain YAML"
  assert_not_contains UNKNOWN_PATHS "$chart/docs/example.gotmpl" "chart: directory traversal must not report docs/*.gotmpl as unknown"

  local fmt yaml_line helm_line
  fmt="$(agent_format_emit_phase)"
  yaml_line="$(line_with "$fmt" 'run_check FORMAT "yamlfmt"')"
  helm_line="$(line_with "$fmt" 'run_check FORMAT "helmfmt"')"
  assert_output_contains "$yaml_line" "$chart/Chart.yaml" "format: yamlfmt gets Chart.yaml"
  assert_output_contains "$yaml_line" "$chart/values.yaml" "format: yamlfmt gets values.yaml"
  assert_output_contains "$yaml_line" "$chart/crds/crd.yaml" "format: yamlfmt gets crds/"
  assert_output_not_contains "$yaml_line" "$chart/templates/" "format: yamlfmt must never see chart templates"
  assert_output_contains "$helm_line" "--files" "format: helmfmt is invoked with --files"
  assert_output_contains "$helm_line" "$chart/templates/deploy.yaml" "format: helmfmt gets templates/*.yaml"
  assert_output_contains "$helm_line" "$chart/templates/service.yml" "format: helmfmt gets templates/*.yml"
  assert_output_contains "$helm_line" "$chart/templates/_helpers.tpl" "format: helmfmt gets templates/*.tpl"
  assert_output_contains "$helm_line" "$chart/templates/NOTES.gotmpl" "format: helmfmt gets templates/*.gotmpl"
  assert_output_not_contains "$helm_line" "$chart/Chart.yaml" "format: helmfmt must not get Chart.yaml"
  assert_output_not_contains "$helm_line" "$chart/values.yaml" "format: helmfmt must not get values.yaml"

  local lint build
  lint="$(emit_lint_phase)"
  build="$(emit_build_test_phase)"
  assert_output_contains "$lint" 'run_check LINT "yamllint"' "lint: a non-flake chart keeps legacy yamllint"
  assert_output_contains "$lint" "helm lint" "lint: a non-flake chart keeps legacy helm lint"
  assert_output_contains "$build" "helm template|kubeconform" "build: a non-flake chart keeps legacy helm template|kubeconform"
}

# Filenames with spaces and newlines survive classification unsplit.
scenario_array_safety() {
  reset_state

  local spaces="$PLAIN/spaces"
  classify_paths "$ROOT" "$spaces"

  assert_count YAML_FILES 2 "spaces: only the two fixture YAML files are classified"
  assert_contains YAML_FILES "$spaces/with space.yaml" "spaces: a filename with a space survives unsplit"
  assert_contains YAML_FILES "$spaces/$NEWLINE_YAML_NAME" "spaces: a filename with a newline survives NUL-safe traversal"
}

# A docs-only change still registers its enclosing flake and is reported as
# unknown, but emits no legacy checks.
scenario_file_docs_flake_ownership() {
  reset_state

  local doc="$FLAKED/README.md"
  classify_paths "$ROOT" "$doc"

  assert_contains AFFECTED_FLAKE_DIRS "$FLAKED" "docs: a changed README still makes its flake affected"
  assert_contains UNKNOWN_PATHS "$doc" "docs: an unrecognized file is reported as unknown"

  if ! any_checks_emitted; then
    fail "docs: a flake-owned docs-only change must still count as checkable"
  fi

  local lint
  lint="$(emit_lint_phase)"
  if [[ -n "$lint" ]]; then
    fail "docs: a flake-owned docs-only change must emit no legacy LINT, got: $lint"
  fi
}

# An explicit directory override discovers every nested flake root, including
# one holding only docs, without inventing UNKNOWN_PATHS entries.
scenario_directory_override_flakes() {
  reset_state

  classify_paths "$ROOT" "$FLAKED"

  assert_contains AFFECTED_FLAKE_DIRS "$FLAKED" "override: the override directory's own flake is affected"
  assert_contains AFFECTED_FLAKE_DIRS "$FLAKED/nested" "override: a nested flake root is discovered even though it holds only docs"
  assert_empty UNKNOWN_PATHS "override: flake discovery must not report unknown paths of its own"
  assert_contains NIX_FILES "$FLAKED/flake.nix" "override: flake.nix itself is classified"
  assert_contains NIX_FILES "$FLAKED/nested/flake.nix" "override: the nested flake.nix is classified"
  assert_contains BASH_FILES "$FLAKED/script.sh" "override: the flake-owned script is classified"
}

# FORMAT is never suppressed, while legacy LINT/BUILD_TEST only cover the
# non-flake paths.
scenario_format_and_legacy_split() {
  reset_state

  classify_paths "$ROOT" "$FLAKED" "$PLAIN/script.sh" "$PLAIN/tool.nix"

  local fmt lint build
  fmt="$(agent_format_emit_phase)"
  lint="$(emit_lint_phase)"
  build="$(emit_build_test_phase)"

  assert_output_contains "$fmt" 'run_check FORMAT "shfmt" shfmt -i 2 -w' "split: shfmt still runs"
  assert_output_contains "$fmt" "$FLAKED/script.sh" "split: a flake-owned shell file keeps shfmt"
  assert_output_contains "$fmt" "$PLAIN/script.sh" "split: a non-flake shell file keeps shfmt"
  assert_output_contains "$fmt" 'run_check FORMAT "nixfmt" nixfmt' "split: nixfmt still runs"
  assert_output_contains "$fmt" "$FLAKED/flake.nix" "split: a flake-owned flake.nix keeps nixfmt"
  assert_output_contains "$fmt" "$PLAIN/tool.nix" "split: a non-flake .nix file keeps nixfmt"

  assert_output_contains "$lint" 'run_check LINT "shellcheck"' "split: a non-flake shell file keeps legacy shellcheck"
  assert_output_contains "$lint" "$PLAIN/script.sh" "split: legacy shellcheck covers the non-flake script"
  assert_output_not_contains "$lint" "$FLAKED/script.sh" "split: a flake-owned shell file must not reach legacy shellcheck/bash -n"
  assert_output_contains "$lint" "statix check" "split: a non-flake .nix file keeps legacy statix"
  assert_output_contains "$lint" "$PLAIN/tool.nix" "split: legacy statix covers the non-flake .nix file"
  assert_output_not_contains "$lint" "$FLAKED/flake.nix" "split: a flake-owned flake.nix must not reach legacy statix"
  assert_output_not_contains "$lint" "$FLAKED/nested/flake.nix" "split: a nested flake-owned flake.nix must not reach legacy statix"

  if [[ -n "$build" ]]; then
    fail "split: BUILD_TEST should be empty for this classification, got: $build"
  fi
}

# Required tools: formatters always, nix for every affected flake, legacy
# tools only for paths that will actually reach them.
scenario_tools_non_flake() {
  reset_state

  classify_paths "$ROOT" "$PLAIN/chart"

  local tool_list
  tool_list="$(required_tools_for_profiles)"
  assert_tool_required "$tool_list" yamlfmt "tools: yamlfmt for plain YAML"
  assert_tool_required "$tool_list" helmfmt "tools: helmfmt for chart templates"
  assert_tool_required "$tool_list" yamllint "tools: yamllint for non-flake plain YAML"
  assert_tool_required "$tool_list" helm "tools: helm for a non-flake chart"
  assert_tool_required "$tool_list" kubeconform "tools: kubeconform for a non-flake chart"
  assert_tool_not_required "$tool_list" nix "tools: no affected flake, so no nix"
  assert_tool_not_required "$tool_list" nixfmt "tools: no .nix files, so no nixfmt"
  assert_tool_not_required "$tool_list" shellcheck "tools: no shell files, so no legacy shellcheck"
}

scenario_tools_flake_owned() {
  reset_state

  classify_paths "$ROOT" "$FLAKED"

  local tool_list
  tool_list="$(required_tools_for_profiles)"
  assert_tool_required "$tool_list" shfmt "tools: formatters still run for flake-owned shell files"
  assert_tool_required "$tool_list" nixfmt "tools: formatters still run for flake-owned .nix files"
  assert_tool_required "$tool_list" nix "tools: every affected flake requires nix"
  assert_tool_not_required "$tool_list" shellcheck "tools: flake-owned files never require legacy shellcheck"
  assert_tool_not_required "$tool_list" statix "tools: flake-owned files never require legacy statix"
  assert_tool_not_required "$tool_list" yamllint "tools: no plain YAML, so no yamllint"
}

scenario_tools_mixed() {
  reset_state

  classify_paths "$ROOT" "$FLAKED" "$PLAIN/script.sh"

  local tool_list
  tool_list="$(required_tools_for_profiles)"
  assert_tool_required "$tool_list" shfmt "tools: shfmt for the changed shell files"
  assert_tool_required "$tool_list" nixfmt "tools: nixfmt for the changed .nix files"
  assert_tool_required "$tool_list" nix "tools: nix for the affected flake"
  assert_tool_required "$tool_list" shellcheck "tools: legacy shellcheck for the non-flake script"
  assert_tool_required "$tool_list" bash "tools: bash -n is paired with legacy shellcheck"
  assert_tool_not_required "$tool_list" statix "tools: every .nix file here is flake-owned, so no statix"
}

# The aggregate build command: one per affected flake with a contract, with an
# explicit ./ so Nix reads a relative path as a local flake.
scenario_flake_build_phase() {
  reset_state

  NIX_SYSTEM="x86_64-linux"
  FLAKE_CHECK_DIRS=("nix/scripts" "$FLAKED")

  local out
  out="$(emit_flake_build_phase)"
  assert_output_contains "$out" \
    "nix build ./nix/scripts#checks.x86_64-linux.agent-validate" \
    "aggregate: a relative flake dir gets an explicit ./ prefix"
  assert_output_contains "$out" \
    "nix build $FLAKED#checks.x86_64-linux.agent-validate" \
    "aggregate: an absolute flake dir stays absolute"

  reset_state
  out="$(emit_flake_build_phase)"
  if [[ -n "$out" ]]; then
    fail "aggregate: no FLAKE_CHECK_DIRS must emit no aggregate build, got: $out"
  fi
}

scenario_chart_profiles
scenario_array_safety
scenario_file_docs_flake_ownership
scenario_directory_override_flakes
scenario_format_and_legacy_split
scenario_tools_non_flake
scenario_tools_flake_owned
scenario_tools_mixed
scenario_flake_build_phase

if [[ "$failures" -ne 0 ]]; then
  printf '%s assertion(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'agent-plan-classify: all assertions passed\n'
