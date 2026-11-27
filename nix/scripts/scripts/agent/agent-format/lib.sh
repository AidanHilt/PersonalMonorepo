#!/bin/bash
# Shared FORMAT-phase check emission for agent-validate. Owns the "what does
# the formatting phase run?" question so it can evolve independently of path
# classification.
#
# Usage (from a run.sh that also declares "#include agent-plan-classify"):
#
#   classify_paths "$raw_paths" "$repo_root"
#   relativize_paths "$repo_root"
#   eval "$(agent_format_emit_phase)"
#
# The emitted commands are literal invocations over the specific files/dirs
# classify_paths found, not a runtime re-scan -- callers that want checks to
# cover newly created files must re-run classify_paths/relativize_paths
# first.
#
# This file never calls "exit" -- callers decide what a failed format check
# means for them.

#include agent-plan-classify

# The classified path arrays (BASH_FILES, GO_MODULE_DIRS, NIX_FILES, TF_DIRS,
# YAML_FILES, HELM_CHART_DIRS) and the quote_list helper are provided by
# agent-plan-classify -- shellcheck sees this file on its own, so those
# cross-lib references are not assigned here.
#shellcheck disable=SC2154

# Emits the concrete `run_check FORMAT "name" cmd...` lines for every
# classified profile that has a formatter, meant to be `eval`'d by a caller
# that defines `run_check` (see agent-validate/run.sh).
#shellcheck disable=SC2329
agent_format_emit_phase() {
  local d
  if [[ ${#BASH_FILES[@]} -gt 0 ]]; then
    printf 'run_check FORMAT "shfmt" shfmt -i 2 -w %s\n' "$(quote_list "${BASH_FILES[@]}")"
  fi
  if [[ ${#GO_MODULE_DIRS[@]} -gt 0 ]]; then
    for d in "${GO_MODULE_DIRS[@]}"; do
      printf 'run_check FORMAT "go fmt(%s)" bash -c %s\n' "$d" "$(printf '%q' "cd $(printf '%q' "$d") && go fmt ./...")"
    done
  fi
  if [[ ${#NIX_FILES[@]} -gt 0 ]]; then
    printf 'run_check FORMAT "nixfmt" nixfmt %s\n' "$(quote_list "${NIX_FILES[@]}")"
  fi
  if [[ ${#TF_DIRS[@]} -gt 0 ]]; then
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
