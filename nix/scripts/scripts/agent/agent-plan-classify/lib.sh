#!/bin/bash
# Shared path-classification + check-emission logic for agent-plan-create
# (pre-dispatch required-tools check and planning metadata) and agent-validate
# (actual runtime check execution). Classifies a list of files/directories
# into file-type "profiles" (bash, go, plain yaml, helm chart templates, helm
# charts, nix, terraform, dockerfiles), derives the tools each profile needs,
# and emits the concrete per-profile LINT/BUILD_TEST commands as
# `run_check PHASE "name" cmd...` lines of shell text that a caller defining
# `run_check` can `eval`.
#
# YAML_FILES holds plain YAML only -- it is exactly what yamlfmt/yamllint are
# handed, so Helm template sources (.yaml/.yml/.tpl/.gotmpl below a chart's
# templates/ directory) never appear in it. Those live in
# HELM_TEMPLATE_FILES, which helmfmt formats, while HELM_CHART_DIRS records
# the chart roots needing helm lint / kubeconform.
#
# Flake ownership is tracked separately from file type. AFFECTED_FLAKE_DIRS
# holds the nearest flake.nix root (inside the repo) enclosing every
# classified path, discovered independently of file extension -- a changed
# README.md still makes its flake affected -- and explicitly supplied
# directory overrides count on their own, both for their own enclosing flake
# and for every nested flake root beneath them (found by a separate
# flake.nix search, so a nested flake holding only docs or unsupported files
# is still discovered), so no changed .nix file is needed. A path inside one
# of those roots is "flake-owned": its legacy LINT and
# BUILD_TEST checks are suppressed, because that flake's own
# checks.<system>.agent-validate aggregate covers them instead. FORMAT checks
# are never suppressed: formatters still run over flake-owned files.
#
# Usage (from a run.sh that also declares "#include agent-plan-classify" and
# "#include printing-and-output"):
#
#   classify_paths "$repo_root" "${path_args[@]}"
#   relativize_paths "$repo_root"
#   mapfile -t tools_list < <(required_tools_for_profiles)
#   eval "$(emit_lint_phase)"
#   eval "$(emit_build_test_phase)"
#   eval "$(emit_flake_build_phase)"
#
# classify_paths takes the repo root plus the actual path arguments (files or
# directories), never a joined or encoded string: filenames may contain
# spaces, tabs, or newlines, so callers must keep them in arrays end to end.
# The FORMAT phase itself lives in the agent-format lib
# (agent_format_emit_phase) so it can evolve independently of classification.
#
# emit_flake_build_phase reads two globals the caller owns: NIX_SYSTEM (the
# system resolved with Nix) and FLAKE_CHECK_DIRS (the affected flakes whose
# checks.<system>.agent-validate contract actually exists -- normally every
# AFFECTED_FLAKE_DIRS entry, minus the ones missing a contract under
# agent-validate's manual --warn-missing-flake-checks mode). Both are set
# after relativize_paths and after the contract preflight, so this emitter
# stays purely mechanical and never builds an aggregate that isn't there.
#
# This file never calls "exit" -- callers decide what a classification
# failure (e.g. an unknown path) means for them.

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
NIX_SYSTEM=""
#shellcheck disable=SC2034
UNKNOWN_PATHS=()

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

# Records the nearest flake.nix root enclosing <path> (a file or directory)
# in AFFECTED_FLAKE_DIRS. Returns 0 when the path is flake-owned, 1 otherwise.
# Callers must not let the 1 propagate as the last command of a function:
# agent-plan-create runs under errexit.
#shellcheck disable=SC2329
record_flake_ownership() {
  local path="$1" repo_root="$2" start flake_root
  if [[ -d "$path" ]]; then
    start="$path"
  else
    start="$(dirname "$path")"
  fi
  if flake_root="$(walk_up_for_marker "$start" "flake.nix" "$repo_root")"; then
    add_unique AFFECTED_FLAKE_DIRS "$flake_root"
    return 0
  fi
  return 1
}

# True (0) when <path> lies at or below one of the affected flake roots. Both
# sides are expected in the same form: relativize_paths() normalizes
# AFFECTED_FLAKE_DIRS and the profile arrays in place before any emitter (or
# required_tools_for_profiles) runs, so the prefix comparison is on
# repo-relative paths -- absolute ones would compare correctly too, as long
# as they were recorded the same way.
#shellcheck disable=SC2329
path_is_flake_owned() {
  local path="$1" root
  for root in "${AFFECTED_FLAKE_DIRS[@]+"${AFFECTED_FLAKE_DIRS[@]}"}"; do
    # A flake at the repo root owns everything below it.
    [[ "$root" == "." ]] && return 0
    [[ "$path" == "$root" || "$path" == "$root"/* ]] && return 0
  done
  return 1
}

# True (0) when at least one of the given paths is NOT flake-owned, i.e. when
# a legacy check covering them will actually run.
#shellcheck disable=SC2329
any_non_flake_paths() {
  local p
  for p in "$@"; do
    path_is_flake_owned "$p" || return 0
  done
  return 1
}

# Splits a path list into the non-flake-owned subset, stored in the array
# named by $1 (which is reset first).
#shellcheck disable=SC2329
collect_non_flake_paths() {
  local -n _cnfp_out="$1"
  shift
  _cnfp_out=()
  local p
  for p in "$@"; do
    path_is_flake_owned "$p" || _cnfp_out+=("$p")
  done
}

# Prints the nearest chart root (the directory holding Chart.yaml, found by
# walking up from the file's own directory) when the file is a Helm template
# source -- i.e. it sits below that root's templates/ directory. Chart layout
# is the sole rule: Chart.yaml, values files, crds/ and anything else outside
# templates/ is plain YAML, never a template source. Returns 1 otherwise.
#shellcheck disable=SC2329
find_chart_template_root() {
  local f="$1" repo_root="$2" chart_root
  chart_root="$(walk_up_for_marker "$(dirname "$f")" "Chart.yaml" "$repo_root")" || return 1
  [[ "$f" == "$chart_root"/templates/* ]] || return 1
  printf '%s\n' "$chart_root"
}

#shellcheck disable=SC2329
classify_file() {
  local f="$1" repo_root="$2"
  local base dir
  base="$(basename "$f")"
  dir="$(dirname "$f")"

  # Flake ownership is recorded for every file, recognized extension or not,
  # so docs and otherwise-unclassified files still make their flake affected.
  record_flake_ownership "$f" "$repo_root" || true

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
    # Chart.yaml is plain YAML -- so yamlfmt/yamllint cover it -- *and* the
    # marker that triggers the chart-level helm/kubeconform checks.
    add_unique YAML_FILES "$f"
    add_unique HELM_CHART_DIRS "$dir"
    return
    ;;
  *.yaml | *.yml)
    local chart_template_root chart_dir
    if chart_template_root="$(find_chart_template_root "$f" "$repo_root")"; then
      # A template source: helmfmt owns it, and yamlfmt/yamllint must never
      # see it, so it stays out of YAML_FILES entirely.
      add_unique HELM_TEMPLATE_FILES "$f"
      add_unique HELM_CHART_DIRS "$chart_template_root"
      return
    fi
    add_unique YAML_FILES "$f"
    if chart_dir="$(walk_up_for_marker "$dir" "Chart.yaml" "$repo_root")"; then
      add_unique HELM_CHART_DIRS "$chart_dir"
    fi
    return
    ;;
  *.tpl | *.gotmpl)
    local chart_template_root
    if chart_template_root="$(find_chart_template_root "$f" "$repo_root")"; then
      add_unique HELM_TEMPLATE_FILES "$f"
      add_unique HELM_CHART_DIRS "$chart_template_root"
    else
      add_unique UNKNOWN_PATHS "$f"
    fi
    return
    ;;
  *.nix)
    # NIX_FILES drives nixfmt (FORMAT) and statix (LINT); the flake itself is
    # recorded by record_flake_ownership above, extension-independently.
    add_unique NIX_FILES "$f"
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
    -o -path '*/templates/*.tpl' -o -path '*/templates/*.gotmpl' \
    \) -print0)
}

# classify_paths <repo_root> <path>...
#
# Each path argument is a file or directory, taken verbatim -- never a
# comma/whitespace-joined string, so filenames containing spaces, tabs, or
# newlines survive. Directories are expanded recursively, and an explicit
# directory override makes its own enclosing flake affected even when none of
# the files found below it are flake-owned by extension rules -- and registers
# every nested flake root beneath it too, regardless of what those flakes
# contain.
#shellcheck disable=SC2329
classify_paths() {
  local repo_root="$1"
  shift
  local p resolved nf
  for p in "$@"; do
    [[ -z "$p" ]] && continue
    resolved="$(resolve_path "$p")"
    if [[ -f "$resolved" ]]; then
      classify_file "$resolved" "$repo_root"
    elif [[ -d "$resolved" ]]; then
      # The override directory itself counts toward flake ownership: a
      # directory below a flake root makes that flake affected without any
      # changed .nix file, and one that holds a flake.nix affects it too.
      record_flake_ownership "$resolved" "$repo_root" || true
      # classify_dir only visits recognized file extensions, so a nested flake
      # whose files are all docs or otherwise unclassifiable would never be
      # recorded by it -- and its checks.<system>.agent-validate contract would
      # then neither be preflighted nor built. Find flake.nix roots beneath the
      # override separately, NUL-safe, and register each one directly: flake
      # discovery alone must not turn unclassifiable files into
      # UNKNOWN_PATHS entries.
      while IFS= read -r -d '' nf; do
        add_unique AFFECTED_FLAKE_DIRS "$(dirname "$nf")"
      done < <(find "$resolved" -name flake.nix -print0)
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
  for name in BASH_FILES GO_MODULE_DIRS YAML_FILES HELM_TEMPLATE_FILES HELM_CHART_DIRS NIX_FILES AFFECTED_FLAKE_DIRS TF_DIRS DOCKERFILES; do
    relativize_array "$name" "$repo_root"
  done
}

# --- required tool computation ---------------------------------------------

#shellcheck disable=SC2329
required_tools_for_profiles() {
  local tools=()
  # FORMAT-phase tools: required for every classified path, flake-owned or
  # not -- formatters are never suppressed.
  [[ ${#BASH_FILES[@]} -gt 0 ]] && tools+=(shfmt)
  [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]] && tools+=(go)
  [[ ${#YAML_FILES[@]} -gt 0 ]] && tools+=(yamlfmt)
  [[ ${#HELM_TEMPLATE_FILES[@]} -gt 0 ]] && tools+=(helmfmt)
  [[ ${#NIX_FILES[@]} -gt 0 ]] && tools+=(nixfmt)
  [[ ${#TF_DIRS[@]} -gt 0 ]] && tools+=(terraform)
  # Legacy LINT/BUILD_TEST tools: required only when at least one path their
  # checks cover is NOT flake-owned. Flake-owned paths are covered by their
  # flake's checks.<system>.agent-validate aggregate instead.
  if any_non_flake_paths "${BASH_FILES[@]+"${BASH_FILES[@]}"}"; then
    tools+=(shellcheck bash)
  fi
  if any_non_flake_paths "${YAML_FILES[@]+"${YAML_FILES[@]}"}"; then
    tools+=(yamllint)
  fi
  if any_non_flake_paths "${HELM_CHART_DIRS[@]+"${HELM_CHART_DIRS[@]}"}"; then
    tools+=(helm kubeconform)
  fi
  if any_non_flake_paths "${NIX_FILES[@]+"${NIX_FILES[@]}"}"; then
    tools+=(statix)
  fi
  if any_non_flake_paths "${DOCKERFILES[@]+"${DOCKERFILES[@]}"}"; then
    tools+=(hadolint)
  fi
  # `nix` is required for every affected flake, not just for .nix files:
  # agent-validate preflights each checks.<system>.agent-validate contract
  # with `nix eval` and then builds it with `nix build`.
  [[ ${#AFFECTED_FLAKE_DIRS[@]} -gt 0 ]] && tools+=(nix)
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
emit_lint_phase() {
  local f d legacy=()
  if [[ ${#BASH_FILES[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${BASH_FILES[@]+"${BASH_FILES[@]}"}"
    if [[ ${#legacy[@]} -gt 0 ]]; then
      printf 'run_check LINT "shellcheck" shellcheck %s\n' "$(quote_list "${legacy[@]}")"
      for f in "${legacy[@]}"; do
        printf 'run_check LINT "bash -n(%s)" bash -n %s\n' "$f" "$(quote_list "$f")"
      done
    fi
  fi
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${GO_MODULE_DIRS[@]+"${GO_MODULE_DIRS[@]}"}"
    for d in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check LINT "go vet(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go vet ./...")"
    done
  fi
  if [[ ${#HELM_CHART_DIRS[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${HELM_CHART_DIRS[@]+"${HELM_CHART_DIRS[@]}"}"
    for d in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check LINT "helm lint(%s)" helm lint %s\n' "$d" "$(quote_list "$d")"
    done
  fi
  if [[ ${#YAML_FILES[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${YAML_FILES[@]+"${YAML_FILES[@]}"}"
    if [[ ${#legacy[@]} -gt 0 ]]; then
      printf 'run_check LINT "yamllint" yamllint %s\n' "$(quote_list "${legacy[@]}")"
    fi
  fi
  if [[ ${#NIX_FILES[@]} -gt 0 ]]; then
    # One `statix check` invocation per file: unlike nixfmt, statix's
    # `check` subcommand only accepts a single [TARGET] positional, so
    # passing every NIX_FILES entry to one invocation fails outright
    # ("unexpected argument ... found") instead of checking them all.
    collect_non_flake_paths legacy "${NIX_FILES[@]+"${NIX_FILES[@]}"}"
    for f in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check LINT "statix check(%s)" statix check %s\n' "$f" "$(quote_list "$f")"
    done
  fi
  if [[ ${#TF_DIRS[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${TF_DIRS[@]+"${TF_DIRS[@]}"}"
    for d in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check LINT "terraform validate(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && terraform validate")"
    done
  fi
  if [[ ${#DOCKERFILES[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${DOCKERFILES[@]+"${DOCKERFILES[@]}"}"
    for f in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check LINT "hadolint(%s)" hadolint %s\n' "$f" "$(quote_list "$f")"
    done
  fi
}

#shellcheck disable=SC2329
emit_build_test_phase() {
  local d legacy=()
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${GO_MODULE_DIRS[@]+"${GO_MODULE_DIRS[@]}"}"
    for d in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check BUILD_TEST "go build(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go build ./...")"
      printf 'run_check BUILD_TEST "go test(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go test ./...")"
    done
  fi
  if [[ ${#HELM_CHART_DIRS[@]} -gt 0 ]]; then
    collect_non_flake_paths legacy "${HELM_CHART_DIRS[@]+"${HELM_CHART_DIRS[@]}"}"
    for d in "${legacy[@]+"${legacy[@]}"}"; do
      printf 'run_check BUILD_TEST "helm template|kubeconform(%s)" bash -c %s\n' "$d" \
        "$(printf '%q' "set -o pipefail; helm template $(printf '%q' "$d") | kubeconform -strict -summary")"
    done
  fi
}

# Emits one BUILD_TEST check per affected flake whose aggregate exists:
# exactly `nix build <local-flake-dir>#checks.<system>.agent-validate`, with an
# explicit `./` for relative local paths. There is deliberately no generic
# `nix flake check` fallback -- a flake that doesn't expose the contract is
# either reported (exit 24) or, under --warn-missing-flake-checks, simply not
# built, which is why the caller narrows FLAKE_CHECK_DIRS before emitting.
#shellcheck disable=SC2329
emit_flake_build_phase() {
  local d flake_path
  # The IMPLEMENT sandbox's nono command policy matches `nix` invocations by
  # argv prefix, so no flag is placed ahead of the subcommand: the host's
  # nix.conf already enables nix-command/flakes.
  for d in "${FLAKE_CHECK_DIRS[@]+"${FLAKE_CHECK_DIRS[@]}"}"; do
    # Nix parses a schemeless argument like `nix/scripts` as an INDIRECT flake
    # ref: it resolves the implicit default `github:NixOS/nix` and treats the
    # path as the requested ref (failing with an HTTP 422 on api.github.com)
    # instead of using the local directory. An explicit `./` prefix forces the
    # local-path interpretation. Absolute paths are already unambiguous.
    if [[ "$d" == /* ]]; then
      flake_path="$d"
    else
      flake_path="./$d"
    fi
    printf 'run_check BUILD_TEST "nix build(%s)" nix build %s\n' "$d" \
      "$(quote_list "${flake_path}#checks.${NIX_SYSTEM}.agent-validate")"
  done
}

#shellcheck disable=SC2329
any_checks_emitted() {
  [[ ${#BASH_FILES[@]} -gt 0 || ${#GO_MODULE_DIRS[@]} -gt 0 || ${#YAML_FILES[@]} -gt 0 ||
    ${#HELM_TEMPLATE_FILES[@]} -gt 0 || ${#HELM_CHART_DIRS[@]} -gt 0 ||
    ${#NIX_FILES[@]} -gt 0 || ${#AFFECTED_FLAKE_DIRS[@]} -gt 0 ||
    ${#TF_DIRS[@]} -gt 0 || ${#DOCKERFILES[@]} -gt 0 ]]
}
