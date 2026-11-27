#!/bin/bash

#include printing-and-output
#include agent-git-discovery
#include agent-plan-classify
#include agent-format

set -uo pipefail

show_help() {
  cat <<'EOF'
Usage: agent-validate [--path <p> ...] [--warn-missing-flake-checks]

Validates the working tree and must be run from the top of the git work tree
being validated (the repository root).

Selection. With no --path, agent-validate discovers the files to validate
itself via Git: tracked changes against HEAD (staged and unstaged) plus
untracked, non-ignored files, excluding the .agent/ bookkeeping directory.
Those repo-relative paths are classified directly, so filenames containing
spaces, tabs, or newlines survive. A real Git failure is reported as an
error, never as an empty selection. Any explicit --path values override Git
discovery entirely: each is a repo-relative file or directory and directories
are re-expanded recursively at run time, so files created after a dispatch
are covered too. Zero changed files with no --path is a successful no-op --
no phases run, the artifact is still written with empty "paths"/"results",
and the failure count is reset like any other successful validation.

Checks. FORMAT (mutating formatters) runs over every classified file,
including flake-owned ones. Every path inside an affected flake root is
"flake-owned": its legacy LINT/BUILD_TEST checks (shellcheck, bash -n, go
vet/build/test, yamllint, statix, terraform validate, hadolint, helm lint,
helm template|kubeconform) are suppressed, because that flake's own
checks.<system>.agent-validate aggregate covers them. Legacy checks still run
for non-flake paths. Before any FORMAT/LINT/BUILD_TEST work, agent-validate
resolves the current system with Nix and preflights every affected flake for
checks.<system>.agent-validate (checked/exposed with `nix eval`, not built).
Missing contracts normally exit 24 after all gaps are listed; with
--warn-missing-flake-checks the complete gap list is printed, the available
checks still run, the missing aggregates are skipped, and both the warning
mode and the gaps are recorded in the artifact. Each existing aggregate is
then built with exactly
`nix build <local-flake-dir>#checks.<system>.agent-validate` (an explicit
`./` prefix for relative local paths) -- there is no generic
`nix flake check` fallback.

agent-validate is installed on PATH outside the IMPLEMENT subagent's
worktree (so the subagent cannot tamper with it); the subagent's permission
to run it at all comes from an exact-match bash allow rule ("agent-validate",
with no arguments) on its own per-dispatch agent definition file, written by
`agent-plan-create` into that dispatch's plan file
(/tmp/pi-agent-plans/IMPLEMENT-<n>.md). `--paths`/`--new-paths` are planning
metadata only; they are not passed to agent-validate at runtime.

Checks run in a fixed global order -- all FORMAT checks across every profile,
then all LINT checks, then all BUILD/TEST checks -- against a failure budget
of 10 (tracked in the git dir, so it persists across runs). On full success,
writes .agent/validated.json (schema_version 3) with:
"validator" (the resolved path of the agent-validate executable that ran),
"tree_sha" (of the working tree excluding only .agent/), "timestamp",
"selection" ("git-discovery" or "explicit-paths"), "warn_missing_flake_checks",
"missing_flake_checks" (empty unless warning mode skipped gaps; each entry is
{"flake": <repo-relative flake root>, "check": <attribute path>}),
"paths" (the explicit --path overrides or the discovered files),
"results" (per-check pass records), and "tool_versions".

Exit codes: 0 all checks passed and the artifact was written; 10 a check
failed (counts against the failure budget); 20 a required tool is missing;
21 a network error; 22 a permission error; 23 an expected artifact value
could not be computed (the artifact is not written in this case); 24 an
affected flake is missing its checks.<system>.agent-validate contract and
--warn-missing-flake-checks was not given; 99 the failure budget is exhausted.
EOF
}

FAILURE_BUDGET=10
ARTIFACT=".agent/validated.json"
RESULTS=()
FLAKE_CONTRACT_OUTPUT=""

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
#
# Each probe captures the command's COMPLETE combined stdout/stderr before
# selecting a line, deliberately avoiding "... 2>&1 | head -1". This
# script runs with pipefail (see the top of the file), so a pipeline into
# head would let head exit after the first line, the producer would get
# SIGPIPE, and the pipeline status would become 141 -- misreporting a
# perfectly good version probe as a failed one and turning a successful
# run into an artifact error (exit 23). Capturing first and trimming with
# parameter expansion keeps the probe's own exit status intact.
tool_version() {
  local t="$1" probe out rc
  case "$t" in
  go)
    probe=(go version)
    ;;
  helm)
    probe=(helm version --short)
    ;;
  kubeconform)
    probe=(kubeconform -v)
    ;;
  *)
    probe=("$t" --version)
    ;;
  esac
  out="$("${probe[@]}" 2>&1)"
  rc=$?
  # Emit only the first line either way; on failure also return the probe's
  # real nonzero status so a failed version command is never read as success
  # (main's diagnostic still gets the text above).
  printf '%s\n' "${out%%$'\n'*}"
  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi
  return 0
}

json_string_array() {
  # json_string_array <values...> -> a JSON array of strings, via jq -R -s.
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

# Preflights one affected flake's checks.<system>.agent-validate contract
# without building it: `nix eval` only instantiates the attribute (producing
# its derivation in the store) and never realises it. Returns 0 when the
# attribute exists, 1 when Nix reports it as missing, and 2 -- with the full
# diagnostic in FLAKE_CONTRACT_OUTPUT -- for any other evaluation failure, so
# an operational Nix problem is never mislabelled as a missing contract.
#shellcheck disable=SC2329
check_flake_contract() {
  local flake_dir="$1" system="$2" flake_path target out rc
  # Same local-path rule as emit_flake_build_phase: without an explicit ./
  # prefix Nix reads a schemeless argument as an indirect flake ref.
  if [[ "$flake_dir" == /* ]]; then
    flake_path="$flake_dir"
  else
    flake_path="./$flake_dir"
  fi
  target="${flake_path}#checks.${system}.agent-validate"
  out="$(nix eval "$target" 2>&1)"
  rc=$?
  FLAKE_CONTRACT_OUTPUT="$out"
  if [[ $rc -eq 0 ]]; then
    return 0
  fi
  if printf '%s' "$out" | grep -qE "does not provide attribute|attribute '[^']*' missing"; then
    return 1
  fi
  return 2
}

main() {
  # writeShellApplication (the Nix builder for this script) prepends
  # 'set -o errexit' to the built binary, but this file is written
  # assuming errexit is OFF: run_check and friends rely on capturing a
  # failing command's exit status via `rc=$?` after a plain assignment
  # (e.g. `out="$("$@" 2>&1)"`), which errexit would instead treat as a
  # fatal error and abort the whole script on, before that capture ever
  # runs -- silently skipping the documented exit codes (10/20/21/22/24/99),
  # the FAILED message, and the failure-budget counter. Turn errexit back
  # off here so this script's own explicit exit-code handling is what
  # actually runs; -u and pipefail (set above) are left untouched.
  set +e

  local warn_missing_flake_checks=0
  local -a path_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --path)
      [[ $# -ge 2 ]] || {
        print_error "--path requires a value"
        exit 1
      }
      path_args+=("$2")
      shift 2
      ;;
    --warn-missing-flake-checks)
      warn_missing_flake_checks=1
      shift
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

  local repo_root
  if ! repo_root="$(find_repo_root "$(pwd)")"; then
    print_error "Current directory is not inside a git repository (no .git found walking up)"
    exit 1
  fi
  if [[ "$repo_root" != "$(pwd)" ]]; then
    print_error "agent-validate must be run from the repo root ('$repo_root'), not '$(pwd)'"
    exit 1
  fi

  # --- selection: explicit --path overrides, or Git discovery ---------------

  local selection
  local -a selected_paths=()
  if [[ ${#path_args[@]} -eq 0 ]]; then
    selection="git-discovery"
    if ! discover_changed_files "$repo_root"; then
      print_error "Git change discovery failed: ${GIT_DISCOVERY_ERROR:-unknown error}"
      print_error "Refusing to validate an empty selection that Git did not actually report as empty."
      exit 1
    fi
    selected_paths=("${DISCOVERED_PATHS[@]+"${DISCOVERED_PATHS[@]}"}")
    if [[ ${#selected_paths[@]} -eq 0 ]]; then
      print_status "No changed or untracked files found; this run is a no-op."
    fi
  else
    selection="explicit-paths"
    selected_paths=("${path_args[@]}")
  fi

  # Classification (and the flake ownership it records) works on the actual
  # path arguments, never on a comma/whitespace-joined string.
  classify_paths "$repo_root" "${selected_paths[@]+"${selected_paths[@]}"}"
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

  # Any artifact already on disk describes an earlier run; it must not
  # outlive a run that fails before rewriting it (exit 24 in particular), so
  # clear it as soon as the required-tool preflight has passed.
  rm -f "$ARTIFACT"

  # Reset by the flake preflight below; declared here so the artifact write at
  # the end can always read them, including on a no-op run.
  local -a missing_flake_checks=()
  FLAKE_CHECK_DIRS=()
  NIX_SYSTEM=""

  # --- failure budget check, preflight, and phases ---------------------------
  #
  # A zero-file selection (no --path, no changed files) is a successful no-op:
  # there is nothing to format, lint, or build, no flake contract to require,
  # and nothing that could fail -- so the failure budget does not gate it and
  # it still writes the artifact and resets the failure count below, like any
  # other passing run.
  if [[ ${#selected_paths[@]} -gt 0 ]]; then
    # --- failure budget check (before doing any work) -------------------------

    local current_failcount
    current_failcount="$(read_failcount)"
    if [[ "$current_failcount" -ge "$FAILURE_BUDGET" ]]; then
      print_error "Failure budget ($FAILURE_BUDGET) already exhausted from prior runs."
      exit 99
    fi

    # --- flake aggregate preflight (before any FORMAT/LINT/BUILD_TEST work) --

    if [[ ${#AFFECTED_FLAKE_DIRS[@]} -gt 0 ]]; then
      local sys_out sys_rc
      sys_out="$(nix eval --raw --impure --expr builtins.currentSystem 2>&1)"
      sys_rc=$?
      if [[ $sys_rc -ne 0 || -z "$sys_out" ]]; then
        handle_failure "PREFLIGHT" "nix eval builtins.currentSystem" "$sys_rc" "$sys_out"
      fi
      NIX_SYSTEM="$sys_out"

      local d contract_rc
      for d in "${AFFECTED_FLAKE_DIRS[@]}"; do
        check_flake_contract "$d" "$NIX_SYSTEM"
        contract_rc=$?
        case "$contract_rc" in
        0) FLAKE_CHECK_DIRS+=("$d") ;;
        1) missing_flake_checks+=("$d") ;;
        *) handle_failure "PREFLIGHT" "nix eval checks($d)" "$contract_rc" "$FLAKE_CONTRACT_OUTPUT" ;;
        esac
      done

      if [[ ${#missing_flake_checks[@]} -gt 0 ]]; then
        if [[ "$warn_missing_flake_checks" -eq 1 ]]; then
          print_warning "Missing checks.${NIX_SYSTEM}.agent-validate contract in ${#missing_flake_checks[@]} affected flake(s); continuing because --warn-missing-flake-checks was given:"
          for d in "${missing_flake_checks[@]}"; do
            print_warning "  ${d}: no checks.${NIX_SYSTEM}.agent-validate"
          done
          print_warning "Those flakes' aggregate checks are skipped; only the remaining checks run."
        else
          print_error "Missing checks.${NIX_SYSTEM}.agent-validate contract in ${#missing_flake_checks[@]} affected flake(s):"
          for d in "${missing_flake_checks[@]}"; do
            print_error "  ${d}: no checks.${NIX_SYSTEM}.agent-validate"
          done
          print_error "Add an agent-validate check to each of those flakes, or rerun with --warn-missing-flake-checks to continue without them."
          exit 24
        fi
      fi
    fi

    # --- FORMAT phase (mutating; reformatting itself is not a failure) -------

    eval "$(agent_format_emit_phase)"

    # --- LINT phase -----------------------------------------------------------

    eval "$(emit_lint_phase)"

    # --- BUILD/TEST phase -----------------------------------------------------

    eval "$(emit_build_test_phase)"

    # One aggregate per affected flake whose contract exists (see
    # FLAKE_CHECK_DIRS above); no generic `nix flake check` fallback.
    eval "$(emit_flake_build_phase)"
  fi

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
  paths_json="$(json_string_array "${selected_paths[@]+"${selected_paths[@]}"}")" || die_artifact "failed to build the paths JSON array"
  results_json="$(
    IFS=,
    echo "${RESULTS[*]+"${RESULTS[*]}"}"
  )"

  local missing_flake_json="[]"
  if [[ ${#missing_flake_checks[@]} -gt 0 ]]; then
    missing_flake_json="$(
      printf '%s\n' "${missing_flake_checks[@]}" |
        jq -R --arg check "checks.${NIX_SYSTEM}.agent-validate" '{flake: ., check: $check}' |
        jq -s -c .
    )" || die_artifact "failed to build the missing_flake_checks JSON array"
  fi

  local warn_json="false"
  [[ "$warn_missing_flake_checks" -eq 1 ]] && warn_json="true"

  {
    printf '{\n'
    printf '  "schema_version": 3,\n'
    printf '  "validator": "%s",\n' "$validator"
    printf '  "tree_sha": "%s",\n' "$tree_sha"
    printf '  "timestamp": "%s",\n' "$ts"
    printf '  "selection": "%s",\n' "$selection"
    printf '  "warn_missing_flake_checks": %s,\n' "$warn_json"
    printf '  "missing_flake_checks": %s,\n' "$missing_flake_json"
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
