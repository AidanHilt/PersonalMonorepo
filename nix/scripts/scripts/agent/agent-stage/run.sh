#!/bin/bash

#include printing-and-output

set -euo pipefail

# Repository root of the destination worktree, resolved once in main(). Every
# .agent/ related operation goes through it so agent-stage behaves the same
# no matter which subdirectory of the worktree it was invoked from.
REPO_ROOT=""

show_help() {
  cat <<'EOF'
Usage: agent-stage <branch> [--slot <n>] [--force]

Stages the file changes committed on a pi-subagent worktree branch onto the
CURRENT branch's working tree and index, via `git merge --squash`, WITHOUT
committing. This lets the user review/edit the staged changes and commit
them themselves (e.g. with `kommit`). It never commits, never deletes the
branch, and never pushes.

Before staging, agent-stage verifies the branch's own agent-validate run
actually passed:

  1. <branch> must match `pi-agent-*` (the branch naming convention used by
     the @gotgenes/pi-subagents-worktrees extension).
  2. The current working tree and index must be clean (no staged or
     unstaged changes) -- agent-stage refuses to stomp on in-progress work.
  3. `.agent/validated.json` must exist on <branch> (read via `git show`,
     no checkout needed).
  4. The tree_sha recorded in that artifact must match a "source-only"
     tree_sha recomputed from the branch's own committed tree, excluding
     only the repository-root `.agent/` (agent-validate's own validation
     bookkeeping, never part of the source being reviewed). The hash is
     computed via a temporary index -- never the real one -- so a branch
     that validated clean matches even though its commit carries
     `.agent/validated.json`.

Any of checks 3-4 failing is reported with which check failed and exits
non-zero, UNLESS --force is given, in which case a loud warning is printed
and staging proceeds anyway.

git and jq must be on PATH for this script to run.

On success: runs `git merge --squash <branch>`, then removes the
repository-root `.agent/` directory from the index and working tree if the
squash brought it in (so it never lands in what the user commits). If the
squash fails or reports conflicts, the working tree and index are restored
to their prior state and agent-stage exits non-zero -- it does not leave a
half-merged tree behind.

agent-stage may be invoked from any directory inside the destination
worktree: it resolves the repository root itself (`git rev-parse
--show-toplevel`) and always hashes and cleans up the ROOT `.agent/`
directory, so running it from e.g. nix/agentic-ai-stack does not leave
`.agent/validated.json` staged.

Prints a summary of the changed files, the branch's commit log, and the
next step (review the staged changes, then run kommit).

     --slot <n>   Optional. After a successful stage, removes the
                  per-dispatch agent definition
                  ${agents_dir}/IMPLEMENT-<n>.md (agents_dir resolves to
                  ${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents) AND its
                  plan file /tmp/pi-agent-plans/IMPLEMENT-<n>.md -- both
                  allocated by agent-plan-create for this dispatch --
                  freeing the slot for reuse. No error if either file is
                  already absent.
     --force      Skip checks 3-4 (missing artifact / tree mismatch) and
                  stage anyway, with a warning.
EOF
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    print_error "Required tool '$tool' not found on PATH. Install it and retry."
    exit 1
  fi
}

require_tools() {
  local tool
  for tool in "$@"; do
    require_tool "$tool"
  done
}

require_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    print_error "Refusing to stage: the current working tree or index is dirty. Commit, stash, or discard your changes first."
    exit 1
  fi
}

# Echoes captured git diagnostics to stderr, when there are any.
print_git_output() {
  local out="$1"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" >&2
  fi
  return 0
}

# Computes the "source-only" tree_sha for an arbitrary commit-ish, excluding
# only the repository-root .agent/ directory, via a temporary index -- never
# touching the real index. Mirrors the same exclusion logic agent-validate
# itself uses to produce the tree_sha it records in the artifact, except that
# it hashes a committed tree rather than the current working tree.
#
# Every git call runs against $REPO_ROOT (so .agent/ is always the root
# bookkeeping directory) and every failure is propagated with its captured
# diagnostics: silently continuing past a failed `git rm` used to leave
# .agent/ in the temporary index, so `git write-tree` returned the full
# branch tree and perfectly valid branches were rejected.
compute_branch_tree_sha() {
  local commitish="$1"
  local tmp_index out rc=0
  tmp_index="$(mktemp -u)"

  # Seed the temporary index from the requested commit-ish, so the hash
  # reflects the branch's committed tree and not the caller's checkout.
  out="$(GIT_INDEX_FILE="$tmp_index" git -C "$REPO_ROOT" read-tree "$commitish" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    print_error "Could not read the tree of '$commitish' into a temporary index (git read-tree exit $rc)"
    print_git_output "$out"
    rm -f "$tmp_index"
    return "$rc"
  fi

  # --force is required here: with GIT_INDEX_FILE set, plain `git rm --cached`
  # still compares staged entries against the caller's HEAD and working tree,
  # so a branch whose .agent/ differs from (or is absent in) the current
  # checkout makes it fail. --force bypasses those comparisons, and --cached
  # plus GIT_INDEX_FILE confine the removal to the temporary index, so no
  # working-tree file is ever deleted. --ignore-unmatch keeps a branch with
  # no .agent/ at all a success.
  out="$(GIT_INDEX_FILE="$tmp_index" git -C "$REPO_ROOT" rm -r --force --cached --ignore-unmatch -q -- .agent 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    print_error "Could not exclude .agent from the temporary index for '$commitish' (git rm exit $rc)"
    print_git_output "$out"
    rm -f "$tmp_index"
    return "$rc"
  fi

  out="$(GIT_INDEX_FILE="$tmp_index" git -C "$REPO_ROOT" write-tree 2>&1)" || rc=$?
  rm -f "$tmp_index"
  if [[ $rc -ne 0 ]]; then
    print_error "Could not write a tree for '$commitish' (git write-tree exit $rc)"
    print_git_output "$out"
    return "$rc"
  fi

  printf '%s\n' "$out"
  return 0
}

main() {
  local branch="" force=0 slot=""

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
  fi

  require_tools git jq

  if [[ $# -eq 0 ]]; then
    print_error "Missing required <branch> argument"
    show_help
    exit 1
  fi

  branch="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --slot)
      slot="$2"
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

  # Resolve the repository root once, after argument parsing: every .agent/
  # operation below is rooted here so agent-stage works identically from any
  # subdirectory of the destination worktree.
  if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    REPO_ROOT=""
  fi
  if [[ -z "$REPO_ROOT" ]]; then
    print_error "Not inside a git work tree: agent-stage must be run from somewhere inside the destination worktree."
    exit 1
  fi

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
  elif ! printf '%s' "$artifact_json" | jq -e . >/dev/null; then
    problem="'.agent/validated.json' on '$branch' is not valid JSON"
  else
    local artifact_tree_sha recomputed_tree_sha
    artifact_tree_sha="$(printf '%s' "$artifact_json" | jq -r '.tree_sha // empty')"

    if [[ -z "$artifact_tree_sha" ]]; then
      problem="'.agent/validated.json' on '$branch' has no usable tree_sha field"
    elif ! recomputed_tree_sha="$(compute_branch_tree_sha "$branch")"; then
      problem="failed to recompute tree_sha for branch '$branch'"
    elif [[ "$recomputed_tree_sha" != "$artifact_tree_sha" ]]; then
      problem="tree_sha mismatch: artifact says '$artifact_tree_sha', branch tree is actually '$recomputed_tree_sha' (working tree changed after agent-validate last ran)"
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

  local pre_agent_tracked=0
  if git -C "$REPO_ROOT" ls-files --error-unmatch .agent >/dev/null 2>&1; then
    pre_agent_tracked=1
  fi

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

  # Keep the root .agent/ out of what the user is asked to commit, but only
  # if the squash actually introduced it (it was not already tracked on the
  # current branch before this merge). Both the unstage and the delete are
  # resolved against $REPO_ROOT: a cwd-relative `.agent` silently missed the
  # real artifact whenever agent-stage was run from a subdirectory.
  if [[ "$pre_agent_tracked" -eq 0 ]]; then
    git -C "$REPO_ROOT" reset -q -- .agent 2>/dev/null || true
    rm -rf -- "$REPO_ROOT/.agent"
  fi

  print_status "Staged changes from '$branch' (squashed, not committed):"
  git status --short

  print_status "Branch log for '$branch':"
  git log --oneline "HEAD..$branch" 2>/dev/null || true

  if [[ -n "$slot" ]]; then
    local agents_dir slot_file plan_dir plan_file
    agents_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents"
    slot_file="$agents_dir/IMPLEMENT-$slot.md"
    plan_dir="/tmp/pi-agent-plans"
    plan_file="$plan_dir/IMPLEMENT-$slot.md"
    if [[ -e "$slot_file" ]]; then
      rm -f -- "$slot_file"
      print_status "Removed per-dispatch agent definition ($slot_file)"
    else
      print_status "Dispatch slot IMPLEMENT-$slot had no agent file to remove ($slot_file)"
    fi
    # agent-plan-create writes the dispatch plan to a shared /tmp path; drop
    # it too so a reused slot never inherits a stale plan. Missing is fine.
    if [[ -e "$plan_file" ]]; then
      rm -f -- "$plan_file"
      print_status "Removed dispatch plan file ($plan_file)"
    else
      print_status "Dispatch slot IMPLEMENT-$slot had no plan file to remove ($plan_file)"
    fi
    print_status "Freed dispatch slot IMPLEMENT-$slot"
  fi

  print_status "Next step: review the staged changes, then commit with kommit. agent-stage never commits, deletes the branch, or pushes."
}

main "$@"
