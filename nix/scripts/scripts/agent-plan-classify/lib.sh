#!/bin/bash
# Shared path-classification + check-emission logic for agent-plan-create
# (pre-dispatch required-tools check) and agent-validate (actual runtime
# check execution). Classifies a list of files/directories into file-type
# "profiles" (bash, go, yaml/helm, nix, terraform, dockerfiles), derives
# the tools each profile needs, and emits the concrete per-profile
# FORMAT/LINT/BUILD_TEST commands as `run_check PHASE "name" cmd...` lines
# of shell text that a caller defining `run_check` can `eval`.
#
# Usage (from a run.sh that also declares "# @lib: agent-plan-classify" and
# "# @lib: printing-and-output"):
#
#   classify_paths "$raw_paths" "$repo_root"
#   relativize_paths "$repo_root"
#   mapfile -t tools_list < <(required_tools_for_profiles)
#   eval "$(emit_format_phase)"
#   eval "$(emit_lint_phase)"
#   eval "$(emit_build_test_phase)"
#
# This file never calls "exit" -- callers decide what a classification
# failure (e.g. an unknown path) means for them.

BASH_FILES=()
GO_MODULE_DIRS=()
YAML_FILES=()
HELM_CHART_DIRS=()
NIX_FILES=()
NIX_FLAKE_DIRS=()
TF_DIRS=()
DOCKERFILES=()

#shellcheck disable=SC2329
array_contains() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

#shellcheck disable=SC2329
add_unique() {
  # add_unique <array-name> <value>
  local -n arr="$1"
  local val="$2"
  array_contains "$val" "${arr[@]+"${arr[@]}"}" || arr+=("$val")
}

# Walks up from a starting path looking for a `.git` entry (directory or,
# for worktrees, a file). Prints the repo root and returns 0 on success;
# returns 1 if none was found by the time it reaches `/`.
#shellcheck disable=SC2329
find_repo_root() {
  local dir="$1"
  while :; do
    if [[ -e "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    if [[ "$dir" == "/" ]]; then
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

# Resolves $1 to an absolute path even if it doesn't exist yet (realpath -m
# resolves the deepest existing ancestor and appends the rest literally).
#shellcheck disable=SC2329
resolve_path() {
  realpath -m -- "$1"
}

# Walks upward from a starting directory looking for a marker file
# (go.mod / flake.nix), bounded at the repo root. Prints the directory
# containing the marker, or nothing if not found.
#shellcheck disable=SC2329
walk_up_for_marker() {
  local dir="$1" marker="$2" repo_root="$3"
  while :; do
    if [[ -e "$dir/$marker" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    if [[ "$dir" == "$repo_root" || "$dir" == "/" ]]; then
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

#shellcheck disable=SC2329
classify_file() {
  local f="$1" repo_root="$2"
  local base dir
  base="$(basename "$f")"
  dir="$(dirname "$f")"

  case "$base" in
  *.sh)
    add_unique BASH_FILES "$f"
    return
    ;;
  *.go)
    local mod_dir
    if mod_dir="$(walk_up_for_marker "$dir" "go.mod" "$repo_root")"; then
      add_unique GO_MODULE_DIRS "$mod_dir"
    else
      add_unique UNKNOWN_PATHS "$f (no go.mod found)"
    fi
    return
    ;;
  Chart.yaml)
    add_unique HELM_CHART_DIRS "$dir"
    return
    ;;
  *.yaml | *.yml)
    add_unique YAML_FILES "$f"
    local chart_dir
    if chart_dir="$(walk_up_for_marker "$dir" "Chart.yaml" "$repo_root")"; then
      add_unique HELM_CHART_DIRS "$chart_dir"
    fi
    return
    ;;
  *.nix)
    add_unique NIX_FILES "$f"
    local flake_dir
    if flake_dir="$(walk_up_for_marker "$dir" "flake.nix" "$repo_root")"; then
      add_unique NIX_FLAKE_DIRS "$flake_dir"
    fi
    return
    ;;
  *.tf)
    add_unique TF_DIRS "$dir"
    return
    ;;
  Dockerfile | Dockerfile.* | *.dockerfile)
    add_unique DOCKERFILES "$f"
    return
    ;;
  *)
    # Fall back to shebang sniffing for extensionless scripts.
    if [[ -f "$f" ]] && head -c 64 -- "$f" 2>/dev/null | head -1 | grep -qE '^#!.*\b(bash|sh)\b'; then
      add_unique BASH_FILES "$f"
    else
      add_unique UNKNOWN_PATHS "$f"
    fi
    return
    ;;
  esac
}

#shellcheck disable=SC2329
classify_dir() {
  local d="$1" repo_root="$2"
  local f
  while IFS= read -r -d '' f; do
    classify_file "$f" "$repo_root"
  done < <(find "$d" -type f \( \
    -name '*.sh' -o -name '*.go' -o -name '*.yaml' -o -name '*.yml' \
    -o -name 'Chart.yaml' -o -name '*.nix' -o -name '*.tf' \
    -o -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.dockerfile' \
    \) -print0)
}

#shellcheck disable=SC2329
classify_paths() {
  local raw="$1" repo_root="$2"
  local normalized p
  # Commas and whitespace are both accepted as separators.
  normalized="${raw//,/ }"
  for p in $normalized; do
    [[ -z "$p" ]] && continue
    local resolved
    resolved="$(resolve_path "$p")"
    if [[ -f "$resolved" ]]; then
      classify_file "$resolved" "$repo_root"
    elif [[ -d "$resolved" ]]; then
      classify_dir "$resolved" "$repo_root"
    else
      add_unique UNKNOWN_PATHS "$p (not found on disk)"
    fi
  done
}

#shellcheck disable=SC2329
relativize_array() {
  local -n _rel_arr="$1"
  local repo_root="$2" i
  for i in "${!_rel_arr[@]}"; do
    _rel_arr[i]="$(realpath -m --relative-to="$repo_root" -- "${_rel_arr[i]}")"
  done
}

#shellcheck disable=SC2329
relativize_paths() {
  local repo_root="$1" name
  for name in BASH_FILES GO_MODULE_DIRS YAML_FILES HELM_CHART_DIRS NIX_FILES NIX_FLAKE_DIRS TF_DIRS DOCKERFILES; do
    relativize_array "$name" "$repo_root"
  done
}

# --- required tool computation ---------------------------------------------

#shellcheck disable=SC2329
required_tools_for_profiles() {
  local tools=()
  [[ ${#BASH_FILES[@]} -gt 0 ]] && tools+=(shfmt shellcheck bash)
  [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]] && tools+=(go)
  [[ ${#YAML_FILES[@]} -gt 0 || ${#HELM_CHART_DIRS[@]} -gt 0 ]] && tools+=(yamllint)
  [[ ${#HELM_CHART_DIRS[@]} -gt 0 ]] && tools+=(helm kubeconform)
  [[ ${#NIX_FILES[@]} -gt 0 ]] && tools+=(nixfmt statix)
  [[ ${#NIX_FLAKE_DIRS[@]} -gt 0 ]] && tools+=(nix)
  [[ ${#TF_DIRS[@]} -gt 0 ]] && tools+=(terraform)
  [[ ${#DOCKERFILES[@]} -gt 0 ]] && tools+=(hadolint)
  printf '%s\n' "${tools[@]+"${tools[@]}"}"
}

# --- check-emission -----------------------------------------------------
#
# Emits a concrete, path-scoped series of `run_check PHASE "name" cmd...`
# lines, one phase at a time, meant to be `eval`'d by a caller that defines
# `run_check` (see agent-validate/run.sh). Every command below is a literal
# invocation over the specific files/dirs classify_paths found, not a
# runtime re-scan -- callers that want checks to cover newly created files
# must re-run classify_paths/relativize_paths first.

#shellcheck disable=SC2329
quote_list() {
  # Shell-quotes each argument and joins them with single spaces, with no
  # trailing space (trailing whitespace does not survive prompt transport).
  local out="" x
  for x in "$@"; do
    out+="$(printf '%q' "$x") "
  done
  printf '%s' "${out% }"
}

#shellcheck disable=SC2329
emit_format_phase() {
  if [[ ${#BASH_FILES[@]} -gt 0 ]]; then
    printf 'run_check FORMAT "shfmt" shfmt -i 2 -w %s\n' "$(quote_list "${BASH_FILES[@]}")"
  fi
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${GO_MODULE_DIRS[@]}"; do
      printf 'run_check FORMAT "go fmt(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go fmt ./...")"
    done
  fi
  if [[ ${#NIX_FILES[@]} -gt 0 ]]; then
    printf 'run_check FORMAT "nixfmt" nixfmt %s\n' "$(quote_list "${NIX_FILES[@]}")"
  fi
  if [[ ${#TF_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${TF_DIRS[@]}"; do
      printf 'run_check FORMAT "terraform fmt(%s)" terraform fmt %s\n' "$d" "$(quote_list "$d")"
    done
  fi
  if [[ ${#YAML_FILES[@]} -eq 0 && ${#HELM_CHART_DIRS[@]} -eq 0 ]]; then
    :
  else
    printf '# NOTE: no YAML formatter is available in this stack; YAML/Helm files are linted but not auto-formatted.\n'
  fi
}

#shellcheck disable=SC2329
emit_lint_phase() {
  if [[ ${#BASH_FILES[@]} -gt 0 ]]; then
    printf 'run_check LINT "shellcheck" shellcheck %s\n' "$(quote_list "${BASH_FILES[@]}")"
    local f
    for f in "${BASH_FILES[@]}"; do
      printf 'run_check LINT "bash -n(%s)" bash -n %s\n' "$f" "$(quote_list "$f")"
    done
  fi
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${GO_MODULE_DIRS[@]}"; do
      printf 'run_check LINT "go vet(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go vet ./...")"
    done
  fi
  if [[ ${#HELM_CHART_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${HELM_CHART_DIRS[@]}"; do
      printf 'run_check LINT "helm lint(%s)" helm lint %s\n' "$d" "$(quote_list "$d")"
    done
  fi
  if [[ ${#YAML_FILES[@]} -gt 0 ]]; then
    printf 'run_check LINT "yamllint" yamllint %s\n' "$(quote_list "${YAML_FILES[@]}")"
  fi
  if [[ ${#NIX_FILES[@]} -gt 0 ]]; then
    # One `statix check` invocation per file: unlike nixfmt, statix's
    # `check` subcommand only accepts a single [TARGET] positional, so
    # passing every NIX_FILES entry to one invocation fails outright
    # ("unexpected argument ... found") instead of checking them all.
    local f
    for f in "${NIX_FILES[@]}"; do
      printf 'run_check LINT "statix check(%s)" statix check %s\n' "$f" "$(quote_list "$f")"
    done
  fi
  if [[ ${#TF_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${TF_DIRS[@]}"; do
      printf 'run_check LINT "terraform validate(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && terraform validate")"
    done
  fi
  if [[ ${#DOCKERFILES[@]} -gt 0 ]]; then
    local f
    for f in "${DOCKERFILES[@]}"; do
      printf 'run_check LINT "hadolint(%s)" hadolint %s\n' "$f" "$(quote_list "$f")"
    done
  fi
}

#shellcheck disable=SC2329
emit_build_test_phase() {
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${GO_MODULE_DIRS[@]}"; do
      printf 'run_check BUILD_TEST "go build(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go build ./...")"
      printf 'run_check BUILD_TEST "go test(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go test ./...")"
    done
  fi
  if [[ ${#HELM_CHART_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${HELM_CHART_DIRS[@]}"; do
      printf 'run_check BUILD_TEST "helm template|kubeconform(%s)" bash -c %s\n' "$d" \
        "$(printf '%q' "set -o pipefail; helm template $(printf '%q' "$d") | kubeconform -strict -summary")"
    done
  fi
  if [[ ${#NIX_FLAKE_DIRS[@]} -gt 0 ]]; then
    local d
    for d in "${NIX_FLAKE_DIRS[@]}"; do
      printf 'run_check BUILD_TEST "nix flake check(%s)" bash -c %s\n' "$d" "$(printf '%q' "nix flake check $(printf '%q' "$d")")"
    done
  fi
}

#shellcheck disable=SC2329
any_checks_emitted() {
  [[ ${#BASH_FILES[@]} -gt 0 || ${#GO_MODULE_DIRS[@]} -gt 0 || ${#YAML_FILES[@]} -gt 0 ||
    ${#HELM_CHART_DIRS[@]} -gt 0 || ${#NIX_FILES[@]} -gt 0 || ${#NIX_FLAKE_DIRS[@]} -gt 0 ||
    ${#TF_DIRS[@]} -gt 0 || ${#DOCKERFILES[@]} -gt 0 ]]
}
