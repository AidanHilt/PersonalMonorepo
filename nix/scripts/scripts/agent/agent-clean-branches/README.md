# agent-clean-branches

Cleans up the local `pi-agent-*` branches left behind by IMPLEMENT
subagent dispatches (see `agent-stage` and
`nix/agentic-ai-stack/config/agent/AGENTS.md`'s planning workflow).
`agent-stage` squash-stages a dispatch's branch onto the current branch
without ever merging or deleting it, so `pi-agent-*` branches pile up
over time; this script finds the ones that are safe to remove.

See `agent-clean-branches --help` for the full reference; in short:

- Operates on the git repository rooted at the current working
  directory. Only local branches matching `pi-agent-*` are ever
  considered; remote branches and anything else are never touched.
- **Dry-run by default** -- prints what it would do and changes
  nothing. Pass `--delete` to actually delete branches.
- Each matching branch is categorized:
  - `KEEP-IN-USE` -- the current branch, or checked out in any
    worktree. Never deleted.
  - `EMPTY` -- no changes relative to its merge-base with `HEAD`.
    Safe to delete.
  - `STAGED` -- its diff against that merge-base reverse-applies
    cleanly onto `HEAD` (i.e. already staged/committed there, normally
    via `agent-stage`). Safe to delete.
  - `KEEP-UNSTAGED` -- anything else (e.g. staged changes that were
    later hand-edited). Never deleted, conservatively.
- With `--delete`, `EMPTY` and `STAGED` branches are removed via
  `git branch -D`, and `git worktree prune` is run afterwards to clear
  stale worktree administrative data.
- No prompts either way.
