# Pi Sandbox Stack (nono)

A Nix-built sandbox for running the [Pi coding agent](https://github.com/earendil-works/pi)
against real projects, isolated by [nono](https://github.com/nolabs-ai/nono)
(Landlock on Linux, Seatbelt on macOS) rather than a container boundary. See
[IMPLEMENTERS.md](IMPLEMENTERS.md) for the design rationale and threat
model; this README is the practical "how do I run it" summary.

## Layout

```
flake.nix               # packages: nono, pi-coding-agent, pi-extra-extensions,
                         # pi-extra-skills, approval-helper; apps: start-agent,
                         # attach, ps, stop, shell, gen-kubeconfig,
                         # update-pi-extensions
approval-helper/         # host-side Go process implementing nono's webhook
                         # approval protocol (see "Approvals" below)
profiles/
  work.base.json         # flake-owned base nono profile for start-agent.sh
scripts/
  start-agent.sh, attach.sh, ps.sh, stop.sh, shell.sh
  lib-common.sh          # shared helpers (sourced, not run directly)
  gen-profile.sh         # composes a launch-ready profile from a base +
                         # per-launch filesystem grants
  gen-kubeconfig.sh      # generates an RBAC-scoped kubeconfig
  update-pi-extensions.sh
config/                  # 1:1 mirror of ~/.pi/, layered onto each run's
  agent/                 # PI_CODING_AGENT_DIR at launch -- config only,
  web-search.json         # never a secret
extensions/, extra-extensions.nix   # pre-built npm/git extensions pipeline
extra-skills.nix          # build-time pinned agent skills bundle
```

## Quickstart

```sh
nix run .#start-agent       # starts one nono-sandboxed pi session
```

If using OAuth, trigger `pi`'s own `/login` command once inside that
session instead of a separate login flow — see "Credentials / secrets"
below.

## Giving `pi` something to work on

Your current working directory and every `--add`/`--clone` extra are
shared **live and read-write at their real host path** with `pi` — never
copied anywhere:

```sh
# Your cwd, shared live as nono's own "workdir":
cd ~/code/my-project && nix run .#start-agent

# One or more existing paths, each shared live (repeatable):
nix run .#start-agent -- --add ~/code/my-project --add ~/notes/todo.md

# A fresh/cached clone (on the HOST, using your own git credentials),
# then shared live exactly like --add:
nix run .#start-agent -- --clone git@github.com:me/my-project.git
```

A path is **refused outright** — before anything is shared, for any of
the paths involved — if it's `/`, your entire `$HOME`, or not owned by
you. Sharing is implemented with ACLs (POSIX ACLs/`setfacl` on Linux;
NFSv4-style ACLs/`chmod +a` on macOS), plus a bare traverse (`x`/`search`)
grant on every parent directory up to (excluding) `/` so `pi` can
actually reach the shared path — but only where that's actually needed
and actually yours to grant: a parent `pi` can already traverse (e.g. a
world-traversable `/home` at 755) is left alone; a parent `pi` can't
already traverse that you also don't own (e.g. a root-owned `/home` at
750) makes the whole share **fail outright** with a clear error instead
of ever escalating with `sudo` on your behalf — fix that directory's
permissions as its actual owner (e.g. `chmod o+x`), or share a path
elsewhere.

At shutdown — `start-agent.sh`'s own exit in foreground mode, its
detached-mode wrapper once the session ends, or `nix run .#stop --
<name>` — every shared path has any file ownership `pi` left behind
normalized back to you and its ACL entries removed. This needs an
**interactive `sudo` prompt** (skipped, with a logged note, for any path
another still-running run or shell session also shares). If a launch is
interrupted before that teardown runs (a crash, a killed terminal), run
`nix run .#stop -- <name>` afterwards to finish restoring ownership/ACLs
— safe to run even if nothing needs restoring. `nix run .#shell --
<name>` re-shares the same paths for its own lifetime and releases them
again on its own exit, except it never releases a path while the run's
own main session is still live.

A git repository shared this way is also registered as a
`safe.directory` for both you and `pi` (via `GIT_CONFIG_*` environment
variables passed through `sudo --preserve-env`, never a written
`.gitconfig`), since git refuses to operate inside a directory it
doesn't own by default.

## The workflow this is designed around

This stack is one piece of a broader plan/dispatch/validate workflow, not
just a place to run `pi` interactively:

1. The user works with the sandboxed, read-only planning agent (`pi`,
   running here) to turn a request into a concrete plan. Any tool the
   plan's validation will need must be added to `nix/mono-flake` and the
   host rebuilt — there is no runtime package-install path inside the
   sandbox.
2. The planning agent writes the full plan with `agent-plan-create` (to
   `/tmp/pi-agent-plans/IMPLEMENT-<n>.md`, a path shared with the sandboxed
   worktree) and dispatches an `IMPLEMENT-n` subagent with a short prompt
   telling it to read that file first. The subagent works in an isolated git
   worktree and validates its own work with `agent-validate`.
3. `agent-stage` squash-stages the subagent's validated branch onto the
   current branch for review, WITHOUT committing; `--slot <n>` also removes
   that dispatch's per-dispatch agent definition and plan file.
4. The user reviews the staged diff and commits themselves (`kommit`).
   Planning/dispatch agents never commit.

See [config/agent/README.md](config/agent/README.md) and
`config/agent/AGENTS.md` (layered onto every run) for the full
dispatch/validate/stage mechanics.

## Approvals over SSH / headless hosts (READ THIS if approvals seem to never show up)

`start-agent.sh` starts a host-side `approval-helper` process
outside the sandbox that pops a dialog (or a tmux prompt) every time `pi`
needs to reach a network host not already on the profile's static
allowlist. **If you are connected over SSH, you MUST start a `tmux`
session first and run `nix run .#start-agent` from
inside it:**

```sh
ssh your-host
tmux new -s pi      # start tmux BEFORE launching -- this sets $TMUX
nix run .#start-agent
```

The helper's `--ui auto` selection never silently falls back to denying
every approval when it can't find a usable UI. Concretely, on Linux:

- A desktop dialog (`kdialog`) is only tried when `DISPLAY`/
  `WAYLAND_DISPLAY` is set AND you are **not** in an SSH session
  (`SSH_CONNECTION`/`SSH_TTY` unset).
- A `tmux` command-prompt (`y`=allow once / `n`=deny / `s`=allow for the
  rest of the session) is only tried when `$TMUX` is already set, i.e.
  you launched from inside an existing tmux session on the same tmux
  server the helper itself ends up running on.
- If neither applies, the helper refuses to start at all — a loud,
  non-zero failure with an actionable message, both from the helper
  itself (stderr) and from `start-agent.sh` (which detects the
  helper exiting early and stops immediately rather than silently waiting
  out a timeout). `--ui deny-all` remains available as an explicit,
  intentional opt-in to fail-closed-always, but is never the automatic
  fallback.

macOS uses a native `osascript` dialog instead.

In `--detached` mode specifically, the approval helper runs as **you**
(the invoking user), not as `pi` — this is what lets it inherit your
`$TMUX` at all; a helper started as `pi` can never reach a tmux server it
doesn't own. `start-agent.sh --detached` prints the approval helper's own
log location (a `pi-sandbox-wrapper-<name>.*.log` file under `$TMPDIR`/
`/tmp`) alongside the supervisor's `supervisor.log`, under this session's
own `/tmp/pi-sessions/<name>-<timestamp>/` bookkeeping directory — check
both if a detached session's approvals don't seem to be happening.

Timeouts: the helper waits up to 55s for you to answer a prompt before
failing that one request closed (logged, never silently); the nono
profile (`profiles/work.base.json`) gives the
webhook backend itself 60s before giving up on the helper entirely — the
5s of headroom is intentional, so the helper's own timeout always wins
and gets logged with a reason.

Unlisted hosts always trigger an approval prompt; the static allowlist
(`network.allow_domain` in `profiles/work.base.json`) never prompts.
Grants from an approval are session-scoped only — there is no
persistence of dynamic grants across launches. Metadata/link-local hosts
are always denied outright, without ever asking the helper.

## TLS / CA trust store (`.#start-agent`)

The nono sandbox has no default CA trust store reachable inside it, which
breaks TLS verification for anything `pi` talks to over HTTPS (OAuth
token exchange included) unless a CA bundle is explicitly resolved and
granted. `scripts/start-agent.sh` does this
automatically on every launch — see `IMPLEMENTERS.md`'s "Credentials"
section for the full mechanism. If it can't find a usable bundle on its
own, or you need to point it at a non-default one (e.g. a custom
corporate CA), set:

```sh
export PI_STACK_CA_BUNDLE=/path/to/your/ca-bundle.crt
nix run .#start-agent
```

Resolution order (first existing, readable-by-`pi` file wins):
`$PI_STACK_CA_BUNDLE`, then the invoking shell's own `$NIX_SSL_CERT_FILE`/
`$SSL_CERT_FILE` (so an existing custom-CA setup is preserved), then the
usual system bundle paths (`/etc/ssl/certs/ca-certificates.crt`,
`/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/cert.pem`).

## Credentials / secrets

`start-agent.sh` never retrieves or decrypts secrets itself — it only
accepts already-decrypted values and injects them into the `pi` process
as environment variables, never via argv (never visible via `ps`). Two
ways to supply a secret, usable interchangeably and together:

```sh
# 1. Repeatable --secret NAME=VALUE flags on start-agent.sh
nix run .#start-agent -- --secret ANTHROPIC_API_KEY=sk-... --secret EXA_API_KEY=...

# 2. Host env vars namespaced PI_SANDBOX__SECRET__<NAME>
export PI_SANDBOX__SECRET__GITHUB_TOKEN=ghp_...
nix run .#start-agent
```

If both are set for the same name, the `--secret` flag wins. `.env` has
nothing to hold today (see `.env.example`) — secrets are never read from
it.

OAuth: run `nix run .#start-agent` as normal, then trigger `pi`'s own
`/login` command once inside that session — there is no separate login
flow or flake app. `auth.json` lands straight in the one fixed, shared
agent dir (`/var/lib/pi/.pi/agent/auth.json`), which persists across
every future `start-agent.sh` launch (and every `--name`), so OAuth only
needs to be done once.

> **Migration note**: `/var/lib/pi/login` and `/var/lib/pi/auth` are
> artifacts of an old, separate login flow and are no longer used — they
> can be deleted.

Tear down a run: `nix run .#stop [-- <name>]`.

## Session naming, resuming, and other wrappers

Every `start-agent.sh` launch picks a session name ROOT (`--name`,
default `pi`; the actual nono session name is always
`<name>-<unix-timestamp>`) and a **transient**, per-session bookkeeping
directory under `/tmp/pi-sessions/<name>-<timestamp>/` (override the
root with `PI_STACK_SESSIONS_ROOT`) — nothing in this stack relies on
that directory surviving a reboot or a `/tmp` cleaner sweep. What
actually makes `--resume` (forwarded to `pi` itself) meaningful across
launches is that **every** session, whatever its `--name`, shares the
SAME fixed, persistent `PI_CODING_AGENT_DIR` at `/var/lib/pi/.pi/agent/`
— never deleted, only ever added/overwritten on each launch (idempotent
seeding — see IMPLEMENTERS.md).

```sh
nix run .#ps                     # list every live session
nix run .#attach [-- <name>]     # attach to pi's own TUI session
nix run .#shell [-- <name>]      # a separate interactive shell into the
                                  # same run (works even if the run's own
                                  # pi session/approval helper isn't up)
nix run .#stop [-- <name>]       # stop a run and release its live shares
```

`<name>` is optional on `attach`/`shell`/`stop`: when exactly one MAIN
session is live, it's auto-selected; otherwise (zero or several live, or
— for `stop` only — more than one leftover `/tmp/pi-sessions/<name>`
bookkeeping directory from a crashed launch when nothing is live) these
error, listing the candidates, so you can pass `<name>` explicitly (see
each wrapper's own `--help`). `shell --dry-run` always requires an
explicit `<name>` (auto-select needs a live `sudo -u pi nono ps` call,
which `--dry-run` must never make).

`nix run .#attach -- <name>` fails for a foreground (non-`--detached`)
run, since there's no free PTY to attach a second client to ("Session
<name> already has an active attached client"). Use `nix run .#shell --
<name>` for a plain shell instead — it opens its own nono session
(`<name>-shell`) with its own approval helper, reusing the run's own
filesystem grants (a copy of its `profile.json`, with only the webhook
URL rewritten). Only one shell session is allowed per run at a time, and
`nix run .#stop -- <name>` refuses to stop a run while its shell session
is still open.

`--detached` (on `start-agent.sh`) starts both the session and its
approval helper in the background; `--audit` passes `--audit-integrity`
to `nono run`; `--dry-run` prints the resolved command and planned
ACL/share actions without running anything. Run any script with
`--help` for its full flag reference.

## Kubernetes access against a local `kind` cluster

`cluster-setup`/`cluster-teardown` (`nix/mono-flake/modules/roles/
universal/kubernetes-admin.nix`) create/destroy a local `kind` dev
cluster explicitly named `qa-cluster` (kubeconfig context
`kind-qa-cluster`). `cluster-setup` also writes a scoped kubeconfig
straight to this stack's default path
(`${PI_SANDBOX__KUBECONFIG_PATH:-~/.config/pi-sandbox/agent-kubeconfig.yaml}`,
overwriting it silently), by running:

```sh
nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#gen-kubeconfig" -- \
  kind-qa-cluster --yes --server https://kind-gateway:6443 --tls-server-name kubernetes
```

`PERSONAL_MONOREPO_LOCATION` must be set for `cluster-setup` to find this
flake. `--server`/`--tls-server-name` are `gen-kubeconfig.sh` flags (see
`scripts/gen-kubeconfig.sh --help`) that override the generated
kubeconfig's cluster address/SAN. `--yes` skips the interactive
dev/staging confirmation prompt.

Token refresh/RBAC widening are explicitly out of scope here — re-run
`gen-kubeconfig` (directly, or via `cluster-setup`) to refresh the 1h
token; widen the Role in `scripts/gen-kubeconfig.sh` deliberately if an
operator workflow needs more than its narrow read-only default. Deny-by-
default at the RBAC layer is the real backstop — the permission-
extension `deny` rules on `kubectl apply`/`delete`/`exec`
(`config/agent/extensions/pi-permission-system/config.json`) are defense
in depth on top of this, not a substitute for it.

## Agent skills (build-time, pinned)

Like extensions (`extra-extensions.nix`, `extensions/README.md`), skills
are **build-time flake inputs**, not something `pi` fetches or installs
at runtime. `extra-skills.nix` pulls in a curated set of third-party
[SKILL.md](https://github.com/Kyure-A/agent-skills-nix)-style skill
directories, pinned by `flake.lock` like any other input; `start-agent.sh`
builds `pi-extra-skills` and copies it into each run's
`PI_CODING_AGENT_DIR/skills/` at launch.

Selection/filtering of which skills from each source actually ship is
done with [Kyure-A/agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix)'s
**library only** (`lib.agent-skills`: `discoverCatalog` / `allowlistFor` /
`selectSkills` / `mkBundle`) — its home-manager module and install apps
are deliberately unused, since this stack has no persistent `$HOME` for
home-manager to manage and nothing here should run an installer at build
time.

**Lazy loading**: `pi` only puts each skill's name + description in the
system prompt (~100 tokens each); the full `SKILL.md` body is read on
demand when the skill is actually invoked. This is why the enabled list
in `extra-skills.nix` is a deliberately curated subset rather than
everything a source offers — every extra enabled skill is a permanent
system-prompt cost even if it's never used.

**Adding a skill**:

1. Add a `flake = false` input for its source repo to `flake.nix` (pinned
   by `flake.lock` after running `nix flake lock`), and thread it into
   `extra-skills.nix`'s inputs.
2. Add a `sources.<name>` entry in `extra-skills.nix` (`path`, optionally
   `subdir`) and add the skill's id to the `enable` list — or, if the
   source doesn't fit `agent-skills-nix`'s discovery (e.g. a repo with
   `SKILL.md` at its root instead of nested under a scanned subdir), copy
   it by hand with a small `pkgs.runCommand`, as `extra-skills.nix` does
   for `kubernetes-skill`. Either way, the final directory name inside
   the bundle **must** equal the skill's `SKILL.md` frontmatter `name` —
   `pi` warns on a mismatch.
3. Set its permission: add it to `permission.skill` in
   `config/agent/extensions/pi-permission-system/config.json` (shared
   planner+implementer policy) and/or to the `skill:` block in
   `config/agent/agents/IMPLEMENT.md`'s frontmatter (implementer-only).
4. Before enabling anything, read its `SKILL.md` and any bundled
   scripts/assets for anything malicious or that needs a tool not
   already provisioned.

## The actual security boundary

Pi's own permission prompts
(`config/agent/extensions/pi-permission-system/config.json`) are a
habit-forming guardrail, not the boundary. The real boundary is nono
(Landlock/Seatbelt) plus the untrusted `pi` user — see IMPLEMENTERS.md's
"Threat model" section for the full writeup. None of this defends
against a fully malicious actor with local code execution already on the
host — it contains "agent did something dumb or was manipulated," which
is the actual risk this stack is built for.
