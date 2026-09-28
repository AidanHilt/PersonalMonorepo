# config/pi/

Everything in this directory is baked into the `pi-image` at build time
(spec §5) and therefore ends up in the Nix store, which is world-readable
on multi-user systems and would leak if these images are ever pushed to
a binary cache or registry.

This directory is a direct, 1:1 mirror of the final `~/.pi/agent/` tree
inside the container: every file already lives at its final relative
path (`settings.json`, `models.json`, `AGENTS.md`, `agents/*`,
`extensions/<name>/config.json`, ...), so `image.nix` bakes it in with a
single recursive copy — no per-file translation.

**Config only. Never a secret, token, or key — not even a placeholder
that looks real enough to paste over by accident.**

| File | Purpose |
|---|---|
| `AGENTS.md` | Fallback behavioral guidelines, used only if the mounted project has no AGENTS.md of its own. |
| `settings.json` | Provider/model/compaction settings. |
| `models.json` | Wires the `ollama` provider through `proxy`'s Ollama gate. **Currently inert** — Ollama/proxy gate support is disabled (see `ollama/README.md`, `containers/proxy/supervise.sh`); this file is left in place for when it's revived. |
| `extensions/pi-permission-system/config.json` | The actual allow/ask/deny policy for `@gotgenes/pi-permission-system` (spec §8). |

Credentials live at runtime, outside this directory and outside the
repo entirely — see spec §7 and `compose.yaml`'s auth-store mount.
