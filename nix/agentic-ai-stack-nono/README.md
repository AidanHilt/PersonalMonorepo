# Pi Sandbox Stack

A Nix-built, Docker-Compose-run sandbox for running the [Pi coding
agent](https://github.com/earendil-works/pi) against real projects with
a hard, container/network-level isolation boundary — not just Pi's own
ask/allow/deny prompts. See [IMPLEMENTERS.md](IMPLEMENTERS.md) for the
full design rationale and threat model; this README is the practical
"how do I run it" summary.

## Layout

```
flake.nix                      # packages: pi-image, proxy-image, pkg-broker-image, workspace-mounter-image, kind-gateway-image; apps: load, start-agent, stop-agent, shell-agent, login, gen-kubeconfig, verify
compose.yaml                   # static compose file; images are just images to it once loaded
compose.kube.yaml              # opt-in override: mounts a scoped kubeconfig into pi (see below)
compose.kind.yaml              # opt-in override: kind-gateway forwarder sidecar for a local kind cluster (see below)
compose.pkgbroker-host-store.yaml  # opt-in override: pkg-broker uses the host's real nix store/daemon
compose.workspace.yaml         # opt-in: layered when --add/--clone extras are given (see below)
containers/
  pi/
    image.nix                  # nix2container build for the pi service
    entrypoint.sh
  proxy/
    image.nix                  # nix2container build for the proxy service
    squid.conf                 # egress allowlist (pi's outbound traffic)
    allowed-domains.txt        # user-editable extra egress entries (permanent, baked into the image)
    supervise.sh                # PID 1: runs squid + domain-gate; fails closed if either dies
    domain-gate/
      main.go                  # POST /allow: adds one hostname to the egress allowlist for this proxy container's lifetime only
  pkg-broker/
    image.nix                  # nix2container build for the pkg-broker service
    main.go                    # single POST /resolve endpoint (nixpkgs attr -> published bin/*)
    README.md                  # design, volumes, store-backend tradeoff
  nix-store-mounter/
    mount.sh                   # CAP_SYS_ADMIN sidecar, overlays pi's own + pkg-broker's /nix/store
  workspace-mounter/
    image.nix                  # nix2container build for the workspace-mounter sidecar
    mount.sh                   # CAP_SYS_ADMIN+bindfs sidecar, builds /workspace from --add/--clone extras
  kind-gateway/
    image.nix                  # nix2container build for the kind-gateway forwarder sidecar (plain socat)
config/                        # 1:1 mirror of ~/.pi/ -- config only, never secrets
  agent/                       # mirrors ~/.pi/agent/: baked-in AGENTS.md / settings.json / permission policy
  web-search.json              # mirrors ~/.pi/web-search.json: pi-web-access ssrf.trustEnvProxy config
scripts/                       # start-agent, stop-agent, shell-agent, gen-kubeconfig, verify-acceptance
```

### Giving `pi` something to work on (`/workspace`)

`/workspace` has no default content — it starts as an empty tmpfs unless you
pass one or more of these repeatable flags to `start-agent.sh`:

```sh
# A single existing directory, mounted directly AT /workspace:
nix run .#start-agent -- --add ~/code/my-project

# A fresh/cached clone (on the HOST, using your own git credentials),
# also mounted directly AT /workspace since it's the only extra:
nix run .#start-agent -- --clone git@github.com:me/my-project.git

# Two or more extras become siblings under /workspace/<basename>:
nix run .#start-agent -- --add ~/code/my-project --add ~/notes/todo.md
#  -> /workspace/my-project/, /workspace/todo.md
```

A lone `--add`/`--clone` must resolve to a directory (a single bare file is
rejected — point at its containing directory, or add a second extra to use
sibling mode). Two extras sharing a basename is an error. Clones are cached
in `${XDG_CACHE_HOME:-~/.cache}/pi-sandbox/clones/<repo-name>`; re-running
`--clone` against an already-cloned repo only runs `git fetch`, it never
touches the working tree.

When any extras are given, `start-agent.sh` layers `compose.workspace.yaml`
(plus a small generated compose file listing that run's extra source
volumes) on top of the base stack, bringing up the `workspace-mounter`
sidecar (`containers/workspace-mounter/`) to build the merged view — see
that sidecar's `mount.sh` and `scripts/start-agent.sh`'s own header comment
for the full mechanism. This needs native Linux Docker (not Docker
Desktop or any other VM-backed Docker), `/dev/fuse` available on the host, and the same shared mount
propagation `nix-store-mounter` already requires (`sudo mount --make-rshared /`
if `start-agent.sh` warns about it).

`nix/scripts/scripts/pkg-install/` (in the sibling `nix/scripts` flake) is
the thin CLI that calls `pkg-broker` from inside the `pi` container; see
`containers/pkg-broker/README.md` for how the two fit together.
`nix/scripts/scripts/request-domain/` is the analogous CLI for
`domain-gate` — see "Requesting an extra domain at runtime" below.

## The workflow this is designed around

This stack is one piece of a broader plan/dispatch/validate workflow, not
just a place to run `pi` interactively:

1. The user works with the sandboxed, read-only planning agent (`pi`,
   running here) to turn a request into a concrete plan.
2. Before dispatching any implementation work, the planning agent is
   responsible for -- and is the only one capable of -- installing any
   tools the plan's validation will need (`pkg-install`, backed by the
   `pkg-broker` sidecar; see "Installing extra nixpkgs software on
   demand" below and [containers/pkg-broker/README.md](containers/pkg-broker/README.md))
   and requesting any extra network domains (`request-domain`, backed by
   `domain-gate`; see "Requesting an extra domain at runtime" below) --
   the implementation subagent dispatched in the next step can do
   neither itself.
3. The planning agent assembles a self-contained dispatch prompt with
   `agent-plan-create` and dispatches an `IMPLEMENT-n` subagent, which
   works in an isolated git worktree and validates its own work with
   `agent-validate`.
4. `agent-stage` (see
   [nix/scripts/scripts/agent/agent-stage/README.md](../scripts/scripts/agent/agent-stage/README.md))
   squash-stages the subagent's validated branch onto the current branch
   for review, WITHOUT committing.
5. The user reviews the staged diff and commits themselves (`kommit`).
   Planning/dispatch agents never commit.

See [config/agent/README.md](config/agent/README.md) and
`config/agent/AGENTS.md` (baked into the `pi` image) for the full
dispatch/validate/stage mechanics; `agent-plan-create`, `agent-validate`,
`request-domain` and `kommit` don't have their own READMEs beyond that.

## Quickstart

```sh
nix run .#gen-kubeconfig -- <dev-context>  # never a production context
nix run .#login                            # if using OAuth; type /login once inside
nix run .#start-agent                      # builds+loads images, brings up pi+proxy
```

For a local `kind` dev cluster specifically, use `cluster-setup`/
`cluster-teardown` (`nix/mono-flake/modules/roles/universal/
kubernetes-admin.nix`) instead of calling `gen-kubeconfig` by hand --
see "Kubernetes access against a local `kind` cluster" below.

### Credentials / secrets

`start-agent.sh` never retrieves or decrypts secrets itself — it only
accepts already-decrypted values and injects them into the `pi`
container as runtime env vars. No secret name is hardcoded, so adding a
new third-party API key (e.g. `EXA_API_KEY`, `GITHUB_TOKEN`) never
requires editing `compose.yaml` or `start-agent.sh`. Two ways to supply
a secret, usable interchangeably and together:

```sh
# 1. Repeatable --secret NAME=VALUE flags on start-agent.sh
nix run .#start-agent -- --secret ANTHROPIC_API_KEY=sk-... --secret EXA_API_KEY=...

# 2. Host env vars namespaced PI_SANDBOX__SECRET__<NAME>
export PI_SANDBOX__SECRET__GITHUB_TOKEN=ghp_...
nix run .#start-agent
```

If both are set for the same name, the `--secret` flag wins. `.env` /
`.env.example` remain, but are now only for non-secret vars Compose
interpolates into `compose.yaml` (e.g. `PERSONAL_MONOREPO_LOCATION`) —
no API keys belong there anymore.

Tear down: `nix run .#stop-agent` (or `docker compose down`). Verify
the acceptance criteria from the spec against a running stack:
`nix run .#verify`.

### Kubernetes access against a local `kind` cluster

`cluster-setup`/`cluster-teardown` (`nix/mono-flake/modules/roles/
universal/kubernetes-admin.nix`, system packages on hosts that include
that role) create/destroy a local `kind` dev cluster explicitly named
`qa-cluster` (kubeconfig context `kind-qa-cluster`, not kind's bare
default `kind`/`kind-kind` — `terragrunt/qa-cluster`'s
`kubeconfig_context` inputs hardcode `kind-qa-cluster` to match).
`cluster-setup` also writes a scoped kubeconfig straight to this stack's
default path (`${PI_SANDBOX__KUBECONFIG_PATH:-~/.config/pi-sandbox/agent-kubeconfig.yaml}`,
overwriting it silently), by running:

```sh
nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#gen-kubeconfig" -- \
  kind-qa-cluster --yes --server https://kind-gateway:6443 --tls-server-name kubernetes
```

`PERSONAL_MONOREPO_LOCATION` must be set for `cluster-setup` to find this
flake. `--server`/`--tls-server-name` are `gen-kubeconfig.sh` flags (see
`scripts/gen-kubeconfig.sh --help`/its header comment) that point the
generated kubeconfig at the `kind-gateway` service name instead of the
context's own (host-only-reachable) `127.0.0.1:<port>` API address, with
`tls-server-name: kubernetes` so TLS verification still succeeds against
that SAN on kind's apiserver cert. `--yes` skips the interactive
dev/staging confirmation prompt, since `cluster-setup` always targets the
local kind cluster it just created.

`pi` cannot reach `127.0.0.1:<port>` directly — it only sits on the
`internal` compose network (no default route at all), and must NOT join
kind's own `kind` docker network directly either (that network has a real
route to the outside world and would bypass the egress proxy). Instead,
`start-agent.sh` layers `compose.kind.yaml` automatically whenever BOTH a
scoped kubeconfig is found AND the `kind` docker network exists (i.e. a
local kind cluster is actually up) — bringing up `kind-gateway`, a narrow
`socat` forwarder sidecar attached to both `internal` and `kind`, which
forwards only TCP `:6443` to `qa-cluster-control-plane:6443`. See
`compose.kind.yaml`'s header comment and `containers/kind-gateway/image.nix`
for the mechanics; `compose.kind.yaml` also restates `pi`'s `NO_PROXY` to
include `kind-gateway` (traffic to it is never routed through the egress
proxy, same as `proxy`/`pkg-broker`).

Token refresh/RBAC widening are explicitly out of scope here — re-run
`gen-kubeconfig` (directly, or via `cluster-setup`) to refresh the 1h
token; widen the Role in `scripts/gen-kubeconfig.sh` deliberately if an
operator workflow needs more than its narrow read-only default.

The generated kubeconfig file is left world-readable (644), not
owner-only: it's bind-mounted read-only into `pi` by `compose.kube.yaml`,
which keeps the host's owner/mode, and the container's `pi` user
(UID 10001) is never that owner. `start-agent.sh` also re-applies 644 to
an existing kubeconfig on every run, to cover ones written by
`cluster-setup` or left over from before this change. Safety rests on the
token inside being RBAC-scoped, read-only, and short-lived (1h) — not on
file-mode secrecy.

### Persistence flags

Three named Docker volumes other than `pi-auth`/`pi-sessions` (which are
**always** persistent and never touched by this logic) have per-volume,
opt-in-or-opt-out persistence, controlled by `start-agent.sh`/`stop-agent.sh`
flags or matching `PI_SANDBOX__PERSIST_*` env vars (a CLI flag always wins
over its env var). Only the flag that *changes* a default exists — no
`--no-persist-pkgs`, no `--persist-store`, no `--no-persist-domains` — but
the env var can express either value:

| Volume          | Holds                                   | Default      | Flag to change it      | Env var                          |
|-----------------|------------------------------------------|--------------|-------------------------|-----------------------------------|
| `pkg-bin`       | pkg-broker's resolved binaries           | ephemeral    | `--persist-pkgs`        | `PI_SANDBOX__PERSIST_PKGS=1`      |
| `nix-store`     | pkg-broker's own nix store               | persistent   | `--no-persist-store`    | `PI_SANDBOX__PERSIST_STORE=0`     |
| `proxy-domains` | `request-domain` runtime grants          | ephemeral    | `--persist-domains`     | `PI_SANDBOX__PERSIST_DOMAINS=1`   |

"Ephemeral" means `start-agent.sh`/`stop-agent.sh` run an explicit `docker
volume rm` on that volume — never tmpfs/in-memory storage, and never an
`external: true` volume declaration (this stack does not want to own
external volume lifecycle). `start-agent.sh` removes non-persisted volumes
twice: once at the start of a run (to clear leftovers from a crashed
previous run that never reached its own teardown) and once more after
`docker compose down` on normal exit; `stop-agent.sh` does the equivalent
removal after its own `down`.

`--no-persist-store` together with `--host-store` is a hard error: in
host-store mode `pkg-broker` uses the host's real `/nix` instead of the
`nix-store` volume, so that volume is simply unused there and the flag is
meaningless. Combining `--persist-pkgs` with `--no-persist-store` is
allowed but warned about: `pkg-bin`'s symlinks point into paths that live
in the `nix-store` volume, so persisting the symlinks while discarding the
store they point into leaves them dangling.

Run `nix run .#start-agent -- --help` / `nix run .#stop-agent -- --help`
for the full flag/env var reference (printed before any docker/sudo/nix
work runs).

### Session naming & resuming

Every run of `start-agent.sh` gives the session a display name, persisted
(along with its history) on the always-on `pi-sessions` volume (see
"Credentials / secrets" above for the volumes this stack never removes).
Two mutually exclusive flags control this:

```sh
# Name this run's session, prefixed with 'release-notes':
nix run .#start-agent -- --name release-notes
# -> container gets PI_SANDBOX__SESSION_NAME=release-notes-20240521-153000

# Skip naming a new session; instead open pi's own built-in --resume
# session picker inside the container, against the pi-sessions volume:
nix run .#start-agent -- --resume
```

With no `--name`, the prefix defaults to `pi` (e.g.
`pi-20240521-153000`), so every run still gets a unique, timestamped name
even with no flags at all. `start-agent.sh` computes the full name and
forwards it (or `PI_SANDBOX__RESUME=1` for `--resume`) into the `pi`
container as a plain `-e` env var on `docker compose run` — the same
mechanism `--secret` uses — and prints the chosen name/mode before
starting. `containers/pi/entrypoint.sh` translates that into pi's own
`--name`/`--resume` flags. Passing both `--name` and `--resume` is a
hard error. Neither has any effect if `PI_SESSIONS=0` is set on the `pi`
container (sessions disabled outright; `--resume` combined with it only
logs a warning).

### Installing extra nixpkgs software on demand (`pkg-broker`)

An always-on `pkg-broker` sidecar (see `containers/pkg-broker/README.md`)
lets you resolve an exact nixpkgs attribute and get its binaries onto
`pi`'s PATH, without rebuilding the `pi` image and without giving `pi`
itself any nix/network access. The `pkg-install` CLI is baked into the
`pi` image but is **not** allow-listed in `pi`'s own permission policy by
default — run it manually from a raw shell in the running container:

```sh
nix run .#shell-agent    # requires `pi` already running (nix run .#start-agent)
# inside the container:
pkg-install ripgrep
```

### Requesting an extra domain at runtime (`domain-gate`)

The `proxy` container also runs a small `domain-gate` sidecar process
(`containers/proxy/domain-gate/`) alongside squid, listening internally on
port 8081 (never published to the host). It lets `pi` ask, at runtime, for
one exact hostname to be added to squid's egress allowlist — without
editing `allowed-domains.txt` or rebuilding/reloading the `proxy` image:

```sh
# from inside the pi container:
request-domain example.com --reason "fetching release notes for X"
```

By default this is **session-scoped only**: the grant lives in
`dynamic-domains.txt` on the `proxy-domains` named Docker volume (mounted at
`/var/lib/proxy-domains` — `proxy`'s root filesystem is read-only, so a
writable path needs a real volume, not tmpfs), and `supervise.sh` truncates
that file on every container start, so a default-mode grant is wiped the
moment `proxy` restarts — there's no revocation command, just restart
`proxy` (or the whole stack) to clear every dynamic grant at once. Pass
`--persist-domains` to `start-agent.sh` (or set
`PI_SANDBOX__PERSIST_DOMAINS=1`) to keep grants across restarts instead —
see "Persistence flags" below. For a permanent addition, edit
`containers/proxy/allowed-domains.txt` instead and rebuild/reload the image
as usual. Only one exact hostname per call — no wildcards/subdomains, no IP
literals, no internal-looking or compose service names (`domain-gate`'s own
validation enforces this; see its `main.go`).

Approval is entirely `pi`'s own permission system: `request-domain` is
deliberately **not** allow-listed in `config/agent/extensions/pi-permission-system/config.json`
(bash's default is `ask`), so every invocation prompts a human before it
runs — there's no separate pending-request queue. `domain-gate`'s HTTP
endpoint itself is internal-network-only (no host port published), and the
permission policy additionally denies any direct bash access to
`proxy:8081` so `request-domain` stays the only path to it.

Note: `pi`'s `compose.yaml` environment also sets `NODE_USE_ENV_PROXY: "1"`
alongside `HTTP(S)_PROXY`/`NO_PROXY` — Node's global `fetch()` (used by
the `fetch_content` tool etc.) otherwise ignores those proxy env vars and
fails with `getaddrinfo EAI_AGAIN` instead of actually going through
`proxy`'s allowlist. That alone is not sufficient for the `pi-web-access`
extension's `fetch_content`/`web_search` tools, though: that extension's
SSRF pre-flight does its own local DNS lookup on the target host before
honoring any proxy env vars, and `pi` has no DNS resolver (only `proxy`
does) — it fails `getaddrinfo EAI_AGAIN` too, just from a different code
path. `config/web-search.json`'s `ssrf.trustEnvProxy: true` (seeded to
`~/.pi/web-search.json`) tells that extension to skip its own DNS lookup
and trust `HTTPS_PROXY` instead; both settings are required.

Note: `pi`'s `compose.yaml` environment also sets `CGO_ENABLED: "0"` and
points `GOCACHE`/`GOPATH`/`GOMODCACHE` at `/tmp/go/{build,path,mod}` — `pi`
is `read_only` with no C compiler installed, so Go's usual
`~/.cache/go-build` and `~/go` are unwritable and cgo vet would fail
anyway. This makes every Go invocation inside the container work out of
the box, not just checks run through `agent-validate`. Since `/tmp` is a
tmpfs, these caches are lost on every container restart (and are not
affected by any of the persistence flags below, which only cover named
volumes) — Go just recreates the directories on first use, so this only
costs a cold cache, not a failure.

## Agent skills (build-time, pinned)

Like extensions (`extra-extensions.nix`, `extensions/README.md`), skills are
**build-time flake inputs**, not something `pi` fetches or installs at
runtime. `extra-skills.nix` is the skills counterpart of
`extra-extensions.nix`: it pulls in a curated set of third-party
[SKILL.md](https://github.com/Kyure-A/agent-skills-nix)-style skill
directories, pinned by `flake.lock` like any other input, and its output is
copied straight into `$out/home/pi/.pi-seed/agent/skills/` by
`containers/pi/image.nix` — the same mechanism `extra-extensions.nix` uses
for `.../agent/extensions/`. At runtime, the entrypoint copies the whole
`~/.pi-seed` tree into the `~/.pi` tmpfs (see `piSeed` in
`containers/pi/image.nix`), landing skills at their final
`~/.pi/agent/skills/<name>/SKILL.md` location.

Selection/filtering of which skills from each source actually ship is done
with [Kyure-A/agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix)'s
**library only** (`lib.agent-skills`: `discoverCatalog` / `allowlistFor` /
`selectSkills` / `mkBundle`) — its home-manager module and install apps are
deliberately unused, since this stack has no `$HOME` for home-manager to
manage and nothing here should run an installer at build time.

**Lazy loading**: `pi` only puts each skill's name + description in the
system prompt (~100 tokens each); the full `SKILL.md` body is read on demand
when the skill is actually invoked. This is why the enabled list in
`extra-skills.nix` is a deliberately curated subset rather than everything a
source offers — every extra enabled skill is a permanent system-prompt cost
even if it's never used.

**Adding a skill**:

1. Add a `flake = false` input for its source repo to `flake.nix` (pinned by
   `flake.lock` after running `nix flake lock`), and thread it into
   `containers/pi/image.nix`'s call into `extra-skills.nix` the same way
   `skills-golang`/`skills-kubernetes`/`skills-nixos` are.
2. Add a `sources.<name>` entry in `extra-skills.nix` (`path`, optionally
   `subdir`) and add the skill's id to the `enable` list — or, if the
   source doesn't fit `agent-skills-nix`'s discovery (e.g. a repo with
   `SKILL.md` at its root instead of nested under a scanned subdir), copy
   it by hand with a small `pkgs.runCommand`, as `extra-skills.nix` does
   for `kubernetes-skill`. Either way, the final directory name inside the
   bundle **must** equal the skill's `SKILL.md` frontmatter `name` — `pi`
   warns on a mismatch.
3. Set its permission: add it to `permission.skill` in
   `config/agent/extensions/pi-permission-system/config.json` (shared
   planner+implementer policy) and/or to the `skill:` block in
   `config/agent/agents/IMPLEMENT.md`'s frontmatter (implementer-only —
   rules are last-match-wins and merge per-pattern across scopes, so an
   agent-specific file only needs to list the patterns it adds/overrides,
   not the whole surface).
4. Before enabling anything, read its `SKILL.md` and any bundled
   scripts/assets for anything malicious or that needs a tool not already
   in the image.

## The actual security boundary

Pi's permission prompts (`config/agent/extensions/pi-permission-system/config.json`) are
a habit-forming guardrail, not the boundary. The real boundary is:

- `pi` is attached only to the `internal` compose network — no route to
  the public internet except through `proxy`'s allowlist, no published
  ports, `cap_drop: [ALL]`, `read_only` root filesystem, `no-new-privileges`.
- `proxy` and `pkg-broker` are the only containers with a leg on the
  external network. `proxy` is deliberately minimal (squid, nothing
  else) since it's the trust anchor for `pi`'s own egress; `pkg-broker`'s
  external leg is separate and narrow — it exists only so nixpkgs
  attribute resolution can fall back to building from source, and `pi`
  only ever reaches it through one internal-only HTTP endpoint (see
  `containers/pkg-broker/README.md`), never directly.
- Kubernetes access is a generated, RBAC-scoped, read-only-mounted
  kubeconfig against a dev/staging cluster — never a real one. Against a
  local `kind` cluster, `pi` reaches it only through the `kind-gateway`
  forwarder sidecar (plain `socat`, one port, `cap_drop: [ALL]`) — never
  by joining kind's own `kind` docker network directly, which has a real
  route to the outside world (see "Kubernetes access against a local
  `kind` cluster" below). The kubeconfig file itself is world-readable
  (644) on the host, since the bind mount keeps the host mode and the
  container's `pi` user isn't its owner; that's fine because the token in
  it is RBAC-scoped, read-only, and short-lived (1h), not because the
  file is secret.

None of this defends against a fully malicious actor with local code
execution already on the host — it contains "agent did something dumb
or was manipulated," which is the actual risk this stack is built for.
