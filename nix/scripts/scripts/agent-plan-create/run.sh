#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  agent-plan-create <target-dir> --context <text> --steps <text> --out-of-scope <text> \
                     [--style-guide <text>] [--notes <text>] [--force]
  agent-plan-create frontmatter <agent-file.md> key=value [key=value ...]

Primary mode: renders and writes a `.AGENT-PLAN.md` file into <target-dir>.

  --context <text>        Required. Free text for the "Context" section.
  --steps <text>          Required. Free text for the "Steps" section.
  --out-of-scope <text>   Required. Free text for the "Out of scope" section.
  --style-guide <text>    Optional. Adds a "Style guide" section.
  --notes <text>          Optional. Adds a "Notes" section.
  --force                 Overwrite an existing .AGENT-PLAN.md at the target path.

Guardrails (not overridable):
  - Always writes exactly ".AGENT-PLAN.md" -- there is no filename flag.
  - Refuses to write outside the repository (detected by walking up from
    <target-dir> for a .git file or directory) the script is invoked within.
  - Refuses to overwrite an existing .AGENT-PLAN.md unless --force is given.

Secondary mode ("frontmatter"): merges key=value pairs into the YAML
frontmatter block of an existing agent .md file, leaving all other
frontmatter keys and the body untouched. Requires the "yq" (mikefarah/yq)
binary on PATH. Refuses to operate on non-.md files, and refuses to write
outside the detected repository. Does NOT compute or infer values -- every
key=value pair must be supplied explicitly by the caller.
EOF
}

# --- shared repo-root guardrail -------------------------------------------

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
    print_error "Refusing to write: '$target' is not inside a git repository (no .git found walking up from it)"
    exit 1
  fi

  case "$target" in
  "$repo_root" | "$repo_root"/*) ;;
  *)
    print_error "Refusing to write: '$target' resolved outside of detected repo root '$repo_root'"
    exit 1
    ;;
  esac

  printf '%s\n' "$repo_root"
}

# --- primary mode: create .AGENT-PLAN.md ----------------------------------

run_create() {
  local target_dir_arg=""
  local context="" steps="" out_of_scope="" style_guide="" notes=""
  local force=0

  if [[ $# -eq 0 ]]; then
    print_error "Missing required target directory argument"
    show_help
    exit 1
  fi

  target_dir_arg="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
    --force)
      force=1
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

  if [[ -z "$context" || -z "$steps" || -z "$out_of_scope" ]]; then
    print_error "--context, --steps, and --out-of-scope are all required"
    exit 1
  fi

  local target_dir
  target_dir="$(resolve_path "$target_dir_arg")"

  require_within_repo "$target_dir" >/dev/null

  local plan_path="$target_dir/.AGENT-PLAN.md"

  if [[ -e "$plan_path" && "$force" -ne 1 ]]; then
    print_error "'$plan_path' already exists; pass --force to overwrite it"
    exit 1
  fi

  mkdir -p "$target_dir"

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
  } >"$plan_path"

  print_status "Wrote $plan_path"
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
