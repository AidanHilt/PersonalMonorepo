# config/agent/

Everything in this directory is baked into the `pi-image` at build time
and therefore ends up in the Nix store, which is world-readable on
multi-user systems and would leak if these images are ever pushed to a
binary cache or registry.

This directory is a direct, 1:1 mirror of the final `~/.pi/agent/` tree
inside the container: every file already lives at its final relative
path (`settings.json`, `AGENTS.md`, `agents/*`,
`extensions/<name>/config.json`, ...), so `image.nix` bakes it in with a
single recursive copy — no per-file translation. It's a sibling of the
top-level `config/`, which is itself a 1:1 mirror of `~/.pi/` (e.g.
`config/web-search.json` mirrors `~/.pi/web-search.json`).

**Config only. Never a secret, token, or key — not even a placeholder
that looks real enough to paste over by accident.**

| File | Purpose |
|---|---|
| `AGENTS.md` | Fallback behavioral guidelines, used only if the mounted project has no AGENTS.md of its own. |
| `settings.json` | Provider/model/compaction settings. |
| `extensions/pi-permission-system/config.json` | The actual allow/ask/deny policy for `@gotgenes/pi-permission-system`. |
| `subagents-worktrees.json` | Opts the `IMPLEMENT` agent type and its per-dispatch `IMPLEMENT-1`..`IMPLEMENT-4` slot copies into isolated git worktrees via `@gotgenes/pi-subagents-worktrees` (`{"worktreeAgents": ["IMPLEMENT", "IMPLEMENT-1", "IMPLEMENT-2", "IMPLEMENT-3", "IMPLEMENT-4"]}`). See AGENTS.md's "Worktrees" section for how that fits the dispatch/validate/stage workflow. |

Credentials live at runtime, outside this directory and outside the
repo entirely — see `compose.yaml`'s auth-store mount.
