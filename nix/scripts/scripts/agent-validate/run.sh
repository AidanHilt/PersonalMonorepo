#!/bin/bash

# @lib: printing-and-output
# @lib: agent-plan-classify

set -uo pipefail

show_help() {
  cat <<'EOF'
Usage: agent-validate --path <p> [--path <p> ...]

Runs the same FORMAT -> LINT -> BUILD/TEST checks agent-plan-create used to
generate into a one-shot validate.sh, except agent-validate discovers them
AT RUN TIME instead of at dispatch time: every --path is re-classified
(directories are re-expanded) when agent-validate itself runs, so files
created or changed after dispatch are covered too. Paths are repo-relative
and resolved against the repo root agent-validate is invoked from (it must
be run from the top of the git work tree being validated).

agent-validate is installed on PATH outside the IMPLEMENT subagent's
worktree (so the subagent cannot tamper with it); the subagent's permission
to run it at all comes from an exact-match bash allow rule
("agent-validate --path ... [--path ...]") on its own per-dispatch agent
definition file, written by `agent-plan-create` into the generated prompt.

Checks run in a fixed global order -- all FORMAT checks across every
profile, then all LINT checks, then all BUILD/TEST checks -- against a
failure budget of 10 (tracked in the git dir, so it persists across runs).
On full success, writes .agent/validated.json (schema_version 2) with:
"validator" (the resolved path of the agent-validate executable that ran),
"tree_sha" (of the working tree excluding only .agent/), "timestamp",
"paths" (the --path arguments given), "results" (per-check pass records),
and "tool_versions".

Exit codes: 0 all checks passed and the artifact was written; 10 a check
failed (counts against the failure budget); 20 a required tool is missing;
21 a network error; 22 a permission error; 23 an expected artifact value
could not be computed (the artifact is not written in this case); 99 the
failure budget is exhausted.
EOF
}

FAILURE_BUDGET=10
ARTIFACT=".agent/validated.json"
RESULTS=()
PATH_ARGS=()

git_dir() { git rev-parse --git-dir 2>/dev/null; }

failcount_file() {
  local gd
  gd="$(git_dir)" || {
    printf '%s\n' "/tmp/.pi-validate-failcount"
    return
  }
  printf '%s/pi-validate-failcount\n' "$gd"
}

read_failcount() {
  local f count
  f="$(failcount_file)"
  if [[ -f "$f" ]]; then
    count="$(cat "$f")" || die_artifact "could not read failure count from $f"
  else
    count=0
  fi
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    die_artifact "$f contains a non-numeric failure count ('$count')"
  fi
  printf '%s\n' "$count"
}

write_failcount() {
  local f
  f="$(failcount_file)"
  printf '%s\n' "$1" >"$f" || die_artifact "could not write failure count to $f"
}

#shellcheck disable=SC2329
classify_error() {
  local out="$1"
  if printf '%s' "$out" | grep -qiE 'could not resolve host|connection refused|connection timed out|timed out after|network is unreachable|certificate verify failed|tls handshake|ssl certificate problem|no route to host|name or service not known|temporary failure in name resolution'; then
    printf 'network\n'
  elif printf '%s' "$out" | grep -qiE 'permission denied|operation not permitted|forbidden|eacces|access denied'; then
    printf 'permission\n'
  else
    printf 'check\n'
  fi
}

#shellcheck disable=SC2329
print_tail() {
  printf '%s\n' "$1" | tail -n 40
}

#shellcheck disable=SC2329
record_pass() {
  RESULTS+=("{\"phase\":\"$1\",\"check\":\"$2\",\"status\":\"pass\"}")
}

#shellcheck disable=SC2329
handle_failure() {
  local phase="$1" name="$2" rc="$3" out="$4"
  local kind
  kind="$(classify_error "$out")"
  case "$kind" in
  network)
    printf '[%s] NETWORK ERROR in "%s" (exit %s)\n' "$phase" "$name" "$rc" >&2
    print_tail "$out" >&2
    exit 21
    ;;
  permission)
    printf '[%s] PERMISSION ERROR in "%s" (exit %s)\n' "$phase" "$name" "$rc" >&2
    print_tail "$out" >&2
    exit 22
    ;;
  *)
    local count
    count="$(read_failcount)"
    count=$((count + 1))
    write_failcount "$count"
    printf '[%s] FAILED "%s" (exit %s) -- failed run %s/%s\n' "$phase" "$name" "$rc" "$count" "$FAILURE_BUDGET" >&2
    print_tail "$out" >&2
    if [[ "$count" -ge "$FAILURE_BUDGET" ]]; then
      printf 'Failure budget (%s) exhausted.\n' "$FAILURE_BUDGET" >&2
      exit 99
    fi
    exit 10
    ;;
  esac
}

#shellcheck disable=SC2329
run_check() {
  local phase="$1" name="$2"
  shift 2
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '[%s] ok: %s\n' "$phase" "$name"
    record_pass "$phase" "$name"
  else
    handle_failure "$phase" "$name" "$rc" "$out"
  fi
}

# An expected artifact value (tree_sha, timestamp, validator path, or a
# tool version) could not be computed. Silent degradation (writing
# "unknown" or an empty value) is unacceptable, so abort instead: remove
# any partial artifact and exit with a dedicated code rather than exit 0
# or 10.
die_artifact() {
  printf 'ARTIFACT ERROR: %s\n' "$1" >&2
  rm -f "$ARTIFACT"
  exit 23
}

# Computes a tree_sha for the current working tree via a temporary index,
# excluding only .agent/ (unlike the old generated validate.sh, this does
# NOT also exclude validate.sh -- there is no validate.sh in this flow).
compute_tree_sha() {
  local tmp_index out rc
  tmp_index="$(mktemp -u)"
  # Seed from HEAD so tracked-but-gitignored files are kept, matching what
  # the worktree commit records.
  out="$(GIT_INDEX_FILE="$tmp_index" git read-tree HEAD 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    rm -f "$tmp_index"
    return $rc
  fi
  out="$(GIT_INDEX_FILE="$tmp_index" git add -A -- :/ 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    rm -f "$tmp_index"
    return $rc
  fi
  # --ignore-unmatch legitimately may match nothing (no .agent/ tracked
  # yet), but any other failure must still propagate.
  out="$(GIT_INDEX_FILE="$tmp_index" git rm -r --cached --ignore-unmatch -q .agent 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    rm -f "$tmp_index"
    return $rc
  fi
  out="$(GIT_INDEX_FILE="$tmp_index" git write-tree 2>&1)"
  rc=$?
  rm -f "$tmp_index"
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    return $rc
  fi
  printf '%s\n' "$out"
  return 0
}

# Per-tool version lookups: most tools support --version, but a handful
# need a different invocation. Falls through to "<tool> --version" for
# anything not special-cased.
tool_version() {
  local t="$1"
  case "$t" in
  go)
    go version 2>&1 | head -1
    ;;
  helm)
    helm version --short 2>&1 | head -1
    ;;
  kubeconform)
    kubeconform -v 2>&1 | head -1
    ;;
  *)
    "$t" --version 2>&1 | head -1
    ;;
  esac
}

json_string_array() {
  # json_string_array <values...> -> a JSON array of strings, via jq -R -s.
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

main() {
  if [[ $# -eq 0 ]]; then
    print_error "Missing arguments"
    show_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --path)
      [[ $# -ge 2 ]] || {
        print_error "--path requires a value"
        exit 1
      }
      PATH_ARGS+=("$2")
      shift 2
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
    esac
  done

  if [[ ${#PATH_ARGS[@]} -eq 0 ]]; then
    print_error "At least one --path is required"
    exit 1
  fi

  local repo_root
  if ! repo_root="$(find_repo_root "$(pwd)")"; then
    print_error "Current directory is not inside a git repository (no .git found walking up)"
    exit 1
  fi
  if [[ "$repo_root" != "$(pwd)" ]]; then
    print_error "agent-validate must be run from the repo root ('$repo_root'), not '$(pwd)'"
    exit 1
  fi

  local raw_paths
  raw_paths="$(printf '%s,' "${PATH_ARGS[@]}")"
  classify_paths "$raw_paths" "$repo_root"
  relativize_paths "$repo_root"

  if [[ ${#UNKNOWN_PATHS[@]} -gt 0 ]]; then
    print_warning "No checks for: ${UNKNOWN_PATHS[*]}"
  fi

  local tools_list=() baseline_tools=(git jq sha256sum cut head tail grep mktemp date cat)
  mapfile -t tools_list < <(required_tools_for_profiles)

  local all_tools=() t
  for t in "${tools_list[@]+"${tools_list[@]}"}" "${baseline_tools[@]}"; do
    [[ -z "$t" ]] && continue
    array_contains "$t" "${all_tools[@]+"${all_tools[@]}"}" || all_tools+=("$t")
  done

  local missing=()
  for t in "${all_tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    print_error "Missing required tools: ${missing[*]}"
    exit 20
  fi

  # --- failure budget check (before doing any work) -------------------------

  local current_failcount
  current_failcount="$(read_failcount)"
  if [[ "$current_failcount" -ge "$FAILURE_BUDGET" ]]; then
    print_error "Failure budget ($FAILURE_BUDGET) already exhausted from prior runs."
    exit 99
  fi

  rm -f "$ARTIFACT"

  # --- FORMAT phase (mutating; reformatting itself is not a failure) --------

  eval "$(emit_format_phase)"

  # --- LINT phase -------------------------------------------------------------

  eval "$(emit_lint_phase)"

  # --- BUILD/TEST phase --------------------------------------------------------

  eval "$(emit_build_test_phase)"

  # --- all phases passed: write the artifact ---------------------------------

  mkdir -p .agent

  local validator
  validator="$(realpath -m -- "$0")" || die_artifact "could not resolve the path of the running agent-validate executable"
  [[ -n "$validator" ]] || die_artifact "resolved validator path came out empty"

  local tree_sha
  tree_sha="$(compute_tree_sha)" || die_artifact "compute_tree_sha failed"
  if [[ ! "$tree_sha" =~ ^[0-9a-f]{40,64}$ ]]; then
    die_artifact "tree_sha did not come out as a git tree object id ('$tree_sha')"
  fi

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || die_artifact "date failed"
  if [[ ! "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    die_artifact "timestamp did not come out in the expected UTC format ('$ts')"
  fi

  local tool_versions_obj="{}" v rc
  for t in "${all_tools[@]}"; do
    v="$(tool_version "$t")"
    rc=$?
    if [[ $rc -ne 0 || -z "$v" ]]; then
      die_artifact "could not determine a version string for required tool '$t' (exit $rc, output: '$v')"
    fi
    tool_versions_obj="$(printf '%s' "$tool_versions_obj" | jq --arg k "$t" --arg v "$v" '. + {($k): $v}')" ||
      die_artifact "jq failed while recording the version of '$t'"
  done

  local paths_json results_json
  paths_json="$(json_string_array "${PATH_ARGS[@]}")" || die_artifact "failed to build the paths JSON array"
  results_json="$(
    IFS=,
    echo "${RESULTS[*]+"${RESULTS[*]}"}"
  )"

  {
    printf '{\n'
    printf '  "schema_version": 2,\n'
    printf '  "validator": "%s",\n' "$validator"
    printf '  "tree_sha": "%s",\n' "$tree_sha"
    printf '  "timestamp": "%s",\n' "$ts"
    printf '  "paths": %s,\n' "$paths_json"
    printf '  "results": [%s],\n' "$results_json"
    printf '  "tool_versions": %s\n' "$tool_versions_obj"
    printf '}\n'
  } >"$ARTIFACT" || die_artifact "failed to write $ARTIFACT"

  printf 'All checks passed. Wrote %s\n' "$ARTIFACT"
  write_failcount 0
  exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

main "$@"
