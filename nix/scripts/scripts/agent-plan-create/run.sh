#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  agent-plan-create --paths <list> --context <text> --steps <text> --out-of-scope <text> \
                     [--style-guide <text>] [--notes <text>] [--research <text>] \
                     [--domains <comma-list>] [--tools <comma-list>]
  agent-plan-create frontmatter <agent-file.md> key=value [key=value ...]

Primary mode: assembles a self-contained IMPLEMENT-subagent dispatch prompt
and prints it to stdout (status/diagnostics go to stderr). It writes no
files. Pass the stdout of this command as the subagent's dispatch prompt.

  --paths <list>           Required. Space- and/or comma-separated list of
                            files/directories that will be touched. Used to
                            pick which validate.sh checks are generated and
                            to scope them to the relevant paths.
  --context <text>         Required. Free text for the "Context" section.
  --steps <text>           Required. Free text for the "Steps" section.
  --out-of-scope <text>    Required. Free text for the "Out of scope" section.
  --style-guide <text>     Optional. Adds a "Style guide" section.
  --notes <text>           Optional. Adds a "Notes" section.
  --research <text>        Optional. Adds a "Research" section.
  --domains <comma-list>   Optional. Network domains already granted (via
                            request-domain) by the main agent before
                            dispatch. Recorded in the prompt; the subagent
                            must not request additional domains itself.
  --tools <comma-list>     Optional. Extra tool names (besides the ones
                            inferred from --paths) required on PATH.

Required-tools handling: the tool list is computed from the file-type
profiles detected in --paths, plus --tools. Every tool is checked with
`command -v` in THIS environment (the one the subagent worktree will
share). If any are missing, they are printed to stderr as a list and the
command exits non-zero WITHOUT printing a prompt -- install them with
pkg-install and retry.

The prompt embeds a generated validate.sh verbatim in a fenced block. The
subagent must write it byte-for-byte to ./validate.sh (no edits, no added
or removed checks) and run it as `bash ./validate.sh`. The sha256 of the
generated validate.sh is printed to stderr and also stated inside the
prompt, so the main agent can later pass it to `agent-stage --expect-sha`.

Secondary mode ("frontmatter"): merges key=value pairs into the YAML
frontmatter block of an existing agent .md file, leaving all other
frontmatter keys and the body untouched. Requires the "yq" (mikefarah/yq)
binary on PATH. Refuses to operate on non-.md files, and refuses to write
outside the detected repository. Does NOT compute or infer values -- every
key=value pair must be supplied explicitly by the caller.
EOF
}

# --- shared repo-root guardrail (frontmatter mode only still writes) -----

# Walks up from a starting path looking for a `.git` entry (directory or,
# for worktrees, a file). Prints the repo root and returns 0 on success;
# returns 1 if none was found by the time it reaches `/`.
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
resolve_path() {
  realpath -m -- "$1"
}

require_within_repo() {
  local target="$1"
  local repo_root

  if ! repo_root="$(find_repo_root "$target")"; then
    print_error "'$target' is not inside a git repository (no .git found walking up from it)"
    exit 1
  fi

  case "$target" in
  "$repo_root" | "$repo_root"/*) ;;
  *)
    print_error "'$target' resolved outside of detected repo root '$repo_root'"
    exit 1
    ;;
  esac

  printf '%s\n' "$repo_root"
}

# --- path classification ---------------------------------------------------
#
# Splits --paths on commas and whitespace, resolves each entry, and sorts
# it into profile buckets by file type. These buckets drive both the
# required-tool list and the concrete, path-scoped commands embedded in the
# generated validate.sh.

BASH_FILES=()
GO_MODULE_DIRS=()
YAML_FILES=()
HELM_CHART_DIRS=()
NIX_FILES=()
NIX_FLAKE_DIRS=()
TF_DIRS=()
DOCKERFILES=()
UNKNOWN_PATHS=()

# Walks upward from a starting directory looking for a marker file
# (go.mod / flake.nix), bounded at the repo root. Prints the directory
# containing the marker, or nothing if not found.
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

array_contains() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

add_unique() {
  # add_unique <array-name> <value>
  local -n arr="$1"
  local val="$2"
  array_contains "$val" "${arr[@]+"${arr[@]}"}" || arr+=("$val")
}

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

relativize_array() {
  local -n _rel_arr="$1"
  local repo_root="$2" i
  for i in "${!_rel_arr[@]}"; do
    _rel_arr[i]="$(realpath -m --relative-to="$repo_root" -- "${_rel_arr[i]}")"
  done
}

relativize_paths() {
  local repo_root="$1" name
  for name in BASH_FILES GO_MODULE_DIRS YAML_FILES HELM_CHART_DIRS NIX_FILES NIX_FLAKE_DIRS TF_DIRS DOCKERFILES; do
    relativize_array "$name" "$repo_root"
  done
}

# --- required tool computation ---------------------------------------------

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

# --- validate.sh generation --------------------------------------------------
#
# Emits a concrete, path-scoped validate.sh: every command below is a
# literal invocation over the specific files/dirs classify_paths found, not
# a runtime re-scan. Phases run in a fixed global order: all FORMAT checks
# across every profile, then all LINT checks, then all BUILD/TEST checks.

quote_list() {                                                                                                                                                              
  # Shell-quotes each argument and joins them with single spaces, with no                                                                                                   
  # trailing space (trailing whitespace does not survive prompt transport).                                                                                                 
  local out="" x                                                                                                                                                            
  for x in "$@"; do                                                                                                                                                         
    out+="$(printf '%q' "$x") "                                                                                                                                             
  done                                                                                                                                                                      
  printf '%s' "${out% }"                                                                                                                                                    
}  

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
    printf 'run_check LINT "statix check" statix check %s\n' "$(quote_list "${NIX_FILES[@]}")"
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

any_checks_emitted() {
  [[ ${#BASH_FILES[@]} -gt 0 || ${#GO_MODULE_DIRS[@]} -gt 0 || ${#YAML_FILES[@]} -gt 0 ||
    ${#HELM_CHART_DIRS[@]} -gt 0 || ${#NIX_FILES[@]} -gt 0 || ${#NIX_FLAKE_DIRS[@]} -gt 0 ||
    ${#TF_DIRS[@]} -gt 0 || ${#DOCKERFILES[@]} -gt 0 ]]
}

generate_validate_script() {
  local required_tools_str="$1"

  cat <<'VALIDATE_HEADER'
#!/bin/bash
# Generated by agent-plan-create. Do not hand-edit; regenerate the plan
# prompt instead if checks need to change.
set -uo pipefail

FAILURE_BUDGET=10
ARTIFACT=".agent/validated.json"
RESULTS=()

git_dir() { git rev-parse --git-dir 2>/dev/null; }

failcount_file() {
  local gd
  gd="$(git_dir)" || { printf '%s\n' "/tmp/.pi-validate-failcount"; return; }
  printf '%s/pi-validate-failcount\n' "$gd"
}

read_failcount() {
  local f
  f="$(failcount_file)"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    printf '0\n'
  fi
}

write_failcount() {
  local f
  f="$(failcount_file)"
  printf '%s\n' "$1" >"$f"
}

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

print_tail() {
  printf '%s\n' "$1" | tail -n 40
}

record_pass() {
  RESULTS+=("{\"phase\":\"$1\",\"check\":\"$2\",\"status\":\"pass\"}")
}

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

VALIDATE_HEADER

  printf '\n# --- required tools ---------------------------------------------------------\n\n'
  printf 'REQUIRED_TOOLS=(\n'
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    printf '  %q\n' "$t"
  done <<<"$required_tools_str"
  printf ')\n'

  cat <<'VALIDATE_BODY'

missing=()
for t in "${REQUIRED_TOOLS[@]}"; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Missing required tools: %s\n' "${missing[*]}" >&2
  exit 20
fi

# --- failure budget check (before doing any work) ---------------------------

current_failcount="$(read_failcount)"
if [[ "$current_failcount" -ge "$FAILURE_BUDGET" ]]; then
  printf 'Failure budget (%s) already exhausted from prior runs.\n' "$FAILURE_BUDGET" >&2
  exit 99
fi

rm -f "$ARTIFACT"

# --- tree_sha helper (excludes .agent/ and validate.sh) ---------------------

compute_tree_sha() {
  local tmp_index
  tmp_index="$(mktemp -u)"
  # Seed from HEAD so tracked-but-gitignored files (e.g. .secrets.baseline)
  # are kept, matching what the worktree commit records.
  GIT_INDEX_FILE="$tmp_index" git read-tree HEAD >/dev/null 2>&1 || true
  GIT_INDEX_FILE="$tmp_index" git add -A -- :/ >/dev/null 2>&1 || true
  GIT_INDEX_FILE="$tmp_index" git rm -r --cached --ignore-unmatch -q .agent validate.sh >/dev/null 2>&1 || true
  GIT_INDEX_FILE="$tmp_index" git write-tree 2>/dev/null
  local rc=$?
  rm -f "$tmp_index"
  return $rc
}

VALIDATE_BODY
  cd "$(git rev-parse --show-toplevel)" || {
    printf 'Not inside a git work tree\n' >&2
    exit 20
  }

  printf '\n# --- FORMAT phase (mutating; reformatting itself is not a failure) --------\n\n'
  emit_format_phase

  printf '\n# --- LINT phase --------------------------------------------------------------\n\n'
  emit_lint_phase

  printf '\n# --- BUILD/TEST phase ---------------------------------------------------------\n\n'
  emit_build_test_phase

  cat <<'VALIDATE_FOOTER'

# --- all phases passed: write the artifact ----------------------------------

mkdir -p .agent
validate_sha="$(sha256sum validate.sh 2>/dev/null | cut -d' ' -f1)"
tree_sha="$(compute_tree_sha || echo "unknown")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tool_versions="{}"
if command -v jq >/dev/null 2>&1; then
  tool_versions_obj="{}"
  for t in "${REQUIRED_TOOLS[@]}"; do
    v="$("$t" --version 2>&1 | head -1 || true)"
    tool_versions_obj="$(printf '%s' "$tool_versions_obj" | jq --arg k "$t" --arg v "$v" '. + {($k): $v}')"
  done
  tool_versions="$tool_versions_obj"
fi

{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "validate_sh_sha256": "%s",\n' "$validate_sha"
  printf '  "tree_sha": "%s",\n' "$tree_sha"
  printf '  "timestamp": "%s",\n' "$ts"
  printf '  "results": [%s],\n' "$(IFS=,; echo "${RESULTS[*]+"${RESULTS[*]}"}")"
  printf '  "tool_versions": %s\n' "$tool_versions"
  printf '}\n'
} >"$ARTIFACT"

printf 'All checks passed. Wrote %s\n' "$ARTIFACT"
write_failcount 0
exit 0
VALIDATE_FOOTER
}

# --- primary mode: assemble dispatch prompt ---------------------------------

run_create() {
  local paths="" context="" steps="" out_of_scope="" style_guide="" notes=""
  local research="" domains="" extra_tools=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --paths)
      paths="$2"
      shift 2
      ;;
    --context)
      context="$2"
      shift 2
      ;;
    --steps)
      steps="$2"
      shift 2
      ;;
    --out-of-scope)
      out_of_scope="$2"
      shift 2
      ;;
    --style-guide)
      style_guide="$2"
      shift 2
      ;;
    --notes)
      notes="$2"
      shift 2
      ;;
    --research)
      research="$2"
      shift 2
      ;;
    --domains)
      domains="$2"
      shift 2
      ;;
    --tools)
      extra_tools="$2"
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

  if [[ -z "$paths" || -z "$context" || -z "$steps" || -z "$out_of_scope" ]]; then
    print_error "--paths, --context, --steps, and --out-of-scope are all required"
    exit 1
  fi

  local repo_root
  if ! repo_root="$(find_repo_root "$(pwd)")"; then
    print_error "Current directory is not inside a git repository (no .git found walking up)"
    exit 1
  fi

  classify_paths "$paths" "$repo_root"
  relativize_paths "$repo_root"

  if [[ ${#UNKNOWN_PATHS[@]} -gt 0 ]]; then
    print_warning "No checks generated for: ${UNKNOWN_PATHS[*]}"
  fi

  if ! any_checks_emitted; then
    print_warning "No recognized file types in --paths; validate.sh will have no checks beyond the artifact write."
  fi

  local tools_list extra_list all_tools=()
  mapfile -t tools_list < <(required_tools_for_profiles)
  if [[ -n "$extra_tools" ]]; then
    IFS=',' read -r -a extra_list <<<"${extra_tools// /,}"
  else
    extra_list=()
  fi
  local t
  for t in "${tools_list[@]+"${tools_list[@]}"}" "${extra_list[@]+"${extra_list[@]}"}"; do
    [[ -z "$t" ]] && continue
    array_contains "$t" "${all_tools[@]+"${all_tools[@]}"}" || all_tools+=("$t")
  done

  local missing=()
  for t in "${all_tools[@]+"${all_tools[@]}"}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    print_error "Missing required tools on PATH: ${missing[*]}"
    print_error "Install them with pkg-install before dispatching, then retry."
    exit 1
  fi

  local required_tools_str
  required_tools_str="$(printf '%s\n' "${all_tools[@]+"${all_tools[@]}"}")"

  local validate_script
  validate_script="$(generate_validate_script "$required_tools_str")"

  local validate_sha
  validate_sha="$(printf '%s' "$validate_script" | sha256sum | cut -d' ' -f1)"

  print_status "Generated validate.sh (sha256: $validate_sha)"
  print_status "Required tools: ${all_tools[*]+"${all_tools[*]}"}"

  # --- assemble the prompt ---------------------------------------------------

  {
    printf '# Plan\n\n'
    printf '## Context\n\n%s\n\n' "$context"
    printf '## Steps\n\n%s\n\n' "$steps"
    if [[ -n "$style_guide" ]]; then
      printf '## Style guide\n\n%s\n\n' "$style_guide"
    fi
    printf '## Out of scope\n\n%s\n' "$out_of_scope"
    if [[ -n "$notes" ]]; then
      printf '\n## Notes\n\n%s\n' "$notes"
    fi
    if [[ -n "$research" ]]; then
      printf '\n## Research\n\n%s\n' "$research"
    fi

    printf '\n## Network\n\n'
    if [[ -n "$domains" ]]; then
      printf 'The following domains have already been granted via request-domain by the main agent: %s.\n' "$domains"
    else
      printf 'No additional network domains have been granted for this task.\n'
    fi
    printf 'You may not request additional domains yourself (request-domain is not available to you); if you hit a network need beyond this, stop and report it instead.\n'

    printf '\n## Definition of Done\n\n'
    printf -- '- The plan above is implemented.\n'
    # shellcheck disable=SC2016
    printf -- '- `./validate.sh` (written byte-for-byte from the fenced block below) exits 0 and `.agent/validated.json` exists.\n'
    # shellcheck disable=SC2016
    printf -- '- Your final report includes the exit code of the last `validate.sh` run, the failure count, and whether the artifact was written.\n'

    printf '\n## validate.sh\n\n'
    # shellcheck disable=SC2016
    printf 'Write the following script byte-for-byte to `./validate.sh` (do not edit it, do not add or remove checks), then run it as `bash ./validate.sh`. It is the only command you may run in bash.\n\n'
    # shellcheck disable=SC2016
    printf 'Expected sha256 of validate.sh once written: `%s`\n\n' "$validate_sha"
    # shellcheck disable=SC2016
    printf '```bash\n%s\n```\n' "$validate_script"
  }

  print_status "Prompt assembled. Pass this script's stdout as the subagent dispatch prompt."
}

# --- secondary mode: frontmatter merge ------------------------------------

run_frontmatter() {
  if [[ $# -lt 2 ]]; then
    print_error "Usage: agent-plan-create frontmatter <agent-file.md> key=value [key=value ...]"
    exit 1
  fi

  local agent_file_arg="$1"
  shift

  if ! command -v yq >/dev/null 2>&1; then
    print_error "'yq' (mikefarah/yq) is required on PATH for frontmatter merging but was not found"
    exit 1
  fi

  case "$agent_file_arg" in
  *.md) ;;
  *)
    print_error "Refusing to operate on '$agent_file_arg': not a .md file"
    exit 1
    ;;
  esac

  local agent_file
  agent_file="$(resolve_path "$agent_file_arg")"

  if [[ ! -f "$agent_file" ]]; then
    print_error "'$agent_file' does not exist"
    exit 1
  fi

  require_within_repo "$(dirname "$agent_file")" >/dev/null

  # Locate the frontmatter delimiters: line 1 must be exactly "---", and
  # the next bare "---" line closes the block.
  local first_line
  first_line="$(sed -n '1p' "$agent_file")"
  if [[ "$first_line" != "---" ]]; then
    print_error "'$agent_file' does not start with a '---' frontmatter delimiter"
    exit 1
  fi

  local end_line
  end_line="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$agent_file")"
  if [[ -z "$end_line" ]]; then
    print_error "'$agent_file' has no closing '---' frontmatter delimiter"
    exit 1
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local frontmatter_file="$tmp_dir/frontmatter.yaml"
  local body_file="$tmp_dir/body.md"

  sed -n "2,$((end_line - 1))p" "$agent_file" >"$frontmatter_file"
  sed -n "$((end_line + 1)),\$p" "$agent_file" >"$body_file"

  local kv key value
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      print_error "Invalid key=value pair: '$kv'"
      exit 1
    fi
    key="${kv%%=*}"
    value="${kv#*=}"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
      print_error "Invalid frontmatter key: '$key'"
      exit 1
    fi

    print_debug "Setting frontmatter key '$key'"
    VALUE="$value" yq eval -i ".${key} = strenv(VALUE)" "$frontmatter_file"
  done

  {
    printf -- '---\n'
    cat "$frontmatter_file"
    printf -- '---\n'
    cat "$body_file"
  } >"$tmp_dir/merged.md"

  mv "$tmp_dir/merged.md" "$agent_file"

  print_status "Merged frontmatter into $agent_file"
}

# --- entry point -----------------------------------------------------------

if [[ $# -eq 0 ]]; then
  print_error "Missing arguments"
  show_help
  exit 1
fi

case "$1" in
--help | -h)
  show_help
  exit 0
  ;;
frontmatter)
  shift
  run_frontmatter "$@"
  ;;
*)
  run_create "$@"
  ;;
esac
