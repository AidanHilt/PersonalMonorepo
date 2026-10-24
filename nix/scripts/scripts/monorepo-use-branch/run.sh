#!/bin/bash

#include printing-and-output
#include args-and-help
#include env-checks

set -euo pipefail

# EXE_git, EXE_jq, EXE_nix are flake runtime-dependency placeholders (see
# nix/scripts/IMPLEMENTERS.md's "Runtime dependencies" section) substituted at build
# time. The declarations below keep shellcheck from flagging SC2154 without needing a
# disable directive.
: "${EXE_git:=}" # runtime-dependency placeholder, substituted at build time
: "${EXE_jq:=}"  # runtime-dependency placeholder, substituted at build time
: "${EXE_nix:=}" # runtime-dependency placeholder, substituted at build time
readonly GIT="${EXE_git}"
readonly JQ="${EXE_jq}"
readonly NIX="${EXE_nix}"

# --- Category A regexes -----------------------------------------------
# Matches github:<owner>/PersonalMonorepo flake-style refs, owner matched
# case-insensitively, repo name matched exactly.
readonly CAT_A_OWNER_RE='[Aa][Ii][Dd][Aa][Nn][Hh][Ii][Ll][Tt]'
readonly CAT_A_ANY_RE="github:${CAT_A_OWNER_RE}/PersonalMonorepo"
# Any char that isn't a quote, space, '?' (start of a query string) or '#'
# (start of a flake output selector).
readonly CAT_A_REF_CLASS='[^"'"'"' ?#]+'
readonly CAT_A_FULL_RE="^(.*)(github:${CAT_A_OWNER_RE}/PersonalMonorepo/)(${CAT_A_REF_CLASS})(.*)\$"

# --- Category B/C targets ----------------------------------------------
readonly B_FILE="nix/mono-flake/flake.nix"
readonly CAT_B_RE='^([[:space:]]*personalMonorepoBranch[[:space:]]*=[[:space:]]*")([^"]*)(".*)$'

readonly C_FILE="kubernetes/helm-charts/k8s-resources/master-stack/values.yaml"
readonly CAT_C_RE='^(gitRevision:[[:space:]]*)([^[:space:]#]+)(.*)$'

# jq program: finds the names of every root flake input whose locked node
# points at owner=aidanhilt (case-insensitive), repo=PersonalMonorepo.
# shellcheck disable=SC2016 # single-quoted on purpose: this is jq syntax, not shell
readonly JQ_FIND_PM_INPUTS='
  . as $doc
  | $doc.nodes.root.inputs
  | to_entries[]
  | select(.value | type == "string")
  | . as $e
  | ($doc.nodes[$e.value]) as $n
  | select((($n.original.repo // "") | ascii_downcase) == "personalmonorepo")
  | select((($n.original.owner // "") | ascii_downcase) == "aidanhilt")
  | $e.key
'

REPO=""
TARGET_BRANCH=""

# Category A: parallel arrays of pending changes.
PA_FILE=()
PA_LINE=()
PA_OLD=()
PA_NEW=()
UPTODATE_A=()
SKIPPED_A=()
A_FLAKE_DIRS=()

# Category B/C scalar state.
B_LINE=""
B_OLD=""
B_NEW_LINE=""
B_CHANGED=false

C_LINE=""
C_OLD=""
C_NEW_LINE=""
C_CHANGED=false

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
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

# Rewrites $1 in place, replacing the lines named as keys in the
# associative array named by $2 (nameref: line number -> new text); every
# other line is copied through unchanged.
rewrite_file_lines() {
  local file="$1"
  local -n _replacements="$2"
  local tmp
  tmp="$(mktemp)"
  local line_num=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ -v _replacements[$line_num] ]]; then
      printf '%s\n' "${_replacements[$line_num]}" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$file"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Classifies a single line for category A. Sets globals:
#   _A_STATUS   one of: none | comment | skip_noref | uptodate | changed
#   _A_OLD_REF  the ref currently in the line (set for uptodate/changed only)
#   _A_NEW_LINE the rewritten line text (set only when _A_STATUS=changed)
category_a_process_line() {
  local line="$1"
  _A_STATUS="none"
  _A_NEW_LINE="$line"
  _A_OLD_REF=""

  # A whole commented-out line is never a match (e.g. doc examples that
  # already use ${globals.personalMonorepoBranch}).
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    _A_STATUS="comment"
    return
  fi

  if [[ ! "$line" =~ $CAT_A_ANY_RE ]]; then
    return
  fi

  if [[ ! "$line" =~ $CAT_A_FULL_RE ]]; then
    _A_STATUS="skip_noref"
    return
  fi

  local before="${BASH_REMATCH[1]}"
  local prefix="${BASH_REMATCH[2]}"
  local ref="${BASH_REMATCH[3]}"
  local after="${BASH_REMATCH[4]}"

  _A_OLD_REF="$ref"

  if [[ "$ref" == "$TARGET_BRANCH" ]]; then
    _A_STATUS="uptodate"
    return
  fi

  _A_STATUS="changed"
  _A_NEW_LINE="${before}${prefix}${TARGET_BRANCH}${after}"
}

scan_category_a() {
  local -a files
  mapfile -t files < <("$GIT" -C "$REPO" ls-files -- . \
    ':(glob,exclude)**/*.md' \
    ':(glob,exclude)**/flake.lock' \
    ':(glob,exclude)windows-setup/**' \
    ':(glob,exclude)custom-images/**' \
    ':(glob,exclude)kubernetes/argocd/configuration-data/**')

  local f
  for f in "${files[@]}"; do
    local path="$REPO/$f"
    [[ -f "$path" ]] || continue

    local line_num=0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_num=$((line_num + 1))
      category_a_process_line "$line"

      case "$_A_STATUS" in
      none | comment) ;;
      skip_noref)
        SKIPPED_A+=("$f:$line_num: $(trim "$line")")
        ;;
      uptodate)
        UPTODATE_A+=("$f:$line_num: $_A_OLD_REF")
        ;;
      changed)
        PA_FILE+=("$f")
        PA_LINE+=("$line_num")
        PA_OLD+=("$_A_OLD_REF")
        PA_NEW+=("$_A_NEW_LINE")
        if [[ "$(basename "$f")" == "flake.nix" ]]; then
          local d
          d="$(dirname "$f")"
          if ! array_contains "$d" "${A_FLAKE_DIRS[@]}"; then
            A_FLAKE_DIRS+=("$d")
          fi
        fi
        ;;
      esac
    done <"$path"
  done
}

apply_category_a() {
  local -A files_seen=()
  local i
  for i in "${!PA_FILE[@]}"; do
    files_seen["${PA_FILE[$i]}"]=1
  done

  local file
  for file in "${!files_seen[@]}"; do
    local -A repl=()
    for i in "${!PA_FILE[@]}"; do
      if [[ "${PA_FILE[$i]}" == "$file" ]]; then
        repl["${PA_LINE[$i]}"]="${PA_NEW[$i]}"
      fi
    done
    rewrite_file_lines "$REPO/$file" repl
    print_status "Category A: updated $file"
  done
}

scan_category_b() {
  local path="$REPO/$B_FILE"
  if [[ ! -f "$path" ]]; then
    print_warning "Category B: $B_FILE not found; skipping."
    return
  fi

  local line_num=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ "$line" =~ $CAT_B_RE ]]; then
      B_LINE="$line_num"
      B_OLD="${BASH_REMATCH[2]}"
      if [[ "$B_OLD" != "$TARGET_BRANCH" ]]; then
        B_CHANGED=true
        B_NEW_LINE="${BASH_REMATCH[1]}${TARGET_BRANCH}${BASH_REMATCH[3]}"
      fi
      return
    fi
  done <"$path"

  print_warning "Category B: no 'personalMonorepoBranch = \"...\";' line found in $B_FILE"
}

apply_category_b() {
  [[ "$B_CHANGED" == true ]] || return 0
  local -A repl=()
  # shellcheck disable=SC2034 # consumed by rewrite_file_lines via nameref, passed by name
  repl["$B_LINE"]="$B_NEW_LINE"
  rewrite_file_lines "$REPO/$B_FILE" repl
  print_status "Category B: updated $B_FILE (line $B_LINE)"
}

scan_category_c() {
  local path="$REPO/$C_FILE"
  if [[ ! -f "$path" ]]; then
    print_warning "Category C: $C_FILE not found; skipping."
    return
  fi

  local line_num=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ "$line" =~ $CAT_C_RE ]]; then
      C_LINE="$line_num"
      C_OLD="${BASH_REMATCH[2]}"
      if [[ "$C_OLD" != "$TARGET_BRANCH" ]]; then
        C_CHANGED=true
        C_NEW_LINE="${BASH_REMATCH[1]}${TARGET_BRANCH}${BASH_REMATCH[3]}"
      fi
      return
    fi
  done <"$path"

  print_warning "Category C: no top-level 'gitRevision: ...' line found in $C_FILE"
}

apply_category_c() {
  [[ "$C_CHANGED" == true ]] || return 0
  local -A repl=()
  # shellcheck disable=SC2034 # consumed by rewrite_file_lines via nameref, passed by name
  repl["$C_LINE"]="$C_NEW_LINE"
  rewrite_file_lines "$REPO/$C_FILE" repl
  print_status "Category C: updated $C_FILE (line $C_LINE)"
}

update_locks() {
  local -a dirs=("$@")
  local overall_rc=0
  local d
  for d in "${dirs[@]}"; do
    local lockfile="$REPO/$d/flake.lock"
    if [[ ! -f "$lockfile" ]]; then
      print_warning "Lock update: $lockfile not found; skipping."
      overall_rc=1
      continue
    fi

    local -a pm_inputs=()
    mapfile -t pm_inputs < <("$JQ" -r "$JQ_FIND_PM_INPUTS" "$lockfile")

    if [[ "${#pm_inputs[@]}" -eq 0 ]]; then
      print_warning "Lock update: no PersonalMonorepo inputs found in $lockfile; skipping."
      continue
    fi

    print_status "Lock update: updating ${pm_inputs[*]} in $d/flake.lock"
    if ! (cd "$REPO/$d" && "$NIX" --extra-experimental-features 'nix-command flakes' flake update "${pm_inputs[@]}"); then
      print_warning "Lock update failed for $d (network or other error); continuing."
      overall_rc=1
    fi
  done
  return "$overall_rc"
}

confirm_category() {
  local label="$1"
  if [[ ! -t 0 ]]; then
    print_warning "Non-interactive stdin; treating category $label confirmation as 'no'."
    return 1
  fi
  local reply=""
  read -r -p "Apply category $label? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

print_plan() {
  echo ""
  print_status "Target branch: $TARGET_BRANCH"
  echo ""
  echo "=== Category A: flake-style github:aidanhilt/PersonalMonorepo/project-appocalypse/knative-function-operator URLs ==="
  if [[ "${#PA_FILE[@]}" -eq 0 ]]; then
    echo "  (no changes needed)"
  else
    local i
    for i in "${!PA_FILE[@]}"; do
      printf '  %s:%s: %s -> %s\n' "${PA_FILE[$i]}" "${PA_LINE[$i]}" "${PA_OLD[$i]}" "$TARGET_BRANCH"
    done
  fi
  if [[ "${#UPTODATE_A[@]}" -gt 0 ]]; then
    echo "  Already up to date:"
    local u
    for u in "${UPTODATE_A[@]}"; do
      echo "    $u"
    done
  fi
  if [[ "${#SKIPPED_A[@]}" -gt 0 ]]; then
    echo "  Skipped (no ref segment present -- not rewritten):"
    local s
    for s in "${SKIPPED_A[@]}"; do
      echo "    $s"
    done
  fi

  echo ""
  echo "=== Category B: nix global personalMonorepoBranch ($B_FILE) ==="
  if [[ "$B_CHANGED" == true ]]; then
    printf '  line %s: %s -> %s\n' "$B_LINE" "$B_OLD" "$TARGET_BRANCH"
  elif [[ -n "$B_LINE" ]]; then
    echo "  Already up to date (line $B_LINE: $B_OLD)"
  else
    echo "  (not found; see warning above)"
  fi

  echo ""
  echo "=== Category C: Helm default gitRevision ($C_FILE) ==="
  if [[ "$C_CHANGED" == true ]]; then
    printf '  line %s: %s -> %s\n' "$C_LINE" "$C_OLD" "$TARGET_BRANCH"
  elif [[ -n "$C_LINE" ]]; then
    echo "  Already up to date (line $C_LINE: $C_OLD)"
  else
    echo "  (not found; see warning above)"
  fi

  echo ""
  echo "=== Never touched (by design) ==="
  echo "  kubernetes/argocd/configuration-data/** (per-cluster pins)"
  echo "  Dockerfiles, raw.githubusercontent.com URLs, *.md, windows-setup/"
  echo "  flake.lock files (only updated indirectly via 'nix flake update', see below)"
  echo ""
}

DRY_RUN=false
ASSUME_YES=false
NO_LOCK=false
ALLOW_UNPUSHED=false

args_description "Rewrites references to the monorepo's branch (flake-style github: URLs, the personalMonorepoBranch nix global, and the Helm master-stack default gitRevision) so they all point at your CURRENT git branch. This only ever rolls forward -- to go back, check out main and run this again."
args_example "$(basename "$0")"
args_example "$(basename "$0") --dry-run"
args_example "$(basename "$0") --yes --no-lock"
args_flag "" "--dry-run" DRY_RUN "Print the plan only; make no changes"
args_flag "" "--yes" ASSUME_YES "Apply all categories with pending changes without prompting"
args_flag "" "--no-lock" NO_LOCK "Skip running 'nix flake update' on affected flake.lock files"
args_flag "" "--allow-unpushed" ALLOW_UNPUSHED "Allow targeting a branch that has not been pushed to origin yet"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

require_monorepo
REPO="$PERSONAL_MONOREPO_LOCATION"

if ! "$GIT" -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  print_error "PERSONAL_MONOREPO_LOCATION ('$REPO') is not a git repository"
  exit 1
fi

TARGET_BRANCH="$("$GIT" -C "$REPO" branch --show-current)"
if [[ -z "$TARGET_BRANCH" ]]; then
  print_error "Refusing: repository at '$REPO' is in detached HEAD (no current branch). Check out a branch first."
  exit 1
fi

if ! "$GIT" check-ref-format --branch "$TARGET_BRANCH" >/dev/null 2>&1; then
  print_error "Refusing: '$TARGET_BRANCH' is not a valid git branch name"
  exit 1
fi

if ! "$GIT" -C "$REPO" ls-remote --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1; then
  if [[ "$ALLOW_UNPUSHED" == true ]]; then
    print_warning "Branch '$TARGET_BRANCH' was not found on origin. Every rewritten reference will point at a branch that does not exist remotely (--allow-unpushed given)."
  else
    print_error "Refusing: branch '$TARGET_BRANCH' does not exist on origin. Push it first, or pass --allow-unpushed."
    exit 1
  fi
fi

scan_category_a
scan_category_b
scan_category_c

print_plan

if [[ "$DRY_RUN" == true ]]; then
  print_status "Dry run: no changes made."
  exit 0
fi

applied_any=false

if [[ "${#PA_FILE[@]}" -gt 0 ]]; then
  if [[ "$ASSUME_YES" == true ]] || confirm_category "A"; then
    apply_category_a
    applied_any=true
  else
    print_status "Category A: declined; no changes made."
    A_FLAKE_DIRS=()
  fi
fi

if [[ "$B_CHANGED" == true ]]; then
  if [[ "$ASSUME_YES" == true ]] || confirm_category "B"; then
    apply_category_b
    applied_any=true
  else
    print_status "Category B: declined; no changes made."
  fi
fi

if [[ "$C_CHANGED" == true ]]; then
  if [[ "$ASSUME_YES" == true ]] || confirm_category "C"; then
    apply_category_c
    applied_any=true
  else
    print_status "Category C: declined; no changes made."
  fi
fi

lock_failures=0
if [[ "$NO_LOCK" != true && "${#A_FLAKE_DIRS[@]}" -gt 0 ]]; then
  update_locks "${A_FLAKE_DIRS[@]}" || lock_failures=1
fi

echo ""
if [[ "$applied_any" == true ]]; then
  print_status "Done. Review the changes with 'git -C $REPO diff' and commit when ready."
else
  print_status "No changes applied."
fi

if [[ "$lock_failures" -ne 0 ]]; then
  print_error "One or more flake.lock updates failed; see warnings above."
  exit 3
fi
