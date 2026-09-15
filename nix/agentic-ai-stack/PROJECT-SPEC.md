# Pi Sandbox Stack — Project Spec

## 1. Goal

Run the [Pi coding agent](https://github.com/earendil-works/pi) against real projects (initially: a monorepo) with:

- A hard, OS-level isolation boundary around the agent, not just app-level permission prompts.
- Reproducible, declarative deployment via Nix — no manual host setup, no config drift.
- Support for both **macOS (via Colima)** and **NixOS**, both already running Docker.
- Multi-provider model access (frontier APIs + a local model), with the local model used for in-the-loop editing/planning and frontier models invoked deliberately for harder tasks.
- No secrets ever committed to the repo or baked into the Nix store.

This document specifies the target architecture and the concrete pieces to build. It assumes the implementer has working knowledge of Nix flakes, `nix2container`, Docker/Compose, and Pi's configuration model, and will look up current syntax/APIs as needed rather than relying on memorized specifics — several of the tools referenced here (Pi, Colima, Ollama) are moving fast and the implementer should verify current CLI/config syntax against upstream docs before finalizing.

## 2. Threat model (what we're defending against, and what we're not)

**In scope:**
- A prompt-injection or misbehaving-agent scenario where Pi is induced to run destructive commands, exfiltrate data, or reach systems/hosts it shouldn't.
- Accidental credential leakage (into git, into the Nix store, into logs).
- A compromised or vulnerable local model server (Ollama) being used as a pivot point from the agent's network segment.

**Explicitly out of scope / accepted risk:**
- A fully malicious, targeted attack against the host OS or hypervisor itself (i.e., we are not defending against nation-state-grade sandbox escapes). Container + network isolation is meant to contain "agent did something dumb or was manipulated," not to be a hard security boundary against a determined attacker with local code execution already.
- Availability/performance guarantees.

**Key architectural principle:** Pi's own permission system (ask/allow/deny prompts) is a *habit-forming guardrail*, not the security boundary. The actual boundary is the container + network isolation described below. Do not treat Pi-level config as sufficient on its own.

## 3. Component overview

Four logical components, three of which are containers:

| Component | Runs as | Network access |
|---|---|---|
| `pi` | Container (Nix-built image) | Internal network only — no direct internet route |
| `proxy` | Container (Nix-built image) | Internal network + external internet (allowlisted egress) |
| `ollama` | **Native process on host** (not containerized) | Bound to a narrow interface; reachable from internal network only through `proxy`'s API gate |
| `login` | Same image as `pi`, alternate compose profile | Bridged/normal network (only run interactively, on demand) |

### 3.1 `pi` container

- Built via `nix2container.buildImage`, contents = Pi + Node runtime + chosen permission extension + bundled config (see §5).
- Non-root user baked in.
- Runs with `--read-only` root filesystem. Explicit `tmpfs` mount for `/tmp`. A named volume or bind mount for Pi's session-persistence directory if session history should survive across runs (decide at implementation time whether this is desired; default to **not** persisting unless asked, to keep runs stateless).
- Mounts:
  - Project directory: read-write bind mount.
  - Scoped kubeconfig (see §6): read-only bind mount.
  - Auth directory (see §7): read-write bind mount, host-side path outside the repo.
- Attached **only** to the `internal` compose network. No published ports. No route to the internet except via `proxy`.
- Capabilities dropped (`cap_drop: [ALL]`), `no-new-privileges` security opt, rootless if the runtime supports it cleanly on both target hosts (verify Colima's rootless story before committing to this — may differ from a NixOS-native Docker rootless setup).
- Other tools (such as Git) as necessary

### 3.2 `proxy` container

- Built via `nix2container.buildImage`. Deliberately minimal — this is the trust anchor of the whole design, keep its own attack surface small.
- Attached to **both** the `internal` network and the external/default network (i.e., it's the only container with real internet access).
- Two responsibilities, which can be one process or two, implementer's choice:
  1. **Egress allowlist** for `pi`'s outbound traffic: permit only the configured model provider API(s) (e.g. Anthropic, OpenAI) and, if extension installation from npm/PyPI is desired, the relevant package registries. Deny everything else by default.
  2. **Ollama API gate**: a narrow reverse proxy in front of the host's native Ollama instance (see §3.3). Allow only inference endpoints — `/api/generate`, `/api/chat`, `/api/embed` (verify current Ollama API path names against upstream docs at implementation time). Deny model-management endpoints (`/api/pull`, `/api/create`, `/api/push`, `/api/delete`, `/api/copy`, and any tensor-transfer endpoints) — these have been the source of real, remotely-exploitable Ollama CVEs (path traversal, arbitrary file write) and are not needed for the agent's actual workflow. Model management is a manual, host-side operation performed outside this stack.
- No filesystem mounts beyond its own config.

### 3.3 `ollama` (native on host, not containerized)

- Rationale: on macOS/Apple Silicon, GPU passthrough into a container (via Colima's `krunkit` VM type) currently costs roughly 15–20% inference throughput versus running natively. Given that overhead, run Ollama natively on the host to get full Metal/CUDA/ROCm acceleration, and treat it as an external service the container network reaches — not something the compose stack builds or manages.
- **This does not mean it's unsandboxed and therefore low-risk.** Ollama is a real network service with its own independently-exploitable attack surface, entirely apart from what the agent asks it to do — it has had multiple CVEs in 2026 alone, including an unauthenticated remote memory-disclosure bug (CVSS 9.1) and a remote path-traversal bug in its model-transfer handling. Treat it as a semi-trusted network service that needs its own hardening, not a passive black box:
  - Bind Ollama's listener to the specific interface reachable from the container network only (loopback + the relevant bridge address) — not `0.0.0.0`.
  - Keep it patched aggressively; check current version against known CVEs before deployment and set a recurring reminder to re-check, since this surface moves fast.
  - Route all container→Ollama traffic through the `proxy` container's API gate (§3.2), not directly — this is what actually limits blast radius from an Ollama-side bug.
- Reachability from containers: verify the current host-loopback-from-container mechanism on both target platforms — Colima's `host.docker.internal`-equivalent behavior and whatever the NixOS-native Docker equivalent is (typically the host-gateway IP or an explicit bridge network route) — these differ by platform and by Docker/Colima version, so confirm current behavior rather than assuming.
- GPU acceleration on NixOS: if the NixOS host has a discrete GPU, this is a non-issue since Ollama runs natively there too — no passthrough question at all. Nvidia/AMD GPU passthrough only becomes relevant if a future decision moves model serving into a container on NixOS.

### 3.4 `login` (compose profile, not a default service)

- Same image as `pi`, started only on demand (`--profile login`), not part of the default `up`.
- Bridged/normal network — needs a real path to the provider's auth endpoint and, if OAuth is used, a way to complete a browser redirect/callback.
- Writes credentials to the same host-side auth directory that the `pi` service mounts, so a completed login is immediately usable by the isolated service.
- **Default assumption: prefer static API keys over OAuth** for exactly this reason — it avoids needing a less-isolated network path at all. Fall back to the OAuth login-service flow only for providers that don't offer key-based auth for the plan/tier in use.

## 4. Build & run flow

Nix's job stops once images are built and loaded into the local Docker daemon. From there, a **plain, static `compose.yaml`** drives everything — do not add Arion or another Nix-aware orchestration layer; once an image is tagged in the daemon, it's indistinguishable from any other image and doesn't need special handling.

1. `nix build` (or a flake app wrapping it) builds:
   - `pi-image` (tag pinned to a stable string, e.g. `pi-sandbox/pi:dev` — **do not** rely on `nix2container`'s default content-hash tag here, since a static compose file needs a tag that doesn't change every rebuild).
   - `proxy-image` (same tagging approach).
2. A flake app (`nix run .#load`) calls `copyToDockerDaemon` for both images. This uses the `docker` CLI under the hood and respects whatever Docker context is active — confirm Colima has set itself as the active context (it does this automatically on `colima start`) or export `DOCKER_HOST` explicitly if not.
3. `docker compose up` (default profile) starts `pi` and `proxy`, attached to the `internal` network as specified. Ollama is assumed already running natively on the host (a setup/health-check step should verify this and fail fast with a clear message if not).
4. `docker compose --profile login up login` is run manually, once, whenever a credential needs to be established or refreshed.

## 5. Configuration bundling

All of the following live **inside the flake repo** and get baked into the `pi-image` at build time, so every run deploys exactly what's committed:

- `AGENTS.md` — behavioral guidelines for Pi.
- `settings.json` — provider/model config, packages, compaction settings.
- Permission extension config (see §8) — the actual allow/ask/deny rules.
- MCP server list, if any are used.

**Hard constraint:** nothing in this bundle may contain a secret. Anything referenced into a Nix-built image lands in the Nix store, which is world-readable on multi-user systems and would leak if these images are ever pushed to a binary cache or registry. Config: yes. Credentials: never — those come from the runtime mounts in §7, not from the image.

## 6. Kubernetes access

- Never mount the operator's real/production kubeconfig.
- Generate a dedicated kubeconfig pointed at a dev/staging cluster context, backed by an RBAC-scoped service account with the minimum permissions needed for the operator work in question.
- Mount this kubeconfig **read-only** into the `pi` container.
- At the permission-extension layer (§8), explicitly deny any `kubectl apply`/`delete`/`exec` patterns outright rather than leaving them at "ask" — app-level prompts are one habitual click from being approved against the wrong context; RBAC scope on the mounted kubeconfig is the real backstop.

## 7. Credentials

- **Frontier provider credentials:** Do not prefer static API keys. Use a the `login` command and a similar process as below
- **Auth persistence for any provider that does need OAuth:** a host-side directory outside the repo (e.g. `~/.config/pi-sandbox/auth/`), permissions locked to `0700`/`0600`, bind-mounted read-write into both the `pi` and `login` services. The `login` service (§3.4) is the only place this directory is ever written to via an interactive flow.
- **Ollama:** no credentials — it's a local, unauthenticated-by-design service, which is exactly why §3.3's network-gating matters.

## 8. Permission model (Pi-level)

Pi's native permission system is minimal (per-tool ask/allow via `--yolo` for all-or-nothing). To get fine-grained, pattern-based allow/ask/deny rules (per-path, per-bash-command), the implementer should evaluate current community permission extensions for Pi, pick one with active maintenance, **read its source before installing**, and share your choice with the user and confirm — these extensions execute code and influence agent behavior, so they're part of the trust surface even though they're not part of the container boundary.

Minimum rule set to configure, regardless of which extension is chosen:

- `edit` / `write`: `ask` by default (not `allow`) — let Pi propose changes freely, require sign-off to apply them, at least initially.
- `read`: deny `.env`, `.env.*`, kubeconfig paths, and any SSH/cloud-credential paths explicitly, even though these shouldn't be mounted into the container in the first place — defense in depth.
- `bash`: allow a short list of known-safe patterns (`git *`, project test/build commands), explicitly `deny` (not just `ask`) destructive patterns (`rm -rf *`, `sudo *`, `kubectl apply *`, `kubectl delete *`, `kubectl exec *`), `ask` for everything else.

Revisit this rule set after initial usage — it's a starting point, not a final answer.

## 9. Cross-platform notes for the implementer

- **macOS/Colima:** confirm the active Docker context before relying on `copyToDockerDaemon`; Colima sets itself as default on `colima start` but this can be overridden by other tooling on the machine. GPU acceleration for Ollama is moot here since Ollama runs natively, but note it for future reference in case some other containerized AI workload is added later (`krunkit` VM type, requires macOS 13+, Apple Silicon, `brew install slp/krunkit/krunkit`).
- **NixOS:** native Docker, no Colima translation layer — simpler in most respects. Confirm GPU passthrough availability/config if the host has a discrete GPU and Ollama should use it (moot if Ollama already runs natively with direct hardware access, which it will by default on NixOS).
- Verify `nix build` can actually produce Linux container images from whichever host is doing the building. On the NixOS box this is native. On the Mac, this requires a Linux builder (either `nix-darwin`'s `nix.linux-builder`, or configuring the NixOS box as a remote builder over SSH) — Nix on Darwin cannot cross-compile these closures without one.

## 10. Open decisions for the implementer to resolve (these have been resolved and answers provided)

- [x] Which Pi permission extension to adopt (§8) — evaluate current options for maintenance activity and read the source: gotgenes/pi-packages (pi-permission-system, v32.0.2 pinned)
- [x] Which local model(s) to run under Ollama, and whether that decision affects Ollama's resource/host requirements: qwen2.5-coder:7b, override via `.env` / `config/pi/models.json`
- [ ] Exact Ollama API endpoint allowlist for the `proxy` gate (§3.2) — verify current path names against the Ollama version being deployed, since API surface has shifted across versions.
- [ ] Confirm current Colima/Docker host-loopback mechanism (§3.3) on the actual Colima version in use.

## 11. Acceptance criteria

- `nix run .#start-agent` on both a fresh macOS/Colima host and a fresh NixOS host produces a working `pi` + `proxy` stack with no manual steps beyond providing credentials, starts the ollama server and docker compose stack, and shuts all down when the session is finished
- `pi` container has no route to the public internet other than through `proxy`'s allowlist — verified by attempting an outbound connection to a non-allowlisted host from inside the `pi` container and confirming it fails.
- `pi` container's root filesystem is read-only — verified by attempting a write outside the mounted paths and confirming it fails.
- Ollama's model-management endpoints are unreachable from the `internal` network — verified by attempting `/api/pull` (or current equivalent) through the path the `pi` container would use, and confirming it's rejected by `proxy`.
- No secret values appear in `git log`, `git diff`, or `nix path-info` output for any built derivation.
- A fresh `login` run correctly populates the host-side auth directory, and a subsequent default-profile `pi` run picks up those credentials without re-authenticating.
