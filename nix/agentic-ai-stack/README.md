# Pi Sandbox Stack

A Nix-built, Docker-Compose-run sandbox for running the [Pi coding
agent](https://github.com/earendil-works/pi) against real projects with
a hard, container/network-level isolation boundary — not just Pi's own
ask/allow/deny prompts. See `PROJECT-SPEC.md` for the full design
rationale and threat model; this README is the practical "how do I run
it" summary.

**Read `docs/NOTES-FOR-IMPLEMENTER.md` before your first real run.**
This scaffold was authored without a live Nix daemon or Docker socket
available, so a handful of things (the npm fixed-output-derivation
hash, exact settings.json keys for the pi version in use) need one
verification pass on a real Nix/Docker host. Everything else — the
compose topology, the permission policy, the proxy allowlists, the
package versions pinned in `containers/pi/npm-src/package-lock.json` —
was checked against live upstream sources at authoring time.

## Layout

```
flake.nix                      # packages: pi-image, proxy-image; apps: load, start-agent, stop-agent, login, gen-kubeconfig, verify
compose.yaml                   # static compose file; images are just images to it once loaded
containers/
  pi/
    image.nix                  # nix2container build for the pi service
    entrypoint.sh
    npm-src/                   # pinned package.json + real package-lock.json
  proxy/
    image.nix                  # nix2container build for the proxy service
    squid.conf                 # egress allowlist (pi's outbound traffic)
    allowed-domains.txt        # user-editable extra egress entries
    ollama-gate.nginx.conf.template  # narrow reverse proxy in front of host Ollama
    supervise.sh                # PID 1: runs squid + nginx, fails closed if either dies
config/pi/                     # baked-in AGENTS.md / settings.json / models.json / permission policy — config only, never secrets
scripts/                       # start-agent, stop-agent, gen-kubeconfig, verify-acceptance
ollama/README.md               # native host setup + hardening notes
docs/NOTES-FOR-IMPLEMENTER.md  # what's verified vs. what needs one more check
kube/                          # generated kubeconfig lands here (gitignored)
```

## Quickstart

```sh
cp .env.example .env                       # fill in keys, or plan to use `nix run .#login`
ollama pull qwen2.5-coder:7b               # on the host, natively — see ollama/README.md
nix run .#gen-kubeconfig -- <dev-context>  # never a production context
nix run .#login                            # if using OAuth; type /login once inside
nix run .#start-agent                      # builds+loads images, verifies Ollama, brings up pi+proxy
```

Tear down: `nix run .#stop-agent` (or `docker compose down`). Verify
the acceptance criteria from the spec against a running stack:
`nix run .#verify`.

## The actual security boundary

Pi's permission prompts (`config/pi/permission-system.config.json`) are
a habit-forming guardrail, not the boundary. The real boundary is:

- `pi` is attached only to the `internal` compose network — no route to
  the public internet except through `proxy`'s allowlist, no published
  ports, `cap_drop: [ALL]`, `read_only` root filesystem, `no-new-privileges`.
- `proxy` is the only container with a leg on the external network, and
  is deliberately minimal (squid + nginx, nothing else) since it's the
  trust anchor.
- Ollama runs natively on the host (not containerized, for GPU
  throughput — see `ollama/README.md`) but is only reachable from
  `pi` through `proxy`'s narrow inference-only gate, never directly.
- Kubernetes access is a generated, RBAC-scoped, read-only-mounted
  kubeconfig against a dev/staging cluster — never a real one.

None of this defends against a fully malicious actor with local code
execution already on the host (see spec §2's threat model) — it
contains "agent did something dumb or was manipulated," which is the
actual risk this stack is built for.
