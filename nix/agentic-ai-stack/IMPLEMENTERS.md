# nix/agentic-ai-stack — Implementers

A Nix-built, Docker-Compose-run sandbox for running the Pi coding agent
against real projects, with a hard container/network isolation boundary.
See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention, and [README.md](README.md) for the practical "how do I run
it" usage guide — this file is architecture/design, not a usage guide.

## Goal

- A hard, container/network-level isolation boundary around the agent,
  not just app-level permission prompts.
- Reproducible, declarative deployment via Nix — no manual host setup, no
  config drift.
- Multi-provider frontier model access, no local model serving.
- No secrets ever committed to the repo or baked into the Nix store.

This stack runs on native Linux Docker only.

## Threat model

**In scope:** a prompt-injection or misbehaving-agent scenario where `pi`
is induced to run destructive commands, exfiltrate data, or reach
systems/hosts it shouldn't; accidental credential leakage (into git, into
the Nix store, into logs).

**Explicitly out of scope / accepted risk:** a fully malicious, targeted
attack against the host OS itself (not a hard security boundary against a
determined attacker with local code execution already on the host).
Availability/performance guarantees.

**Key architectural principle:** `pi`'s own permission system (ask/allow/
deny prompts, `config/agent/extensions/pi-permission-system/config.json`)
is a *habit-forming guardrail*, not the security boundary. The actual
boundary is container + network isolation — see README.md's "The actual
security boundary" section for the concrete mechanisms (internal-only
network, `cap_drop: [ALL]`, read-only root filesystem,
`no-new-privileges`, RBAC-scoped kubeconfig).

## Components and network access

| Component | Network access |
|---|---|
| `pi` | Internal network only — no direct internet route |
| `proxy` | Internal + external (allowlisted egress for `pi`, plus `domain-gate`'s runtime grant path) |
| `pkg-broker` | Internal + external (its own unproxied leg — not part of `pi`'s egress path) |
| `workspace-mounter`, `nix-store-mounter` | No network; CAP_SYS_ADMIN sidecars that build `pi`'s filesystem views |
| `login` | External only, on-demand compose profile for OAuth |

`proxy` is the only container in `pi`'s egress path and is deliberately
minimal (squid + the `domain-gate` sidecar, nothing else). `pkg-broker`'s
external leg exists purely so nixpkgs attribute resolution can fall back
to building from source — see `containers/pkg-broker/README.md`.
`workspace-mounter`/`nix-store-mounter` need `CAP_SYS_ADMIN` to build
`pi`'s `/workspace` and `/nix/store` views via bind/overlay mounts — see
`containers/workspace-mounter/mount.sh` and
`containers/nix-store-mounter/mount.sh`.

## Build and run flow

Nix's job stops once images are built and loaded into the local Docker
daemon; from there a plain, static `compose.yaml` drives everything (no
Arion or other Nix-aware orchestration layer).

1. `flake.nix` builds `pi-image`, `proxy-image`, `pkg-broker-image`,
   `workspace-mounter-image` via `nix2container.buildImage`.
2. `nix run .#load` calls `copyToDockerDaemon` for each, skipping the
   copy when the image's content-id label already matches what's loaded.
3. `scripts/start-agent.sh` (`nix run .#start-agent`) builds+loads
   images, resolves the workspace layout from `--add`/`--clone`,
   optionally layers `compose.workspace.yaml`/`compose.kube.yaml`, and
   runs `docker compose up`. `scripts/stop-agent.sh` tears it down and
   removes any non-persisted volumes.
4. `scripts/shell-agent.sh` (`nix run .#shell-agent`) opens a raw shell
   into the running `pi` container. `scripts/gen-kubeconfig.sh`
   (`nix run .#gen-kubeconfig`) generates the RBAC-scoped kubeconfig.
5. `scripts/verify-acceptance.sh` (`nix run .#verify`) runs smoke checks
   against an already-running stack.

## Configuration bundling

`config/` is a 1:1 mirror of `~/.pi/` baked into the `pi-image` at build
time — `config/agent/` mirrors `~/.pi/agent/` (`settings.json`,
`AGENTS.md`, `agents/*`, each extension's `config.json`). See
[config/agent/README.md](config/agent/README.md) for the file-by-file
breakdown. **Config only, never a secret** — anything baked into an image
lands in the Nix store, which is world-readable on multi-user systems.
Edit the SOURCE under `config/agent/`, never a deployed copy.

## Credentials

No secrets live in the repo or the Nix store. Two mechanisms, usable
together:

- Static API keys / third-party secrets: `start-agent.sh --secret
  NAME=VALUE` (repeatable) or `PI_SANDBOX__SECRET__<NAME>` host env vars,
  injected as runtime `-e` vars on `docker compose run` — never written
  to a file, never declared by name in `compose.yaml`.
- OAuth: `nix run .#login` (the `login` compose profile) writes
  `auth.json` to the `pi-auth` named Docker volume, shared read-write
  with the `pi` service.

See README.md's "Credentials / secrets" section for the full flag/env
var reference.

## Permission model (Pi-level)

`@gotgenes/pi-permission-system`
(`config/agent/extensions/pi-permission-system/config.json`) provides
pattern-based allow/ask/deny rules for `edit`/`write`/`read`/`bash`. This
is a guardrail on top of the real boundary described above, not a
substitute for it — see "Threat model" above.

## Acceptance criteria

`scripts/verify-acceptance.sh` is the canonical, numbered list of
acceptance checks (egress isolation, read-only root filesystem, no
secrets in git history, `pkg-broker` isolation, the login/auth-volume
flow, `domain-gate` validation). Run it against an already-running stack
with `nix run .#verify`.

## Making changes

- **Adding/changing a container image**: edit the relevant
  `containers/<name>/image.nix` (nix2container build) and
  `flake.nix`'s corresponding `packages.<name>-image`/app wiring.
- **Adding a permanent egress domain**: add a line to
  `containers/proxy/allowed-domains.txt` and rebuild/reload the `proxy`
  image. For a runtime, session-scoped exception instead, see
  README.md's "Requesting an extra domain at runtime" section
  (`domain-gate`/`request-domain`).
- **Changing agent config**: edit the source under `config/agent/` (see
  [config/agent/README.md](config/agent/README.md)) — never a deployed
  copy. Never add a secret here.
- **Updating pinned extensions**: `nix run .#update-pi-extensions`
  (`scripts/update-pi-extensions.sh`) regenerates
  `extensions/package-lock.json`/`git-extensions.nix`; see
  [extensions/README.md](extensions/README.md).
- **Updating pinned skills**: edit `extra-skills.nix` (sources/`enable`
  list) — see README.md's "Agent skills" section for the full add-a-skill
  checklist, including wiring permissions in
  `config/agent/extensions/pi-permission-system/config.json` and/or
  `config/agent/agents/IMPLEMENT.md`.
- **The `IMPLEMENT` agent definition and worktrees**: `config/agent/
  agents/IMPLEMENT.md` is the base template for the implementation
  subagent (locked-down `bash` policy — only the exact `agent-validate`
  invocation granted per-dispatch, plus `git *`/`rm *` for worktree work).
  `config/agent/subagents-worktrees.json` opts `IMPLEMENT` and its
  per-dispatch `IMPLEMENT-1`..`IMPLEMENT-4` slot copies into isolated git
  worktrees via `@gotgenes/pi-subagents-worktrees`. See
  `config/agent/AGENTS.md`'s "Worktrees" section for how dispatch/
  validate/stage fits together, and `containers/pkg-broker/README.md`
  for `pkg-broker`.

## Gotchas

- `pi`'s own image never gets a nix toolchain, a nix-daemon socket, or
  write access to `pkg-broker`'s shared volumes — all nixpkgs resolution
  goes through `pkg-broker`'s narrow `POST /resolve` endpoint via the
  `pkg-install` CLI, which is deliberately **not** allow-listed in `pi`'s
  own permission policy by default (run it manually via
  `nix run .#shell-agent`).
- `proxy`'s root filesystem is read-only; `domain-gate`'s dynamic
  allowlist file lives on the `proxy-domains` named volume, not tmpfs,
  and is truncated on every container start unless `--persist-domains`/
  `PI_SANDBOX__PERSIST_DOMAINS=1` is set.
- `pkg-broker`'s nix sandbox needs targeted `security_opt` opt-outs
  (`seccomp:unconfined`, `apparmor:unconfined`, `systempaths=unconfined`)
  to bind-mount its chroot store — see `containers/pkg-broker/README.md`'s
  "Sandbox note" before changing anything here.
- Never mount a real/production kubeconfig — `scripts/gen-kubeconfig.sh`
  generates a dedicated, RBAC-scoped one pointed at a dev/staging
  cluster; the permission-extension layer additionally denies `kubectl
  apply`/`delete`/`exec` outright.
- `pi`'s `compose.yaml` environment sets `CGO_ENABLED: "0"` and
  `GOCACHE`/`GOPATH`/`GOMODCACHE` under `/tmp/go/` so Go works at all
  inside `pi` (`read_only` root filesystem, no C compiler, HOME's usual
  `~/.cache/go-build`/`~/go` unwritable). `agent-validate` used to default
  these itself (`setup_go_env` in `nix/scripts/scripts/agent/agent-validate/
  run.sh`) but that only covered `agent-validate` runs, not arbitrary Go
  invocations elsewhere in the container — the fix now lives here instead.
  `/tmp` is a tmpfs, so these caches don't survive a stack restart; this
  takes effect the next time the `pi` container (re)starts, not by
  editing a running one.
