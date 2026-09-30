# Improvement backlog

Ideas for future work on the `agentic-ai-stack`, captured from planning
discussions but not yet implemented. Each item needs its own scoping
conversation before it becomes a `.AGENT-PLAN.md`.

## 2. Dynamic, directory-scoped permissions for subagents

Question to resolve: can a subagent be granted broader `write`/`edit`/
`bash` access scoped specifically to the directory (or directories) it's
actually supposed to touch, rather than either a fixed static policy
(today's `config/pi/extensions/pi-permission-system/config.json` /
`config/pi/agents/*.md` frontmatter) or blanket `yoloMode`? Needs research
into what `@gotgenes/pi-permission-system` actually supports today (path
globs are already a first-class concept in its config — see the `path`,
`path_read`, `path_write` blocks — so this may be more "wire it up
per-dispatch" than "build new capability"), and a decision on whether
scoping happens at dispatch time (the orchestrator computes and injects a
scoped policy per subagent invocation) or some other mechanism.

## 3. More tools in the environment

- **`jq` and `yq`** — DONE. `yq-go` (mikefarah/yq) is now packaged
  alongside `jq` in `flake.nix`'s `devShells.default`, and `"yq *": "allow"`
  is in the permission policy's bash allow-list next to `jq`.
- **Python** — open discussion, not yet decided. Note that the default
  role's current policy explicitly *denies* `python3` in bash (see the
  same config file) — so this isn't just a packaging question, it's also
  a "should the default/planning role be able to eval arbitrary code"
  policy question that needs to be discussed alongside the packaging one.
- **`nix/scripts` as a flake input** — DONE. `scripts` is now a flake
  input of `agentic-ai-stack`'s `flake.nix` (same remote ref as
  mono-flake's), with a `nix run .#scripts-shell` app for local-checkout
  overrides, and its `agent-plan-create` package (see item 5) is wired
  into `devShells.default`. Not wired into the built `pi`/`proxy` container
  images.

## 4. Delete permission for implementation agents, and a policy gap to close

DONE. `IMPLEMENT.md`'s frontmatter now grants explicit `"rm *": allow` and
`"git rm *": allow`, with `"rm -rf *": deny` ordered after them so the
recursive-force case still wins (last-match-wins). The `unlink` gap is
closed with an explicit `"unlink *": allow` rule rather than the previous
silent bash `"*"` fallthrough.

## 5. Default role: permission to create `.AGENT-PLAN.md`

DONE (in a slightly different shape than originally sketched here). Rather
than the default/planning role itself gaining write access, the new
`agent-plan-create` script (`nix/scripts/scripts/agent-plan-create`,
wired into `agentic-ai-stack`'s `devShells.default`) creates/overwrites a
`.AGENT-PLAN.md` at a given path from predefined template fields, refusing
any other filename, refusing to write outside the detected repo, and
refusing to overwrite an existing plan file without `--force`. It also has
a secondary `frontmatter` subcommand for merging key/value pairs into an
agent `.md`'s YAML frontmatter (deliberately generic — no directory-scoping
or dynamic-permission logic; that's item 2, still open).

## 6. Troubleshooter role

Create an agent with the permissions to run debugging commands and test. This
should be a more powerful model with a lot of permissions. Might need to run in
a second container
