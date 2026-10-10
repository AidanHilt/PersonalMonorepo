#!/bin/bash

# @lib: printing-and-output
# @lib: agent-plan-classify

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  agent-plan-create --paths <list> --context <text> --steps <text> --out-of-scope <text> \
                     [--style-guide <text>] [--notes <text>] [--research <text>] \
                     [--domains <comma-list>] [--tools <comma-list>]
  agent-plan-create frontmatter <agent-file.md> key=value [key=value ...] [--allow-bash <cmd>]

Primary mode: assembles a self-contained IMPLEMENT-subagent dispatch prompt
and prints it to stdout (status/diagnostics go to stderr). It writes no
plan files, but it DOES allocate a per-dispatch agent definition: it picks
the first free slot n in 1..4 for which
${agents_dir}/IMPLEMENT-n.md does not already exist (agents_dir resolves to
${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents), copies the global
${agents_dir}/IMPLEMENT.md template to ${agents_dir}/IMPLEMENT-n.md, and
grants that copy permission to run exactly one bash command: the
`agent-validate --path ...` invocation covering --paths, via an exact-match
permission.bash allow rule. Pass the printed prompt as the dispatch prompt
for subagent_type IMPLEMENT-n (stated in the prompt itself); the slot
number is also printed to stderr on its own line.

  --paths <list>           Required. Space- and/or comma-separated list of
                            files/directories that will be touched. Used to
                            pick the required tools and to build the
                            `agent-validate --path ...` command the
                            subagent is granted permission to run.
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
command exits non-zero WITHOUT printing a prompt or allocating a slot --
install them with pkg-install and retry.

Unlike the old generated-validate.sh flow, `agent-validate` discovers its
checks AT RUN TIME when the subagent runs it (re-classifying --paths,
including directories, from scratch), so files the subagent creates during
the work are covered too -- not just the files/dirs that existed at
dispatch time.

Secondary mode ("frontmatter"): merges key=value pairs into the YAML
frontmatter block of an existing agent .md file, leaving all other
frontmatter keys and the body untouched, and/or grants an exact-match bash
allow rule via `--allow-bash <cmd>` (sets
`.permission.bash["<cmd>"] = "allow"`). Requires the "yq" (mikefarah/yq)
binary on PATH. Refuses to operate on non-.md files. Refuses to write
outside the detected repository UNLESS the target file is inside the
resolved agents_dir (${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents) --
that tmpfs directory holds the per-dispatch agent definitions this script's
primary mode writes, and is never part of the repo. Does NOT compute or
infer key=value values -- every pair must be supplied explicitly by the
caller.
EOF
}

# --- shared repo-root guardrail (frontmatter mode only still writes) -----

resolve_agents_dir() {
  printf '%s/agents\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
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
    print_warning "No recognized file types in --paths; agent-validate will have no checks beyond the artifact write."
  fi

  local tools_list extra_list all_tools=()
  mapfile -t tools_list < <(required_tools_for_profiles)
  if [[ -n "$extra_tools" ]]; then
    IFS=',' read -r -a extra_list <<<"${extra_tools// /,}"
  else
    extra_list=()
  fi
  # Baseline tools agent-validate itself always relies on (failcount/artifact
  # bookkeeping, tree_sha computation, tool-version reporting), plus yq
  # (needed below to write the per-dispatch agent definition), regardless
  # of which file-type profiles were detected in --paths.
  local baseline_tools=(git jq yq sha256sum cut head tail grep mktemp date cat)
  local t
  for t in "${tools_list[@]+"${tools_list[@]}"}" "${extra_list[@]+"${extra_list[@]}"}" "${baseline_tools[@]}"; do
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

  print_status "Required tools: ${all_tools[*]+"${all_tools[*]}"}"

  # --- build the ordered, repo-relative --path arguments for agent-validate --

  local ordered_paths=() normalized p resolved rel
  normalized="${paths//,/ }"
  for p in $normalized; do
    [[ -z "$p" ]] && continue
    resolved="$(resolve_path "$p")"
    rel="$(realpath -m --relative-to="$repo_root" -- "$resolved")"
    ordered_paths+=("$rel")
  done

  if [[ ${#ordered_paths[@]} -eq 0 ]]; then
    print_error "No usable entries found in --paths"
    exit 1
  fi

  local validate_cmd="agent-validate"
  for p in "${ordered_paths[@]}"; do
    validate_cmd+=" --path $(printf '%q' "$p")"
  done

  # --- allocate a dispatch slot and grant it the exact-match allow rule -----

  local agents_dir
  agents_dir="$(resolve_agents_dir)"

  local template="$agents_dir/IMPLEMENT.md"
  if [[ ! -f "$template" ]]; then
    print_error "Template '$template' not found; cannot allocate a dispatch slot"
    exit 1
  fi

  local slot="" n per_dispatch_file
  for n in 1 2 3 4; do
    if [[ ! -e "$agents_dir/IMPLEMENT-$n.md" ]]; then
      slot="$n"
      break
    fi
  done

  if [[ -z "$slot" ]]; then
    print_error "All dispatch slots (IMPLEMENT-1..IMPLEMENT-4) are taken. Wait for one to finish (its agent file is removed on completion by 'agent-stage --slot <n>'), or clean up a stale ${agents_dir}/IMPLEMENT-<n>.md yourself, then retry."
    exit 1
  fi

  per_dispatch_file="$agents_dir/IMPLEMENT-$slot.md"
  cp -- "$template" "$per_dispatch_file"

  run_frontmatter "$per_dispatch_file" --allow-bash "$validate_cmd"

  print_status "Allocated dispatch slot IMPLEMENT-$slot ($per_dispatch_file)"
  printf '%s\n' "$slot" >&2

  # --- assemble the prompt ---------------------------------------------------

  {
    printf '# Plan\n\n'
    printf '## Dispatch\n\n'
    # shellcheck disable=SC2016
    printf -- 'Dispatch this prompt to subagent_type `IMPLEMENT-%s`. That subagent has\n' "$slot"
    printf 'already been granted permission to run exactly one bash command -- the\n'
    printf 'following, and no other -- as its only validation step:\n\n'
    # shellcheck disable=SC2016
    printf '```\n%s\n```\n\n' "$validate_cmd"
    # shellcheck disable=SC2016
    printf 'Run it verbatim from the repo root. It discovers its checks at run time\n'
    printf 'by re-classifying the --path arguments above (directories are re-expanded),\n'
    printf 'so files you create during the work are covered too.\n\n'
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
    printf -- '- `%s` (the exact command above, run verbatim) exits 0 and `.agent/validated.json` exists.\n' "$validate_cmd"
    # shellcheck disable=SC2016
    printf -- '- Your final report includes the exit code of the last `agent-validate` run, the failure count, and whether the artifact was written.\n'
  }

  print_status "Prompt assembled for subagent_type IMPLEMENT-$slot. Pass this script's stdout as the subagent dispatch prompt."
}

# --- secondary mode: frontmatter merge ------------------------------------

run_frontmatter() {
  if [[ $# -lt 2 ]]; then
    print_error "Usage: agent-plan-create frontmatter <agent-file.md> key=value [key=value ...] [--allow-bash <cmd>]"
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

  local agents_dir
  agents_dir="$(resolve_agents_dir)"

  case "$agent_file" in
  "$agents_dir"/*) ;; # Inside the per-dispatch agents dir: not part of any
  # repo (it's the tmpfs ~/.pi/agent/agents tree), so the
  # within-repo guard doesn't apply here.
  *)
    require_within_repo "$(dirname "$agent_file")" >/dev/null
    ;;
  esac

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
  # shellcheck disable=SC2064 # intentional: expand tmp_dir now so cleanup
  # does not depend on the local variable's scope at EXIT time
  trap "rm -rf '$tmp_dir'" EXIT

  local frontmatter_file="$tmp_dir/frontmatter.yaml"
  local body_file="$tmp_dir/body.md"

  sed -n "2,$((end_line - 1))p" "$agent_file" >"$frontmatter_file"
  sed -n "$((end_line + 1)),\$p" "$agent_file" >"$body_file"

  local kv key value cmd
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --allow-bash)
      if [[ $# -lt 2 ]]; then
        print_error "--allow-bash requires a value"
        exit 1
      fi
      cmd="$2"
      print_debug "Allowing bash command '$cmd'"
      CMD="$cmd" yq eval -i '.permission.bash[strenv(CMD)] = "allow"' "$frontmatter_file"
      shift 2
      ;;
    *)
      kv="$1"
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
      shift
      ;;
    esac
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
