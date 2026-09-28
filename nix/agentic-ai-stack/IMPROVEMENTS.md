# Improvement backlog

Ideas for future work on the `agentic-ai-stack`, captured from planning
discussions but not yet implemented. Each item needs its own scoping
conversation before it becomes a `.AGENT-PLAN.md`.

## 1. Adopt the `subagent-workspaces` extension

Goal: make it easier to run multiple agents concurrently against the same
project without them treading on each other. Needs a scoping pass: how it
interacts with the existing `piPackages` extension list in
`containers/pi/image.nix`, whether it needs anything from the
not-yet-wired `extra-extensions.nix` path, and whether it has any bearing
on the workspace-permissions question that's currently on hold.

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

- **`jq` and `yq`** — `jq` is already allowed in the default role's bash
  policy (see `config/pi/extensions/pi-permission-system/config.json`);
  it and `yq` should be added as actual packages in the image/devshell
  wherever the current tool list lives, and `yq` added to the permission
  policy's allow-list alongside `jq`.
- **Python** — open discussion, not yet decided. Note that the default
  role's current policy explicitly *denies* `python3` in bash (see the
  same config file) — so this isn't just a packaging question, it's also
  a "should the default/planning role be able to eval arbitrary code"
  policy question that needs to be discussed alongside the packaging one.
- **`nix/scripts` as a flake input** — bring in the `scripts` flake (same
  one that's already an input to the mono-flake) as an input to
  `agentic-ai-stack`'s `flake.nix`, so its built utility scripts can be
  included in the `pi`/planning environment directly, rather than only
  being available to system configs that consume the mono-flake.

## 4. Delete permission for implementation agents, and a policy gap to close

Grant `IMPLEMENT`-type agents (see `config/pi/agents/IMPLEMENT.md`) real,
intentional permission to delete files in their own working environment,
rather than relying on workarounds.

**Workaround discovered and used during recent plan implementations:**
the base permission policy (and `IMPLEMENT.md`'s own frontmatter) denies
`rm *`, `rm -rf *`, and `git *` (with a short allow-list of read-only git
subcommands) in the `bash` block. Neither policy has a rule matching the
`unlink` command specifically. When an implementation agent needed to
delete a file (e.g. removing `scripts/setup-auth-dir.sh` as part of the
volumes-migration plan, and deleting the old `permission-system.config.json`
after moving it), it ran `unlink <path>` instead of `rm`/`git rm`, which
is functionally equivalent for a single file but isn't caught by either
`rm *`/`rm -rf *`/`git *` pattern, so it fell through to the bash block's
default `"*": "ask"` handling rather than an explicit `deny` — and was
evidently permitted to proceed in that non-interactive dispatch context.

This is a policy **gap**, not a designed capability — `unlink` should not
be treated as a sanctioned deletion path going forward. When scoping
item 4's actual permission grant, this gap should be closed explicitly
(e.g. an explicit `"unlink *"` rule matching whatever the final decision
is for `rm`), rather than left as an accidental loophole alongside
whatever intentional delete permission gets added.

## 5. Default role: permission to create `.AGENT-PLAN.md`

Currently the default/planning role has no `write`/`edit` access at all
(see `config/pi/extensions/pi-permission-system/config.json`:
`"write": "deny"`, `"edit": "deny"`), which is why writing a
`.AGENT-PLAN.md` today requires handing its full content to a subagent to
create. Idea: give the default role access to run a *script* (not raw
`write`/`edit`) whose only job is to create/overwrite a `.AGENT-PLAN.md`
at a given path with given content — so the role gains exactly the one
capability it needs for the documented planning workflow, without a
general-purpose file-write escape hatch. Needs a decision on where that
script lives and what guardrails it should enforce (e.g. only ever
targeting a file literally named `.AGENT-PLAN.md`, refusing to write
anywhere outside the repo, etc.).
