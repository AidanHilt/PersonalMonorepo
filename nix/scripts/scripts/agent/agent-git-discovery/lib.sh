#!/bin/bash
# Git-backed changed-file discovery for the agent dispatch tooling.
#
# This lib knows nothing about check execution, path classification, or
# dispatch artifacts: it answers exactly one question -- "which
# repo-relative files currently differ from HEAD, or are untracked?" -- and
# leaves what to do about them to its caller. agent-validate is its caller:
# with no --path it feeds DISCOVERED_PATHS straight into classification, and
# explicit --path values override discovery entirely (see
# agent-validate/run.sh for the CLI and artifact semantics).
#
# Usage (from a script that also declares "#include agent-git-discovery"):
#
#   if discover_changed_files "$repo_root"; then
#     for path in "${DISCOVERED_PATHS[@]}"; do
#       ...  # repo-relative, existing, deduplicated
#     done
#   else
#     # Real git failure; $GIT_DISCOVERY_ERROR has the diagnostic, which
#     # has already been printed to stderr.
#   fi
#
# Contract:
#   - DISCOVERED_PATHS holds *existing* file paths, relative to the work
#     tree top level, with no duplicates and no .agent/ bookkeeping
#     entries. repo_root must be that top level (as returned by
#     `git rev-parse --show-toplevel`), because git emits paths relative
#     to it.
#   - Zero changes is a success: discover_changed_files returns 0 and
#     leaves DISCOVERED_PATHS empty.
#   - Order is stable and deterministic: tracked changes against HEAD
#     (staged and unstaged together) in git's own sorted order first, then
#     untracked non-ignored files in git's own sorted order. No extra sort
#     pass is needed, so no extra tool dependency is introduced.
#   - Filenames containing spaces, tabs, or newlines survive intact: every
#     git invocation is NUL-delimited (-z) and every read loop is
#     NUL-terminated, so nothing is ever split on whitespace.
#
# This file never calls "exit" -- it is inlined into every consumer.

# Reset and repopulated by discover_changed_files. Declared here so a
# consumer can reference it (e.g. from an empty-selection branch) before
# the first call, even under `set -u`.
#shellcheck disable=SC2034
DISCOVERED_PATHS=()

# Human-readable reason for the most recent discovery failure, empty on
# success. Mirrors the stderr diagnostic discover_changed_files prints.
#shellcheck disable=SC2034
GIT_DISCOVERY_ERROR=""

# True (0) when a discovered path must never be validated: the dispatch
# workflow's own scratch directory, which would otherwise make every run
# rediscover its own bookkeeping.
#shellcheck disable=SC2329
git_discovery_is_excluded() {
  local path="$1"
  case "$path" in
  .agent | .agent/*) return 0 ;;
  esac
  return 1
}

# True (0) when <repo_root>/<path> is present on disk. -e alone misses
# dangling symlinks, which are still real entries git tracks, so -L covers
# those too.
#shellcheck disable=SC2329
git_discovery_path_exists() {
  local repo_root="$1" path="$2"
  [[ -e "$repo_root/$path" || -L "$repo_root/$path" ]]
}

# Appends the NUL-delimited output of `git -C <repo_root> <args>` to the
# named array. Returns non-zero, setting GIT_DISCOVERY_ERROR and printing
# it to stderr, when git itself fails; git's own stderr is left untouched
# so the real cause stays visible instead of collapsing into an empty
# selection.
#
# Git's output goes to a temporary file rather than a process substitution
# because `< <(git ...)` discards git's exit status: reading the file back
# afterwards is what lets a genuine failure be distinguished from "no
# changes".
#shellcheck disable=SC2329
git_discovery_collect() {
  # git_discovery_collect <array-name> <repo_root> <git args...>
  local -n _git_discovered="$1"
  local repo_root="$2"
  shift 2

  local tmp line quoted rc=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/agent-git-discovery.XXXXXX")" || {
    GIT_DISCOVERY_ERROR="could not create a temporary file under ${TMPDIR:-/tmp} to hold git output"
    printf '%s\n' "$GIT_DISCOVERY_ERROR" >&2
    return 1
  }

  git -C "$repo_root" "$@" >"$tmp"
  rc=$?
  if ((rc != 0)); then
    # Only builds a printable copy of argv for the diagnostic below, so a
    # masked printf status is intended.
    #shellcheck disable=SC2312
    quoted="$(printf '%q ' "$@")"
    GIT_DISCOVERY_ERROR="git -C $(printf '%q' "$repo_root") ${quoted% } failed with exit status $rc"
    printf '%s\n' "$GIT_DISCOVERY_ERROR" >&2
    rm -f -- "$tmp"
    return 1
  fi

  while IFS= read -r -d '' line; do
    _git_discovered+=("$line")
  done <"$tmp"

  rm -f -- "$tmp"
  return 0
}

# Resets DISCOVERED_PATHS and fills it with the repository-relative paths
# of every file that is (a) modified in the index or the working tree
# relative to HEAD, or (b) untracked and not ignored. Deleted paths are
# filtered out rather than reported as stale names.
#shellcheck disable=SC2329
discover_changed_files() {
  # discover_changed_files <repo_root>
  local repo_root="${1-}"

  DISCOVERED_PATHS=()
  GIT_DISCOVERY_ERROR=""

  if [[ -z "$repo_root" ]]; then
    GIT_DISCOVERY_ERROR="discover_changed_files requires a repository root path"
    printf '%s\n' "$GIT_DISCOVERY_ERROR" >&2
    return 1
  fi
  if [[ ! -d "$repo_root" ]]; then
    GIT_DISCOVERY_ERROR="repository root '$repo_root' is not a directory"
    printf '%s\n' "$GIT_DISCOVERY_ERROR" >&2
    return 1
  fi

  local -a tracked=() untracked=()
  local -A seen=()
  local path

  # (a) Tracked changes, staged and unstaged, against HEAD. --no-renames
  # keeps the result predictable: a rename surfaces as its old path (a
  # deletion) plus its new path (an addition), and the old one is dropped
  # by the filters below. --diff-filter=d drops deletions at the source.
  if ! git_discovery_collect tracked "$repo_root" \
    diff --name-only -z --diff-filter=d --no-renames HEAD --; then
    return 1
  fi

  # (b) Untracked files. --exclude-standard honours .gitignore,
  # .git/info/exclude, and core.excludesFile, so ignored build output and
  # the like never reaches the caller.
  if ! git_discovery_collect untracked "$repo_root" \
    ls-files --others --exclude-standard -z; then
    return 1
  fi

  for path in "${tracked[@]+"${tracked[@]}"}" \
    "${untracked[@]+"${untracked[@]}"}"; do
    [[ -n "$path" ]] || continue
    git_discovery_is_excluded "$path" && continue
    git_discovery_path_exists "$repo_root" "$path" || continue
    [[ -n "${seen["$path"]+set}" ]] && continue
    seen["$path"]=1
    DISCOVERED_PATHS+=("$path")
  done

  return 0
}
