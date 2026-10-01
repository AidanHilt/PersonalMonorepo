# Pi Sandbox Stack

A Nix-built, Docker-Compose-run sandbox for running the [Pi coding
agent](https://github.com/earendil-works/pi) against real projects with
a hard, container/network-level isolation boundary — not just Pi's own
ask/allow/deny prompts. See `PROJECT-SPEC.md` for the full design
rationale and threat model; this README is the practical "how do I run
it" summary.

## Layout

```
flake.nix                      # packages: pi-image, proxy-image; apps: load, start-agent, stop-agent, login, gen-kubeconfig, verify
compose.yaml                   # static compose file; images are just images to it once loaded
containers/
  pi/
    image.nix                  # nix2container build for the pi service
    entrypoint.sh
  proxy/
    image.nix                  # nix2container build for the proxy service
    squid.conf                 # egress allowlist (pi's outbound traffic)
    allowed-domains.txt        # user-editable extra egress entries
    supervise.sh                # PID 1: runs squid; fails closed if it dies
config/pi/                     # baked-in AGENTS.md / settings.json / models.json / permission policy — config only, never secrets
scripts/                       # start-agent, stop-agent, gen-kubeconfig, verify-acceptance
kube/                          # legacy/unused; kubeconfig now defaults to
                                # ~/.config/pi-sandbox/agent-kubeconfig.yaml
                                # (override with PI_SANDBOX__KUBECONFIG_PATH), never in-repo
```

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

## The actual security boundary

Pi's permission prompts (`config/pi/extensions/pi-permission-system/config.json`) are
a habit-forming guardrail, not the boundary. The real boundary is:

- `pi` is attached only to the `internal` compose network — no route to
  the public internet except through `proxy`'s allowlist, no published
  ports, `cap_drop: [ALL]`, `read_only` root filesystem, `no-new-privileges`.
- `proxy` is the only container with a leg on the external network, and
  is deliberately minimal (squid, nothing else) since it's the trust
  anchor.
- Kubernetes access is a generated, RBAC-scoped, read-only-mounted
  kubeconfig against a dev/staging cluster — never a real one.

None of this defends against a fully malicious actor with local code
execution already on the host (see spec §2's threat model) — it
contains "agent did something dumb or was manipulated," which is the
actual risk this stack is built for.
