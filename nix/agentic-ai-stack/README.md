# Pi Sandbox Stack

A Nix-built, Docker-Compose-run sandbox for running the [Pi coding
agent](https://github.com/earendil-works/pi) against real projects with
a hard, container/network-level isolation boundary — not just Pi's own
ask/allow/deny prompts. See `PROJECT-SPEC.md` for the full design
rationale and threat model; this README is the practical "how do I run
it" summary.

## Layout

```
flake.nix                      # packages: pi-image, proxy-image, pkg-broker-image, workspace-mounter-image; apps: load, start-agent, stop-agent, shell-agent, login, gen-kubeconfig, verify
compose.yaml                   # static compose file; images are just images to it once loaded
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
    FOLLOWUP.md                # deferred: fuzzy/by-binary-name lookup
  nix-store-mounter/
    mount.sh                   # CAP_SYS_ADMIN sidecar, overlays pi's own + pkg-broker's /nix/store
  workspace-mounter/
    image.nix                  # nix2container build for the workspace-mounter sidecar
    mount.sh                   # CAP_SYS_ADMIN+bindfs sidecar, builds /workspace from --add/--clone extras
config/                        # 1:1 mirror of ~/.pi/ -- config only, never secrets
  agent/                       # mirrors ~/.pi/agent/: baked-in AGENTS.md / settings.json / models.json / permission policy
  web-search.json              # mirrors ~/.pi/web-search.json: pi-web-access ssrf.trustEnvProxy config
scripts/                       # start-agent, stop-agent, shell-agent, gen-kubeconfig, verify-acceptance
kube/                          # legacy/unused; kubeconfig now defaults to
                                # ~/.config/pi-sandbox/agent-kubeconfig.yaml
                                # (override with PI_SANDBOX__KUBECONFIG_PATH), never in-repo
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
for the full mechanism. This needs native Linux Docker (not Colima/Docker
Desktop), `/dev/fuse` available on the host, and the same shared mount
propagation `nix-store-mounter` already requires (`sudo mount --make-rshared /`
if `start-agent.sh` warns about it).

`nix/scripts/scripts/pkg-install/` (in the sibling `nix/scripts` flake) is
the thin CLI that calls `pkg-broker` from inside the `pi` container; see
`containers/pkg-broker/README.md` for how the two fit together.
`nix/scripts/scripts/request-domain/` is the analogous CLI for
`domain-gate` — see "Requesting an extra domain at runtime" below.

## Quickstart

```sh
nix run .#gen-kubeconfig -- <dev-context>  # never a production context
nix run .#login                            # if using OAuth; type /login once inside
nix run .#start-agent                      # builds+loads images, verifies Ollama, brings up pi+proxy
```

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

This is **session-scoped only**: the grant lives in
`/tmp/proxy-runtime/dynamic-domains.txt` on the `proxy` container's tmpfs,
so it's wiped the moment that container restarts — there's no revocation
command, just restart `proxy` to clear every dynamic grant at once. For a
permanent addition, edit `containers/proxy/allowed-domains.txt` instead and
rebuild/reload the image as usual. Only one exact hostname per call — no
wildcards/subdomains, no IP literals, no internal-looking or compose
service names (`domain-gate`'s own validation enforces this; see its
`main.go`).

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
  kubeconfig against a dev/staging cluster — never a real one.

None of this defends against a fully malicious actor with local code
execution already on the host (see spec §2's threat model) — it
contains "agent did something dumb or was manipulated," which is the
actual risk this stack is built for.
