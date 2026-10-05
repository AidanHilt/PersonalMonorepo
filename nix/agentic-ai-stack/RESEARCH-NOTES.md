# Research findings for the agentic-ai-stack backlog

Researched 2026-09-28 from pi.dev package pages, npm/GitHub READMEs and the
`@gotgenes/pi-permission-system` docs. Written for a handoff agent that cannot
search, so every claim is tagged:

- **[documented]** stated in a source I read
- **[inferred]** my reasoning from documented behavior; verify before relying on it
- **[unknown]** could not determine; needs a test or a look at the repo

Not visible to me: `containers/pi/image.nix`, `config/agent/**`, `flake.nix`. Any
statement about "your current setup" below is a question for whoever can read them.

---

## 1. "subagent-workspaces" is really `@gotgenes/pi-subagents-worktrees`

No package named `subagent-workspaces` turned up. The match is
`@gotgenes/pi-subagents-worktrees` (v0.3.3, published 2026-09-05). "Workspaces"
comes from the `WorkspaceProvider` seam it plugs into.

### Is it just "install and launch several at once"? Mostly no, in two parts

**Concurrency comes from the core, not the worktree package.** [documented]
`@gotgenes/pi-subagents` (v21.8.0) already runs background agents in parallel
with a queue, default limit 4, tunable via `/subagents:settings`. Foreground
agents bypass the queue. With no worktree package, parallel children all work in
the *same directory* and can overwrite each other.

**The worktree package adds filesystem isolation, opt-in per agent type.** [documented]

### Setup requirements [documented]

1. Install the core first: `npm:@gotgenes/pi-subagents`, then
   `npm:@gotgenes/pi-subagents-worktrees`. **Order in `.pi/settings.json`
   `packages` matters**: the worktree package registers its provider at load time,
   and if the core is not loaded first it silently does nothing.
2. Create `subagents-worktrees.json` listing the agent types to isolate:
   `{ "worktreeAgents": ["general-purpose", "refactorer"] }`.
   Locations: global `~/.pi/agent/subagents-worktrees.json`, project
   `<cwd>/.pi/subagents-worktrees.json` (project overrides global).
3. The project must be a git repo with at least one commit. If worktree creation
   fails for a listed agent (not a repo, no commits, `git worktree add` fails),
   the child run **fails loudly** rather than running unisolated.
4. Agent types not listed run in the parent's directory, exactly as if the
   package were absent. Reasonable to leave read-only agents (Explore, planners)
   unlisted and list only writers.
5. Migration note: the old `isolation: "worktree"` spawn flag and `isolation:`
   frontmatter key were removed from the core. Use `worktreeAgents` instead.

### Behavior [documented]

- Each listed child gets a fresh **detached worktree at `HEAD`**.
- Finished with no changes: worktree removed.
- Finished with changes: committed to branch `pi-agent-<id>`; the result tells
  you `git merge <branch>`. Merging is manual. Two parallel agents touching the
  same files means you resolve conflicts.
- If a commit hook rejects the rescue commit, it retries once with `--no-verify`
  and adds a "hooks were bypassed, review before merging" note.
- If cleanup fails, the worktree is left in place and the result says where.
  At session start, leftover `pi-agent-*` worktrees and unmerged branches are
  named in warnings. `/subagents-worktrees` lists/removes preserved worktrees
  (deliberately a slash command, not an agent tool).
- A child that ends with a question (`ask_parent`) keeps its worktree until you
  answer, so it can resume into it.
- The package never deletes branches.

### What it does NOT isolate [documented + inferred]

- It is git working-tree isolation only. Children still share the same process
  (in-process core), container, network, environment, and `~/.pi` state.
  [documented: "no spawned subprocesses"]
- Permissions are unchanged: the child still runs under permission-system with
  its own agent's `permission:` frontmatter. [documented]
- **Uncommitted parent state is invisible to a child** (worktree is at `HEAD`).
  [inferred from "at HEAD"] This includes an uncommitted or untracked
  `.AGENT-PLAN.md`. If plans are written but not committed before dispatch, an
  isolated child will not find the file; its content must be passed in the
  prompt, or the plan committed first.
- **Gitignored files are absent from a fresh worktree** (`node_modules`, build
  output, `.env`, local caches). [inferred: standard `git worktree` behavior]
  Children that need dependencies may have to install them or be told to.
- **Absolute paths in prompts can point back at the main checkout.** [inferred]
  A child told to edit `/workspace/repo/foo` instead of a relative path would
  edit the parent tree, bypassing isolation.
- The README does not say where worktrees are created on disk. [unknown]

### Container/environment checks for the handoff agent [inferred unless noted]

- `git` must exist in the image and the repo's `.git` must be writable from where
  pi runs. Rescue commits and `git worktree add` write into `.git`.
- Volume-mounted repos can trigger git's "dubious ownership" / `safe.directory`
  errors when the mount owner differs from the pi user.
- The worktree package's git operations run in extension code, not through the
  agent's `bash` tool, so `git *: deny` in bash policy should not block them.
  [inferred] Confirm with one real dispatch.

### Interaction with permission-system [inferred]

- The `external_directory` gate is defined relative to the session's `cwd`.
  [documented] A worktree child's cwd is the worktree, so writes back to the main
  checkout would likely register as external and prompt or deny. This may be a
  useful side effect. Not tested.
- Project-scope permission config (`<cwd>/.pi/extensions/pi-permission-system/config.json`)
  loads only if the project is trusted. [documented] A worktree contains only
  committed `.pi/` files. If your policy is delivered globally by the image, this
  does not matter; if any of it is project-scoped and uncommitted, worktree
  children would not get it.

### Bearing on the on-hold workspace-permissions question

Worktrees give **coarse** scoping for free (the child works in its own directory
tree and the external-directory gate guards the rest). They do not give
fine-grained per-directory grants inside one repo. See item 2 below.

---

## 2. Popular pi extensions (pi.dev catalog, 5,433 packages, downloads are per month as of 2026-09-28)

I read full READMEs only for the packages marked (deep). Everything else is the
catalog blurb, so treat advantages as claimed, not verified.

### Planning and workflow

| Package | Downloads | Notes |
|---|---|---|
| `@plannotator/pi-extension` | 93.7K | Interactive plan review with annotations, annotate agent messages, review code/PRs. Closest match to your `.AGENT-PLAN.md` workflow. |
| `@narumitw/pi-plan-mode` | 25.1K | Read-only `/plan` collaboration mode. |
| `pi-goal-x`, `@schovest/pi-goal`, `@narumitw/pi-goal` | 125K / 38K / 27K | Autonomous `/goal` completion; pi-goal-x adds an independent completion auditor. |
| `@juicesharp/rpiv-todo`, `rpiv-ask-user-question` | 186K / 249K | Persistent model todo list; typed multiple-choice questions instead of guessing. |
| `pi-advisor-flow` | 32.4K | Executor/advisor split. |
| `@akagilnc/pi-workflow-roles` | 46.2K | Role-bound workflows. |

### Code quality and feedback

`pi-lens` (96K: LSP, linters, type-checking feedback), `@gotgenes/pi-autoformat`
(format touched files at turn end, steer the agent only when changes happen),
`pi-simplify` (34.5K: review changed code for clarity), `@ff-labs/pi-fff`
(37.7K: fast fuzzy file/content search), `pi-rewind-hook` (git checkpoints with
file/conversation restore; new).

### Integrations, context, observability

- `pi-mcp-adapter` (1.2M, by far the most popular) connects any MCP server;
  `pi-mcp-extension` (104K) is an alternative.
- `pi-web-access` (444K): web search, URL fetch, GitHub repo cloning, PDF/YouTube.
- `@gotgenes/pi-github-tools`: deterministic CI/release/issue tools.
- Context: `billion-context` (280K), `context-mode` (75K), `pi-memory`,
  `pi-hermes-memory`, `@moyai/pi-session-hoarder`.
- Observability: `@langfuse/pi-observability-plugin` (199K),
  `@langchain/langsmith-pi-extension`, `@raindrop-ai/pi-agent`.
- Auth/provider: `@gotgenes/pi-anthropic-auth`, `pi-claude-bridge`,
  `pi-provider-litellm`.

Security note repeated on every pi.dev page: pi packages execute code and steer
the agent; review source before installing.

---

## 3. Remaining backlog items: what research changes

### Item 2: dynamic directory-scoped permissions

Findings [documented]:
- Path globs already exist and are cross-cutting: `path`, plus directional
  `path_read` / `path_write` and `external_directory(_read/_write)`. `*` matches
  across `/`; `**` is not special. Rules are last-match-wins; `~` and `$HOME` expand.
- Per-agent `permission:` frontmatter overrides project and global config, and
  frontmatter supports nested maps, so a `path_write` allowlist per agent type
  works today. The frontmatter parser is minimal (no arrays, anchors, multiline).
- **The `subagent` tool has no permission parameter.** Its parameters are prompt,
  description, subagent_type, model, thinking, max_turns, run_in_background,
  resume, inherit_context. So "orchestrator injects a scoped policy at dispatch"
  is not a supported call today.
- The authorizer chain (live decision links, e.g. a model judge) **cannot grant
  `allow` on `path` or `external_directory`**. Those are capped to `defer`.
  It cannot be the mechanism for broadening access.
- A directional `path_write: { "*": "deny", "<dir>/*": "allow" }` per agent is the
  documented shape of a scoped-write agent. `*_write` is described as more useful
  as a restriction than as a grant; note that `edit` also reads, so grant both
  directions (or use bare `path`).
- Bash path tokens are gated against these rules, with direction "both" unless the
  command is a proven pure reader. So a path rule constrains `rm`, `unlink`, `mv`
  targets etc. regardless of command name. [documented; applies to items 2 and 4]

Candidate mechanisms the scoping conversation can weigh:
1. Static per-agent frontmatter scoped to fixed directories (works now).
2. Worktree isolation as the coarse scope (section 1).
3. A generated per-dispatch agent file with scoped frontmatter. [inferred]
   Whether `@gotgenes/pi-subagents` re-reads agent files at spawn time or only
   at load/`/reload` is [unknown] and decisive.
4. OS-level containment (bwrap). Real containment, unlike permission-system, which
   is a gate on tool calls and parsed command tokens, not a sandbox. Whether
   bwrap works unprivileged inside your container is [unknown].
5. A feature request upstream for per-dispatch policy.

### Item 4: tools

- **`yq` has two incompatible implementations.** [documented] `mikefarah/yq` (Go,
  standalone binary, own expression language, preserves comments; nixpkgs attr
  `yq-go`) versus `kislyuk/yq` (Python wrapper that shells out to `jq`, jq syntax,
  YAML 1.1 quirks). Both install a binary named `yq`. Decision needed on which.
  The Go one avoids pulling Python into the environment, which matters given the
  open Python question. I did not verify the nixpkgs attribute name for the Python one.
- **`yq -i` edits files in place.** [kislyuk's `--in-place` is documented in its
  README; mikefarah's `-i` is from my general knowledge, not a source I read; the
  policy impact is my inference] `jq` has no in-place mode, so
  the "jq allowed" precedent does not transfer cleanly. If the default role has
  `write: deny` but no `path_write` restriction, an allowed `yq` could still write
  files. Decide how the default role's path policy treats it.
- **Python.** Permission-system inspects command text and path tokens; it does
  not see what an interpreter does internally. `sh -c` and `eval` are floored to
  `ask`; the docs do not say the same for `python -c`. [documented / inferred]
  So allowing Python means allowing arbitrary file writes and network calls
  regardless of `write: deny`. Also worth checking that `node`/`npx` (necessarily
  present for pi) are treated consistently with the `python3` deny. [unknown]
- **`nix/scripts` flake input:** nothing in external docs needed; repo-internal.

### Item 5: delete permission and the `unlink` gap

- Confirmed pattern behavior [documented]: patterns match per top-level command;
  a wildcard-suffixed pattern also matches the bare command; unmatched commands
  fall to the `bash` `"*"` rule.
- **The "unlink was permitted in a non-interactive dispatch" observation
  deserves a check.** [documented] For an in-process child, an `ask` forwards to
  the parent session's UI, and with no responder it fails as "approval
  unavailable" (blocked, not allowed). So `unlink` proceeding means one of: a
  human approved the forwarded prompt, `yoloMode` was on (auto-approves `ask`), or
  the `bash` `"*"` rule was actually `allow`. The review log
  (`~/.pi/agent/extensions/pi-permission-system/logs/pi-permission-system-permission-review.jsonl`)
  records the decider (`forwarded` frame with `decision.kind`). Worth reading before
  deciding what the gap actually was.
- The docs' own recipes prefer an **allowlist** (`"bash": {"*": "deny", "<safe cmd>": "allow"}`)
  over chasing destructive command names. `rm`, `unlink`, `mv`, `find -delete`,
  `truncate`, `git clean` all delete or clobber. A denylist of two names will keep leaking.
- Intentional delete permission can be expressed by path (section 4, item 2), not
  just command name, since path tokens are gated regardless of command.

### Item 6: default role creates `.AGENT-PLAN.md`

- [documented] Registered extension tools are gated by name as their own surface,
  so an alternative to a bash script is a dedicated tool that only writes that one
  filename. Content is not shell-quoted, which avoids heredoc parsing problems.
  Documented limitation: a heredoc combined with `2>&1` and a pipe cannot be
  parsed and forces an `ask`.
- With a script, permission-system sees only the command string and path tokens;
  the script's own internal writes are ungated. The script is therefore the whole
  guardrail (fixed filename, in-repo check, refusing symlink escapes).
- Review log stores bash command text unredacted (truncated to 1000 chars by
  default), so plan content passed on the command line lands in the log.
- Interaction with section 1: an uncommitted `.AGENT-PLAN.md` will not exist in an
  isolated worktree.

### Item 7: troubleshooter role and "second container"

- In-process children live in the parent process, so a second container means an
  out-of-process child. [documented] Permission forwarding for those works via
  the `PI_SUBAGENT_PARENT_SESSION` env var plus files under
  `<agent dir>/sessions/permission-forwarding/`, and the child gives up in about 2 s
  if the parent is not serving. Cross-container operation therefore needs a
  **shared agent-dir volume** and the env var set, and `@gotgenes/pi-subagents`
  does not spawn out-of-process children. [inferred for the shared-volume requirement]
- Related packages: `pi-background-tasks` (child Pi processes, durable tasks),
  `pi-lens` (LSP diagnostics), Langfuse/LangSmith tracing for post-mortems.

---

## 5. Open questions to resolve by reading the repo

1. Which subagent extension does `piPackages` currently list?
2. Does the nix-rendered `.pi/settings.json` preserve package order?
3. Is `yoloMode` on anywhere, and how do dispatches get their permissions?
4. Are packages installed at build time or container start (volume masking)?
5. Does the default role's config have any `path`/`path_write` rules?
6. Are `node`/`npx` handled like `python3` in the default role policy?
7. Does the subagents core re-read agent `.md` files per spawn?

## Sources

- https://pi.dev/packages/@gotgenes/pi-subagents-worktrees
- https://pi.dev/packages/@gotgenes/pi-subagents
- https://pi.dev/packages/pi-subagents
- https://pi.dev/packages/@trim21/personal-pi-extensions
- https://pi.dev/packages (catalog, sorted by downloads)
- https://github.com/gotgenes/pi-packages/blob/main/packages/pi-permission-system/docs/configuration.md
- https://raw.githubusercontent.com/gotgenes/pi-packages/main/packages/pi-permission-system/docs/subagent-integration.md
- https://github.com/gotgenes/pi-anthropic-auth (Docker volume masking note)
- https://latchkey.dev/learn/command-reference/yq-go-vs-python and https://github.com/mikefarah/yq/issues/1392 (yq variants, nixpkgs `yq-go`)

# Task: package agent skills declaratively for the pi image

## Constraints
- Nix-managed image; skills must be pinned (rev + hash) and available with no runtime egress.
- Permission policy is enforced by `@gotgenes/pi-permission-system`. It has a `skill` surface (allow/ask/deny by name pattern), so decide the policy for the skills below.
- Pi loads skills from `~/.pi/agent/skills/<name>/SKILL.md`, `.pi/skills/`, `.agents/skills/`, and from pi packages.
- Every skill's `description` is always in context (~100 tokens each). Prefer a curated subset.

## Packaging patterns (from the flakes' READMEs)

### 1. sudosubin/agents.nix: per-skill pinned derivations via overlay
https://github.com/sudosubin/agents.nix (MIT; ~145k skills from skills.sh/skillsdirectory.com; CI pins each repo to a rev + hash; 14 stars, bot-maintained)

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    agents-nix.url = "github:sudosubin/agents.nix";
  };
  outputs = { nixpkgs, agents-nix, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ agents-nix.overlays.default ];
      };
    in { /* pkgs.agent-skills.github.<owner>.<repo>.<skill-name> */ };
}
```
Install for pi via home-manager (README example):
```nix
{ pkgs, ... }:
{
  home.file.".pi/agent/skills/find-skills" = {
    source = pkgs.agent-skills.github.vercel-labs.skills.find-skills;
    recursive = true;
  };
}
```
Rename: `pkgs.agent-skills.github.vercel-labs.skills.find-skills.override { name = "my-find-skills"; }`
Identifiers are lower-cased `github.<owner>.<repo>.<skill-name>`; quote names that aren't valid Nix identifiers. Skills at a repo root are named after the repo.
Explore: `nix repl` then `:lf github:sudosubin/agents.nix` then `outputs.agent-skills.${builtins.currentSystem}.github.<owner>.<repo>`.

### 2. Kyure-A/agent-skills-nix: declarative sources, selection, targets
https://github.com/Kyure-A/agent-skills-nix (MIT; 200 stars)
- Concepts: `sources` (flake inputs or paths, optional `subdir`, `idPrefix`, `filter.maxDepth`, `filter.nameRegex`), `discover` (recursive SKILL.md scan), `skills.enable` / `skills.enableAll` / `skills.explicit`, and `targets`.
- The `pi` target defaults to `$HOME/.pi/agent/skills` (global) and `.pi/skills` (local). Targets are opt-in: `targets.pi.enable = true;`.
- `structure`: `link` (home.file symlinks), `symlink-tree` or `copy-tree` (rsync in activation).
```nix
sources.openai = { input = "openai-skills"; subdir = "skills"; idPrefix = "openai"; };
sources.anthropic = { input = "anthropic-skills"; subdir = "skills"; idPrefix = "anthropic"; };
skills.enable = [ "openai/pdf" "anthropic/pdf" ];
```
- Explicit skills support `transform`/`packages` to bundle tool binaries next to SKILL.md.
- Also: `apps.<s>.skills-install`, `skills-install-local`, `skills-list`, and `lib.agent-skills.mkShellHook` for devShells.
- Full flake input wiring: read `examples/quickstart/{main,child}/flake.nix` in the repo (not read by me).

### 3. lukasl-dev/pi.nix: bake skills into the pi wrapper
https://github.com/lukasl-dev/pi.nix (MIT)
```nix
programs.pi.coding-agent = {
  enable = true;
  skills = [ ./skills/my-skill ];
  # jail.enable = true;   # bubblewrap; jail has network + writable cwd by default
};
```
or `inputs.pi.lib.mkCodingAgent { inherit pkgs; modules = [{ pi.coding-agent.skills = [ ./skills/my-skill ]; }]; }`.
UNTESTED composition: passing a pinned store path (e.g. an agents.nix derivation or `fetchFromGitHub` result) in that `skills` list.

## Recommended skills (all are plain SKILL.md dirs; review each for bundled scripts before pinning)

| Area | Source | Take | Notes |
|---|---|---|---|
| Go | https://github.com/samber/cc-skills-golang (MIT, 3.3k stars) | `skills/golang-` + code-style, data-structures, database, design-patterns, documentation, error-handling, how-to, modernize, naming, refactoring, safety, testing, troubleshooting, security (the ⭐ set, ~1,100 description tokens); consider concurrency, context, structs-interfaces, lint, dependency-management | Skills cross-reference each other; install related ones together. Skip `golang-gopls` and `golang-pkg-go-dev` unless `gopls`/`godig` are packaged. `allowed-tools` frontmatter mentions Claude tools; harmless in pi as far as I know. Prefer local `go doc` over Context7 for stdlib. |
| Kubernetes + Helm + Kustomize | https://github.com/LukasNiessen/kubernetes-skill | whole repo (SKILL.md at root, `references/` loaded on demand) | Low activation cost; "#1 by stars" is a self-claim. License not checked. |
| Helm (operations) | https://github.com/greedychipmunk/agent-skills, path `helm/SKILL.md` | optional | install/upgrade/rollback/template. Quality unknown. |
| Helm (chart authoring) | https://smithery.ai/skills/mjunaidca/helm-charts | optional | Source repo not identified; find it before pinning. |
| NixOS | https://github.com/michalzubkowicz/nixos-management-skill, dir `nixos-managing/` | yes | flakes, modules, rebuild/rollback, luks, impermanence, anti-patterns. Read only the README. |
| Nix language/packaging | https://smithery.ai/skills/natea/nix | optional | Workflows for build/debug/develop/package/flakes/troubleshoot. Repo not identified. |
| Skip | https://github.com/JEFF7712/nix-agent | no | Experimental MCP server that can patch and switch a system. |

## Docs lookups (not skills; optional)
- Already installed: `@firstpick/pi-extension-nixos-wiki-local`. Read its TECHNICAL.md to see which three repos it clones, and check whether nixpkgs manual and nix.dev are included.
- Optional: `@upstash/context7-pi` (free tier 1,000 calls/month; resolve + docs = 2 calls). Put known IDs in instructions to skip the resolve step: `/kubernetes/website`, `/websites/kubectl_kubernetes_io`, `/golang/go`, `/nixos/nixpkgs`, `/websites/nixos_manual_nixpkgs`, `/nix-community/home-manager`.

## Verify before finishing
1. Whether agents.nix actually indexes the repos above (`nix repl` as shown). If not, use `fetchFromGitHub` with a pinned rev + hash, or an agent-skills-nix source.
2. Exact skill directory names (`ls` the pinned source); the table names are from READMEs.
3. Licenses, and a read of every SKILL.md and any bundled scripts.
4. Pi actually lists them at startup and `/skill:<name>` works.
5. `skill` surface policy in permission-system config for these names.
6. Total description tokens after selection.