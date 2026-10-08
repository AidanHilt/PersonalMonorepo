#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: agent-stage <branch> [--expect-sha <sha256-of-validate.sh>] [--force]

Stages the file changes committed on a pi-subagent worktree branch onto the
CURRENT branch's working tree and index, via `git merge --squash`, WITHOUT
committing. This lets the user review/edit the staged changes and commit
them themselves (e.g. with `kommit`). It never commits, never deletes the
branch, and never pushes.

Before staging, agent-stage verifies the branch's own validate.sh actually
passed:

  1. <branch> must match `pi-agent-*` (the branch naming convention used by
     the @gotgenes/pi-subagents-worktrees extension).
  2. The current working tree and index must be clean (no staged or
     unstaged changes) -- agent-stage refuses to stomp on in-progress work.
  3. `.agent/validated.json` must exist on <branch> (read via `git show`,
     no checkout needed).
  4. The tree_sha recorded in that artifact must match a tree_sha
     recomputed from the branch's own tree (same exclusions: .agent/ and
     validate.sh, computed via a temporary index -- never the real one).
  5. If --expect-sha is given and differs from the artifact's                                                                                                               
    validate_sh_sha256 field, a warning is printed. This is advisory only                                                                                                  
    and never blocks staging; check 4 (tree_sha) is the enforced guarantee. 

Any of checks 3-5 failing is reported with which check failed and exits
non-zero, UNLESS --force is given, in which case a loud warning is printed
and staging proceeds anyway.

On success: runs `git merge --squash <branch>`, then removes validate.sh
and .agent/ from the index and working tree if the squash brought them in
(so they never land in what the user commits). If the squash fails or
reports conflicts, the working tree and index are restored to their prior
state and agent-stage exits non-zero -- it does not leave a half-merged
tree behind.

Prints a summary of the changed files, the branch's commit log, and the
next step (review the staged changes, then run kommit).

     --expect-sha <sha>   Optional. Warn if the artifact's validate_sh_sha256                                                                                                  
                           differs from <sha> (advisory only; see check 5).                                                                                                    
     --force              Skip checks 3-4 (missing artifact / tree mismatch)                                                                                                   
                           and stage anyway, with a warning.  
EOF
}

require_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    print_error "Refusing to stage: the current working tree or index is dirty. Commit, stash, or discard your changes first."
    exit 1
  fi
}

# Computes the tree_sha for an arbitrary commit-ish, excluding .agent/ and
# validate.sh, via a temporary index -- never touching the real index.
# Mirrors the same exclusion logic validate.sh itself uses to produce the
# tree_sha it records in the artifact.
compute_branch_tree_sha() {
  local commitish="$1"
  local tmp_index
  tmp_index="$(mktemp -u)"
  GIT_INDEX_FILE="$tmp_index" git read-tree "$commitish" 2>/dev/null
  GIT_INDEX_FILE="$tmp_index" git rm -r --cached --ignore-unmatch -q .agent validate.sh >/dev/null 2>&1 || true
  local sha
  sha="$(GIT_INDEX_FILE="$tmp_index" git write-tree 2>/dev/null)"
  local rc=$?
  rm -f "$tmp_index"
  if [[ $rc -ne 0 ]]; then
    return 1
  fi
  printf '%s\n' "$sha"
}

main() {
  local branch="" expect_sha="" force=0

  if [[ $# -eq 0 ]]; then
    print_error "Missing required <branch> argument"
    show_help
    exit 1
  fi

  branch="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --expect-sha)
      expect_sha="$2"
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

  case "$branch" in
  pi-agent-*) ;;
  *)
    print_error "Refusing to stage '$branch': branch name does not match the pi-agent-* convention"
    exit 1
    ;;
  esac

  if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    print_error "Branch '$branch' does not exist"
    exit 1
  fi

  require_clean_worktree

  local artifact_json="" problem=""

  if ! artifact_json="$(git show "$branch:.agent/validated.json" 2>/dev/null)"; then
    problem="'.agent/validated.json' not found on branch '$branch'"
  else
    local artifact_tree_sha recomputed_tree_sha artifact_sha
    artifact_tree_sha="$(printf '%s' "$artifact_json" | jq -r '.tree_sha // empty' 2>/dev/null || true)"
    artifact_sha="$(printf '%s' "$artifact_json" | jq -r '.validate_sh_sha256 // empty' 2>/dev/null || true)"

    if [[ -z "$artifact_tree_sha" ]]; then
      problem="'.agent/validated.json' on '$branch' has no usable tree_sha field"
    elif ! recomputed_tree_sha="$(compute_branch_tree_sha "$branch")"; then
      problem="failed to recompute tree_sha for branch '$branch'"
    elif [[ "$recomputed_tree_sha" != "$artifact_tree_sha" ]]; then
      problem="tree_sha mismatch: artifact says '$artifact_tree_sha', branch tree is actually '$recomputed_tree_sha' (working tree changed after validate.sh ran)"
    fi
    
    if [[ -n "$expect_sha" && "$expect_sha" != "$artifact_sha" ]]; then                                                                                                     
      print_warning "validate.sh sha256 differs from --expect-sha (expected '$expect_sha', artifact recorded '$artifact_sha'). Not a failure: only tree_sha is enforced."   
    fi 
  fi

  if [[ -n "$problem" ]]; then
    if [[ "$force" -eq 1 ]]; then
      print_warning "VALIDATION PROBLEM IGNORED DUE TO --force: $problem"
      print_warning "Staging anyway. Review the diff carefully before committing."
    else
      print_error "Refusing to stage '$branch': $problem"
      print_error "If the artifact is missing or mismatched, run the checks yourself instead of using --force, or pass --force to override."
      exit 1
    fi
  fi

  local pre_validate_tracked=0 pre_agent_tracked=0
  git ls-files --error-unmatch validate.sh >/dev/null 2>&1 && pre_validate_tracked=1
  git ls-files --error-unmatch .agent >/dev/null 2>&1 && pre_agent_tracked=1

  print_status "Staging '$branch' onto the current branch via git merge --squash..."

  if ! git merge --squash "$branch" >/tmp/agent-stage-merge.out 2>&1; then
    cat /tmp/agent-stage-merge.out >&2
    print_error "git merge --squash failed or produced conflicts. Restoring working tree and index."
    git merge --abort 2>/dev/null || true
    git reset --hard HEAD >/dev/null 2>&1 || true
    rm -f /tmp/agent-stage-merge.out
    exit 1
  fi
  rm -f /tmp/agent-stage-merge.out

  # Keep validate.sh and .agent/ out of what the user is asked to commit,
  # but only if the squash actually introduced them (they were not already
  # tracked on the current branch before this merge).
  if [[ "$pre_validate_tracked" -eq 0 ]]; then
    git reset -q -- validate.sh 2>/dev/null || true
    rm -f validate.sh
  fi
  if [[ "$pre_agent_tracked" -eq 0 ]]; then
    git reset -q -- .agent 2>/dev/null || true
    rm -rf .agent
  fi

  print_status "Staged changes from '$branch' (squashed, not committed):"
  git status --short

  print_status "Branch log for '$branch':"
  git log --oneline "HEAD..$branch" 2>/dev/null || true

  print_status "Next step: review the staged changes, then commit with kommit. agent-stage never commits, deletes the branch, or pushes."
}

main "$@"
