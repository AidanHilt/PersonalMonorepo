# agent-stage

Stages the changes committed by an IMPLEMENT subagent worktree branch
(`pi-agent-<id>`, created by the `@gotgenes/pi-subagents-worktrees`
extension) onto the current branch, for human review -- without committing.

See `agent-plan-create`'s plan-file generation and
`nix/agentic-ai-stack/config/agent/AGENTS.md`'s planning workflow for how
this fits into the overall dispatch -> validate -> stage -> review -> commit
pipeline; `agent-stage --help` is the detailed reference for this script's
own flags and exit behavior.

## The standard

- Only ever stages a branch matching `pi-agent-*` -- the naming convention
  the worktrees extension uses.
- Before staging, verifies the branch's own `.agent/validated.json`
  artifact (written by a passing `agent-validate` run inside the
  subagent's worktree) actually matches the branch's "source-only" tree,
  so a human never stages code that the subagent itself never finished
  validating. The check recomputes the hash from the branch's *committed*
  tree with only the repository-root `.agent/` excluded, via a temporary
  index (never the real one), and propagates any `git read-tree` / `git rm`
  / `git write-tree` failure with its captured diagnostics instead of
  silently falling back to the full branch tree. `--force` skips the check
  at the user's own risk.
- Uses `git merge --squash` (stages into the working tree and index, no
  commit), and strips the root `.agent/` back out of what gets staged if
  the squash introduced it.
- Works from any directory inside the destination worktree: it resolves
  the repository root once with `git rev-parse --show-toplevel`, so both the
  hash exclusion and the post-squash unstage/delete always target the root
  `.agent/` bookkeeping directory. Invoking it from e.g.
  `nix/agentic-ai-stack` therefore does not stage
  `.agent/validated.json`.
- `--slot <n>` frees a dispatch slot after a successful stage by removing
  both files `agent-plan-create` allocated for that dispatch: the
  per-dispatch `IMPLEMENT-<n>.md` agent definition and its plan file
  `/tmp/pi-agent-plans/IMPLEMENT-<n>.md` (see
  `nix/agentic-ai-stack/config/agent/AGENTS.md`'s "Worktrees" section).
  Cleanup only ever runs after a successful stage.
- Never commits, never deletes the branch, never pushes. Committing is the
  user's job (`kommit`).
