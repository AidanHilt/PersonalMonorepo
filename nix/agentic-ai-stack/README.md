# Pi Sandbox Stack

A Nix-built, Docker-Compose-run sandbox for running the [Pi coding
agent](https://github.com/earendil-works/pi) against real projects with
a hard, container/network-level isolation boundary — not just Pi's own
ask/allow/deny prompts. See `PROJECT-SPEC.md` for the full design
rationale and threat model; this README is the practical "how do I run
it" summary.

## Layout

```
flake.nix                      # packages: pi-image, proxy-image, pkg-broker-image; apps: load, start-agent, stop-agent, shell-agent, login, gen-kubeconfig, verify
compose.yaml                   # static compose file; images are just images to it once loaded
compose.pkgbroker-host-store.yaml  # opt-in override: pkg-broker uses the host's real nix store/daemon
containers/
  pi/
    image.nix                  # nix2container build for the pi service
    entrypoint.sh
  proxy/
    image.nix                  # nix2container build for the proxy service
    squid.conf                 # egress allowlist (pi's outbound traffic)
    allowed-domains.txt        # user-editable extra egress entries
    supervise.sh                # PID 1: runs squid; fails closed if it dies
  pkg-broker/
    image.nix                  # nix2container build for the pkg-broker service
    main.go                    # single POST /resolve endpoint (nixpkgs attr -> published bin/*)
    README.md                  # design, volumes, store-backend tradeoff
    FOLLOWUP.md                # deferred: fuzzy/by-binary-name lookup
config/pi/                     # baked-in AGENTS.md / settings.json / models.json / permission policy — config only, never secrets
scripts/                       # start-agent, stop-agent, shell-agent, gen-kubeconfig, verify-acceptance
kube/                          # legacy/unused; kubeconfig now defaults to
                                # ~/.config/pi-sandbox/agent-kubeconfig.yaml
                                # (override with PI_SANDBOX__KUBECONFIG_PATH), never in-repo
```

`nix/scripts/scripts/pkg-install/` (in the sibling `nix/scripts` flake) is
the thin CLI that calls `pkg-broker` from inside the `pi` container; see
`containers/pkg-broker/README.md` for how the two fit together.

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

## The actual security boundary

Pi's permission prompts (`config/pi/extensions/pi-permission-system/config.json`) are
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
