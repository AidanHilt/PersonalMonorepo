#!/bin/bash

#include printing-and-output
#include agent-plan-classify

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  agent-plan-create --paths <list> --context <text> --steps <text> --out-of-scope <text> \
                     [--new-paths <list>] [--style-guide <text>] [--notes <text>] \
                     [--research <text>] [--tools <comma-list>]
  agent-plan-create frontmatter <agent-file.md> key=value [key=value ...] [--allow-bash <cmd>]

Primary mode: writes a self-contained IMPLEMENT-subagent plan file to
/tmp/pi-agent-plans/IMPLEMENT-<n>.md and prints ONLY that absolute path to
stdout (status/diagnostics, plus the slot number n on its own line, go to
stderr). The write is atomic (temporary file in the same directory, then
rename), so a reader never sees a half-written plan. /tmp is shared with
the subagent's isolated worktree, so the plan file is readable there even
though uncommitted repository files are not. Dispatch subagent_type
IMPLEMENT-n with a short prompt telling it to read the printed path before
doing anything else, e.g.:

  Read /tmp/pi-agent-plans/IMPLEMENT-<n>.md before doing anything else. It
  contains your complete implementation plan and validation command.

It also allocates a per-dispatch agent definition: it picks the first free
slot n in 1..MAX_SLOTS for which ${agents_dir}/IMPLEMENT-n.md does not
already exist (agents_dir resolves to
${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents), copies the global
${agents_dir}/IMPLEMENT.md template to ${agents_dir}/IMPLEMENT-n.md, and
grants that copy permission to run exactly one bash command: the
`agent-validate --path ...` invocation covering --paths/--new-paths, via an
exact-match permission.bash allow rule. If the plan file cannot be written
after a slot is allocated, that per-dispatch agent definition is removed
again so the slot is not leaked. `agent-stage --slot <n>` removes both the
agent definition and the plan file on a successful stage.

  --paths <list>           Required. Space- and/or comma-separated list of
                            files/directories that will be touched. Every
                            entry is resolved relative to the CURRENT
                            WORKING DIRECTORY (or used as-is if absolute),
                            NOT relative to the repo root, then converted
                            to a repo-relative path. It is a HARD ERROR
                            (exit non-zero, before any slot is allocated)
                            for a --paths entry to not exist on disk --
                            double-check your cwd if you hit this. Used to
                            pick the required tools and to build the
                            `agent-validate --path ...` command the
                            subagent is granted permission to run.
  --new-paths <list>       Optional. Same comma/space separated syntax as
                            --paths, also cwd-relative or absolute: paths
                            the dispatched subagent is expected to CREATE,
                            so they are not required to exist yet. They
                            skip --paths' existence check, are converted to
                            repo-relative paths the same way, and are
                            appended to the generated `agent-validate
                            --path ...` command. --paths is still required;
                            --new-paths alone is not sufficient to dispatch.
  --context <text>         Required. Free text for the "Context" section.
  --steps <text>           Required. Free text for the "Steps" section.
  --out-of-scope <text>    Required. Free text for the "Out of scope" section.
  --style-guide <text>     Optional. Adds a "Style guide" section.
  --notes <text>           Optional. Adds a "Notes" section.
  --research <text>        Optional. Adds a "Research" section.
  --tools <comma-list>     Optional. Extra tool names (besides the ones
                            inferred from --paths/--new-paths) required on
                            PATH.

Required-tools handling: the tool list is computed from the file-type
profiles detected in --paths, plus --tools. Every tool is checked with
`command -v` in THIS environment (the one the subagent worktree will
share). If any are missing, they are printed to stderr as a list and the
command exits non-zero WITHOUT writing a plan file or allocating a slot --
ask the user to add them to nix/mono-flake (host system packages) and run
update, then retry.

Unlike the old generated-validate.sh flow, `agent-validate` discovers its
checks AT RUN TIME when the subagent runs it (re-classifying --paths,
including directories, from scratch), so files the subagent creates during
the work are covered too -- not just the files/dirs that existed at
dispatch time.

Secondary mode ("frontmatter"): merges key=value pairs into the YAML
frontmatter block of an existing agent .md file, leaving all other
frontmatter keys and the body untouched, and/or grants an exact-match bash
allow rule via `--allow-bash <cmd>` (sets
`.permission.bash["<cmd>"] = "allow"`, written as a single-line
double-quoted mapping key so the pi permission system can parse it -- see
the --allow-bash case in run_frontmatter for why). Requires the "yq"
(mikefarah/yq) binary on PATH. Refuses to operate on non-.md files. Refuses to write
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
  local dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents"
  local resolved

  # cd -P / pwd -P follow symlinks (e.g. /var -> /private/var) physically.
  if resolved=$(cd -P -- "$dir" 2>/dev/null && pwd -P); then
    printf '%s\n' "$resolved"
  elif resolved=$(cd -P -- "${dir%/agents}" 2>/dev/null && pwd -P); then
    # agents/ doesn't exist yet: resolve the parent and append.
    printf '%s/agents\n' "$resolved"
  else
    printf '%s\n' "$dir"
  fi
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

# --- primary mode: build the plan file ----------------------------------

run_create() {
  local paths="" new_paths="" context="" steps="" out_of_scope="" style_guide="" notes=""
  local research="" extra_tools=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --paths)
      paths="$2"
      shift 2
      ;;
    --new-paths)
      new_paths="$2"
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

  # --paths entries are resolved relative to the CURRENT WORKING DIRECTORY
  # (or taken as-is if absolute) -- see resolve_path -- NOT relative to the
  # repo root. A planner invoking this from somewhere other than the repo
  # root can easily pass a path that doesn't actually exist once resolved;
  # that used to only produce a classify_paths "not found on disk" warning,
  # which let a broken agent-validate command get generated and dispatched
  # anyway. Treat it as a hard error instead, before anything (including a
  # dispatch slot) gets allocated.
  local missing_paths=() normalized_paths p resolved
  normalized_paths="${paths//,/ }"
  for p in $normalized_paths; do
    [[ -z "$p" ]] && continue
    resolved="$(resolve_path "$p")"
    [[ -e "$resolved" ]] || missing_paths+=("$p" "(resolved to $resolved)")
  done
  if [[ ${#missing_paths[@]} -gt 0 ]]; then
    print_error "The following --paths entries do not exist on disk: ${missing_paths[*]}"
    print_error "--paths entries are resolved relative to the current working directory (or used as-is if absolute), not relative to the repo root -- double-check your cwd, or use --new-paths for paths the subagent is expected to create."
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
    print_error "Ask the user to add ${missing[*]} to nix/mono-flake (host system packages) and run update, then retry."
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

  # --new-paths: files/dirs the subagent is expected to CREATE, so they are
  # not required to exist yet (unlike --paths above) and are never run
  # through classify_paths/UNKNOWN_PATHS -- there's nothing on disk yet for
  # it to classify. They're still resolved cwd-relative (or absolute) and
  # converted to repo-relative the same way, then appended to the
  # agent-validate --path arguments so agent-validate's own runtime
  # re-classification (which happens once the subagent has actually created
  # the files) picks them up.
  if [[ -n "$new_paths" ]]; then
    local normalized_new
    normalized_new="${new_paths//,/ }"
    for p in $normalized_new; do
      [[ -z "$p" ]] && continue
      resolved="$(resolve_path "$p")"
      rel="$(realpath -m --relative-to="$repo_root" -- "$resolved")"
      array_contains "$rel" "${ordered_paths[@]+"${ordered_paths[@]}"}" || ordered_paths+=("$rel")
    done
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

  # MAX_SLOTS must stay in sync with the worktreeAgents list in
  # nix/agentic-ai-stack/config/agent/subagents-worktrees.json (updated in
  # a separate, parallel dispatch) -- that's what actually gives each of
  # IMPLEMENT-1..IMPLEMENT-MAX_SLOTS its own isolated worktree.
  local MAX_SLOTS=10
  local slot="" n per_dispatch_file
  for ((n = 1; n <= MAX_SLOTS; n++)); do
    if [[ ! -e "$agents_dir/IMPLEMENT-$n.md" ]]; then
      slot="$n"
      break
    fi
  done

  if [[ -z "$slot" ]]; then
    print_error "All dispatch slots (IMPLEMENT-1..IMPLEMENT-$MAX_SLOTS) are taken. Wait for one to finish (its agent file and plan file are removed on completion by 'agent-stage --slot <n>'), or clean up a stale ${agents_dir}/IMPLEMENT-<n>.md yourself, then retry."
    exit 1
  fi

  per_dispatch_file="$agents_dir/IMPLEMENT-$slot.md"
  cp -- "$template" "$per_dispatch_file"

  run_frontmatter "$per_dispatch_file" --allow-bash "$validate_cmd"

  print_status "Allocated dispatch slot IMPLEMENT-$slot ($per_dispatch_file)"
  printf '%s\n' "$slot" >&2

  # --- write the plan file ---------------------------------------------------

  # The complete plan goes to a fixed, shared path under /tmp (visible from
  # the subagent's isolated worktree, unlike uncommitted repo files). Only
  # that path is printed to stdout, so the dispatch prompt itself stays
  # short. Written to a temp file in the same directory and then renamed, so
  # a reader never sees a partially written plan.
  local plan_dir="/tmp/pi-agent-plans"
  local plan_file="$plan_dir/IMPLEMENT-$slot.md"
  local plan_tmp=""

  # Failing after the slot is allocated must not leak the slot: drop the
  # per-dispatch agent definition we just created and any partial plan file.
  abort_plan_write() {
    print_error "Failed to write plan file '$plan_file': $1"
    print_error "Releasing dispatch slot IMPLEMENT-$slot (removing '$per_dispatch_file'); nothing was dispatched."
    rm -f -- "$per_dispatch_file"
    if [[ -n "$plan_tmp" ]]; then
      rm -f -- "$plan_tmp"
    fi
    exit 1
  }

  if ! mkdir -p -- "$plan_dir"; then
    abort_plan_write "could not create '$plan_dir'"
  fi

  if ! plan_tmp="$(mktemp "$plan_dir/.IMPLEMENT-$slot.XXXXXX")"; then
    abort_plan_write "could not create a temporary file in '$plan_dir'"
  fi

  if ! {
    printf '# Plan\n\n'
    printf '## Dispatch\n\n'
    # shellcheck disable=SC2016
    printf -- 'You are subagent_type `IMPLEMENT-%s`. Your dispatcher sent a short prompt\n' "$slot"
    printf 'pointing at this file: read it in full before doing anything else. It IS\n'
    printf 'your complete plan.\n\n'
    printf 'That dispatch already granted you permission to run exactly one bash\n'
    printf 'command -- the following, and no other -- as your only validation step:\n\n'
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
    printf 'Network access from the sandbox is mediated by the user'"'"'s interactive\n'
    printf 'approval prompts (nono approval). You cannot pre-grant domains yourself; if\n'
    printf 'you hit a network need, expect an approval prompt, or stop and report it if\n'
    printf 'denied.\n'

    printf '\n## Definition of Done\n\n'
    printf -- '- The plan above is implemented.\n'
    # shellcheck disable=SC2016
    printf -- '- `%s` (the exact command above, run verbatim) exits 0 and `.agent/validated.json` exists.\n' "$validate_cmd"
    # shellcheck disable=SC2016
    printf -- '- Your final report includes the exit code of the last `agent-validate` run, the failure count, and whether the artifact was written.\n'
  } >"$plan_tmp"; then
    abort_plan_write "writing to '$plan_tmp' failed"
  fi

  if ! mv -f -- "$plan_tmp" "$plan_file"; then
    abort_plan_write "could not move '$plan_tmp' into place"
  fi

  print_status "Plan written to $plan_file (slot IMPLEMENT-$slot)"
  print_status "Dispatch subagent_type IMPLEMENT-$slot with a short prompt telling it to read that file before doing anything else."
  printf '%s\n' "$plan_file"
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

  echo "$agents_dir"

  case "$agent_file" in
  "$agents_dir"/*) ;; # Inside the per-dispatch agents dir: not part of any
  # repo (it's the tmpfs ~/.pi/agent/agents tree), so the
  # within-repo guard doesn't apply here.
  *)
    require_within_repo "$(dirname "$agent_file")"
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

  local kv key value cmd escaped_cmd allow_bash_set=""
  local placeholder_key='__AGENT_PLAN_ALLOW_PLACEHOLDER__'
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --allow-bash)
      if [[ $# -lt 2 ]]; then
        print_error "--allow-bash requires a value"
        exit 1
      fi
      cmd="$2"
      print_debug "Allowing bash command '$cmd'"

      # go-yaml's emitter (mikefarah/yq v4) switches to YAML's explicit-key
      # form ('? key' / ': allow') for any mapping key longer than 128
      # chars, which the pi permission system does not parse, silently
      # falling through to deny. agent-validate's --path ... invocation is
      # routinely longer than that, so we can't let yq write the long key
      # directly: set a short placeholder key instead (short keys keep
      # yq's plain one-line form), then hand-rewrite that one line into a
      # single-line double-quoted key via awk, with the real command value
      # passed through the environment (never interpolated into the awk
      # program text).
      echo "YQ COMMAND: yq eval -i .permission.bash[\"${placeholder_key}\"] = \"allow\" \"$frontmatter_file\"" >/tmp/command-out.txt
      yq eval -i ".permission.bash[\"${placeholder_key}\"] = \"allow\"" "$frontmatter_file"

      if ! grep -q -F -- "$placeholder_key" "$frontmatter_file"; then
        print_error "Internal error: placeholder key '$placeholder_key' not found in '$frontmatter_file' after yq merge"
        exit 1
      fi

      # Escape backslash then double-quote for a YAML double-quoted scalar.
      escaped_cmd="${cmd//\\/\\\\}"
      escaped_cmd="${escaped_cmd//\"/\\\"}"

      PLACEHOLDER="$placeholder_key" ESCAPED_CMD="$escaped_cmd" awk '
        index($0, ENVIRON["PLACEHOLDER"]) {
          match($0, /^[ \t]*/)
          indent = substr($0, RSTART, RLENGTH)
          print indent "\"" ENVIRON["ESCAPED_CMD"] "\": allow"
          next
        }
        { print }
      ' "$frontmatter_file" >"$frontmatter_file.tmp"
      mv "$frontmatter_file.tmp" "$frontmatter_file"

      allow_bash_set=1
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

  if [[ -n "$allow_bash_set" ]]; then
    local expected_allow_line="\"${escaped_cmd}\": allow"
    if ! grep -q -F -- "$expected_allow_line" "$frontmatter_file"; then
      print_error "Internal error: expected allow rule line not found in '$frontmatter_file' after merge"
      exit 1
    fi
    if grep -q '^[[:space:]]*? ' "$frontmatter_file"; then
      print_error "Internal error: '$frontmatter_file' contains a YAML explicit-key ('? ') line after merge -- the allow rule would not be parsed by the permission system"
      exit 1
    fi
  fi

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
