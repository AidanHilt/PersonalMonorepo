# config/agent/

This directory is a direct, 1:1 mirror of the final `PI_CODING_AGENT_DIR`
tree the launcher seeds: every file already lives at its final relative
path (`settings.json`, `AGENTS.md`, `agents/*`,
`extensions/<name>/config.json`, ...), so `start-agent.sh` lays it onto
the one fixed, shared agent directory (`/var/lib/pi/.pi/agent/` — see
IMPLEMENTERS.md's "Fixed agent dir" section) with a single recursive
copy — no per-file translation. It's a sibling of the top-level `config/`, which mirrors the
rest of `~/.pi/` the same way (e.g. `config/web-search.json` mirrors
`~/.pi/web-search.json`, i.e. `/var/lib/pi/.pi/web-search.json`).

**Config only. Never a secret, token, or key — not even a placeholder
that looks real enough to paste over by accident.**

| File | Purpose |
|---|---|
| `AGENTS.md` | Fallback behavioral guidelines, used only if the mounted project has no AGENTS.md of its own. |
| `settings.json` | Provider/model/compaction settings. |
| `extensions/pi-permission-system/config.json` | The actual allow/ask/deny policy for `@gotgenes/pi-permission-system`. |
| `subagents-worktrees.json` | Opts the `IMPLEMENT` agent type and its per-dispatch `IMPLEMENT-1`..`IMPLEMENT-10` slot copies into isolated git worktrees via `@gotgenes/pi-subagents-worktrees` (`{"worktreeAgents": ["IMPLEMENT", "IMPLEMENT-1", "IMPLEMENT-2", "IMPLEMENT-3", "IMPLEMENT-4", "IMPLEMENT-5", "IMPLEMENT-6", "IMPLEMENT-7", "IMPLEMENT-8", "IMPLEMENT-9", "IMPLEMENT-10"]}`). See AGENTS.md's "Worktrees" section for how that fits the dispatch/validate/stage workflow. This slot count must stay in sync with `MAX_SLOTS` in `nix/scripts/scripts/agent/agent-plan-create/run.sh`. |

Credentials live at runtime, outside this directory and outside the
repo entirely — see IMPLEMENTERS.md's "Credentials" section.
