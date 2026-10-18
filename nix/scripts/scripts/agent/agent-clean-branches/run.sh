#!/bin/bash

#include printing-and-output
#include args-and-help

set -euo pipefail

# EXE_git is a flake runtime-dependency placeholder (see nix/scripts/IMPLEMENTERS.md's
# "Runtime dependencies" section) substituted at build time. The declaration below avoids
# a shellcheck SC2154 warning without needing a disable directive.
: "${EXE_git:=}" # runtime-dependency placeholder, substituted at build time
readonly GIT="${EXE_git}"

delete=""

read -r -d '' description <<'DESCRIPTION' || true
Clean up local pi-agent-* branches left behind by IMPLEMENT subagent
dispatches.

Operates on the git repository rooted at the current working directory
(must be inside a work tree). Considers only LOCAL branches matching
pi-agent-* -- the naming convention used by the
@gotgenes/pi-subagents-worktrees extension for IMPLEMENT subagent
dispatches, whose changes are always squash-staged (via agent-stage) onto
another branch rather than merged, so these branches never disappear on
their own and pile up over time. Remote branches and any branch not
matching pi-agent-* are never touched.

Each pi-agent-* branch is placed into exactly one category:

  KEEP-IN-USE   The branch is the current branch, or is checked out in any
                worktree. Never deleted.
  EMPTY         The branch has no changes relative to its merge-base with
                HEAD (e.g. a dispatch that made no changes). Safe to
                delete.
  STAGED        The branch's diff against its merge-base with HEAD
                reverse-applies cleanly onto HEAD -- i.e. the same changes
                are already present on HEAD (normally via agent-stage).
                Safe to delete.
  KEEP-UNSTAGED Anything else. Conservative default: never deleted. This
                includes branches whose staged changes were later edited
                by hand, which no longer reverse-apply cleanly.

Without --delete (the default), nothing is changed: every action printed
is prefixed "would". With --delete, EMPTY and STAGED branches are removed
via git branch -D, and git worktree prune is run to clear out any stale
worktree administrative data. No prompts are shown either way.
DESCRIPTION

args_description "$description"
args_example "$(basename "$0")"
args_example "$(basename "$0") --delete"
args_flag "" "--delete" delete "Actually delete safe-to-delete branches (default: dry-run, prints what would happen and changes nothing)"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

cleanup_tmp_dir() {
  if [[ -n "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup_tmp_dir EXIT

if ! REPO_ROOT="$("$GIT" rev-parse --show-toplevel 2>/dev/null)"; then
  print_error "Not inside a git work tree."
  exit 1
fi
cd "$REPO_ROOT"

if ! CURRENT_BRANCH="$("$GIT" branch --show-current 2>/dev/null)"; then
  print_error "Failed to determine the current branch."
  exit 1
fi

declare -A worktree_branches=()
while IFS= read -r line; do
  case "$line" in
  branch\ refs/heads/*)
    worktree_branches["${line#branch refs/heads/}"]=1
    ;;
  esac
done < <("$GIT" worktree list --porcelain)

mapfile -t branches < <("$GIT" for-each-ref --format='%(refname:short)' 'refs/heads/pi-agent-*' | sort)

if [[ "${#branches[@]}" -eq 0 ]]; then
  print_status "No local pi-agent-* branches found."
else
  TMP_DIR="$(mktemp -d)"

  declare -A count_keep_in_use=()
  declare -A count_empty=()
  declare -A count_staged=()
  declare -A count_unstaged=()
  deleted_empty=0
  deleted_staged=0
  would_delete_empty=0
  would_delete_staged=0

  for branch in "${branches[@]}"; do
    subject="$("$GIT" log -1 --format=%s "$branch" 2>/dev/null || echo "<no commits>")"
    category=""
    reason=""

    if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
      category="KEEP-IN-USE"
      reason="current branch"
    elif [[ -n "${worktree_branches[$branch]:-}" ]]; then
      category="KEEP-IN-USE"
      reason="checked out in a worktree"
    else
      if ! merge_base="$("$GIT" merge-base HEAD "$branch" 2>/dev/null)"; then
        category="KEEP-UNSTAGED"
        reason="no merge-base with HEAD"
      elif "$GIT" diff --quiet "$merge_base" "$branch" -- 2>/dev/null; then
        category="EMPTY"
      else
        tmp_index="$TMP_DIR/index"
        rm -f "$tmp_index"
        if GIT_INDEX_FILE="$tmp_index" "$GIT" read-tree HEAD 2>/dev/null &&
          "$GIT" diff --binary "$merge_base" "$branch" -- |
          GIT_INDEX_FILE="$tmp_index" "$GIT" apply --cached --reverse --check 2>/dev/null; then
          category="STAGED"
        else
          category="KEEP-UNSTAGED"
          reason="diff does not reverse-apply to HEAD"
        fi
        rm -f "$tmp_index"
      fi
    fi

    action=""
    case "$category" in
    KEEP-IN-USE)
      count_keep_in_use["$branch"]=1
      action="kept: $reason"
      ;;
    EMPTY)
      count_empty["$branch"]=1
      if [[ "$delete" == "true" ]]; then
        if "$GIT" branch -D "$branch" >/dev/null 2>&1; then
          action="deleted"
          deleted_empty=$((deleted_empty + 1))
        else
          action="kept: failed to delete"
        fi
      else
        action="would delete"
        would_delete_empty=$((would_delete_empty + 1))
      fi
      ;;
    STAGED)
      count_staged["$branch"]=1
      if [[ "$delete" == "true" ]]; then
        if "$GIT" branch -D "$branch" >/dev/null 2>&1; then
          action="deleted"
          deleted_staged=$((deleted_staged + 1))
        else
          action="kept: failed to delete"
        fi
      else
        action="would delete"
        would_delete_staged=$((would_delete_staged + 1))
      fi
      ;;
    KEEP-UNSTAGED)
      count_unstaged["$branch"]=1
      action="kept: $reason"
      ;;
    esac

    printf '%-14s %-40s %-50s %s\n' "$category" "$branch" "$subject" "$action"
  done

  print_status "Summary:"
  print_status "  KEEP-IN-USE:   ${#count_keep_in_use[@]}"
  if [[ "$delete" == "true" ]]; then
    print_status "  EMPTY:         ${#count_empty[@]} ($deleted_empty deleted)"
    print_status "  STAGED:        ${#count_staged[@]} ($deleted_staged deleted)"
  else
    print_status "  EMPTY:         ${#count_empty[@]} ($would_delete_empty would delete)"
    print_status "  STAGED:        ${#count_staged[@]} ($would_delete_staged would delete)"
  fi
  print_status "  KEEP-UNSTAGED: ${#count_unstaged[@]}"
fi

if [[ "$delete" == "true" ]]; then
  print_status "Pruning stale worktree administrative data..."
  "$GIT" worktree prune -v
else
  print_status "Worktree prune dry-run (pass --delete to actually prune):"
  "$GIT" worktree prune --dry-run -v
fi
