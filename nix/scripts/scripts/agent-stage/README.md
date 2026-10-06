# agent-stage

Stages the changes committed by an IMPLEMENT subagent worktree branch
(`pi-agent-<id>`, created by the `@gotgenes/pi-subagents-worktrees`
extension) onto the current branch, for human review -- without committing.

See `agent-plan-create`'s prompt generation and
`nix/agentic-ai-stack/config/agent/AGENTS.md`'s planning workflow for how
this fits into the overall dispatch -> validate -> stage -> review -> commit
pipeline; `agent-stage --help` is the detailed reference for this script's
own flags and exit behavior.

## The standard

- Only ever stages a branch matching `pi-agent-*` -- the naming convention
  the worktrees extension uses.
- Before staging, verifies the branch's own `.agent/validated.json`
  artifact (written by a passing `./validate.sh` run inside the subagent's
  worktree) actually matches the branch's tree, so a human never stages
  code that the subagent itself never finished validating. `--force` skips
  this at the user's own risk.
- Uses `git merge --squash` (stages into the working tree and index, no
  commit), and strips `validate.sh`/`.agent/` back out of what gets staged
  if the squash introduced them.
- Never commits, never deletes the branch, never pushes. Committing is the
  user's job (`kommit`).
