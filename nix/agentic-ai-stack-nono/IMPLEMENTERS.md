# nix/agentic-ai-stack-nono — Implementers

> **Mid-migration note (Phase 4b of `PLAN.md`):** this directory is a
> structural copy of `nix/agentic-ai-stack`, with the container-era code
> (compose files, `containers/`, container-only scripts/flake wiring)
> deleted. The nono work profile (Phase 3), launcher, approval helper
> (Phase 4a), and the `ps`/`attach`/`stop`/`login` wrappers plus the
> `nono-sandbox` extension/skill (Phase 4b) are now built -- see "Work
> profile (Phase 3)", "Launcher and approval helper (Phase 4a)", and
> "Session wrappers, login, and nono-sandbox extension (Phase 4b)" below.
> Still not built: the `nix/scripts` changes (removing `pkg-install`,
> rewriting/removing `request-domain`, updating `agent-plan-create`'s
> messages) and `config/agent/`/`AGENTS.md` permission-rule edits
> (Phase 4c) -- see `PLAN.md` section 4 for the full phase breakdown.
> Everything ELSE below this note still describes the old container
> architecture almost entirely verbatim and is known-stale pending the
> Phase 5 documentation rewrite; do not trust it as a description of this
> copy's current or future behaviour. In particular, known-stale areas:
> - "Threat model", "Components and network access", "Build and run
>   flow", "Credentials", "Acceptance criteria", and "Gotchas" all
>   describe the removed Docker Compose / container boundary.
> - `scripts/shell-agent.sh` and `scripts/stop-agent.sh` were deleted
>   outright (purely container-based) and replaced by `scripts/attach.sh`/
>   `scripts/stop.sh` (Phase 4b, see the new section below).
>   `scripts/verify-acceptance.sh` is still rewritten in Phase 5, not yet
>   built.
> - `flake.nix` no longer builds any container image or exposes
>   `load`/`verify` apps; see its top-of-file comment for what remains
>   (`ps`/`attach`/`stop`/`login` now exist as of Phase 4b, replacing the
>   old `shell-agent`/`stop-agent`/`login` container-era apps).
> - `.env.example` and `.gitignore` have been trimmed of compose-only
>   content; the secrets interface they describe (`--secret`,
>   `PI_SANDBOX__SECRET__<NAME>`) is carried forward unchanged per
>   `PLAN.md`.

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
`no-new-privileges`, RBAC-scoped kubeconfig left world-readable (644) on
the host so the container's non-owning `pi` user can read it — relies
on RBAC scope + token lifetime, not file mode, for safety).

## Components and network access

| Component | Network access |
|---|---|
| `pi` | Internal network only — no direct internet route |
| `proxy` | Internal + external (allowlisted egress for `pi`, plus `domain-gate`'s runtime grant path) |
| `pkg-broker` | Internal + external (its own unproxied leg — not part of `pi`'s egress path) |
| `workspace-mounter`, `nix-store-mounter` | No network; CAP_SYS_ADMIN sidecars that build `pi`'s filesystem views |
| `login` | External only, on-demand compose profile for OAuth |
| `kind-gateway` | Internal + the external, pre-existing `kind` docker network (opt-in, `compose.kind.yaml`) — the ONLY bridge between `pi` and a local kind cluster; `pi` never joins `kind` directly |

### Local `kind` cluster network model (`compose.kind.yaml`)

`nix/mono-flake`'s `cluster-setup`/`cluster-teardown` (`modules/roles/
universal/kubernetes-admin.nix`) create/destroy a local `kind` dev cluster
explicitly named `qa-cluster` (context `kind-qa-cluster`, not kind's bare
default `kind`/`kind-kind`) and, after creation, write an RBAC-scoped
kubeconfig straight to this stack's default path
(`gen-kubeconfig.sh ... --server https://kind-gateway:6443
--tls-server-name kubernetes`, overwriting silently — see README.md's
"Kubernetes access against a local `kind` cluster" section for the full
flag/flow writeup).

`pi` has no route to the host's `127.0.0.1:<port>` kind API address (it
only sits on `internal`, which has no default route at all) and must NOT
be attached to kind's own `kind` docker network directly — that network
has a real route to the outside world and would bypass the egress proxy
entirely, defeating the whole point of `internal`'s isolation. Instead,
`kind-gateway` (`containers/kind-gateway/image.nix`, plain `socat`,
`cap_drop: [ALL]`) sits on BOTH `internal` and `kind`, forwarding only TCP
`:6443` to `qa-cluster-control-plane:6443` — the narrowest possible
bridge between the two networks. `compose.kind.yaml` declares the `kind`
network `external: true` (owned/created by `kind` itself, never by
Compose) and is layered in by `start-agent.sh` only when BOTH a scoped
kubeconfig is found AND `docker network inspect kind` succeeds (i.e. a
local kind cluster is actually up); it also restates `pi`'s `NO_PROXY` to
include `kind-gateway` (not proxied — same precedent as `pkg-broker`).

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
- **Changing the local `kind` cluster network bridge**: edit
  `containers/kind-gateway/image.nix` (image) and/or `compose.kind.yaml`
  (forwarding rule, network attachments) — see "Local `kind` cluster
  network model" above. Keep the forwarding rule narrow (one port, one
  destination) deliberately; widen only if a concrete need arises.
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
  apply`/`delete`/`exec` outright. It's written chmod 644
  (world-readable, not owner-only), since the bind mount keeps the
  host's owner/mode and the container's `pi` user (UID 10001) isn't that
  owner; `start-agent.sh` re-applies 644 on every run to cover
  pre-existing or `cluster-setup`-written files too. That's safe because
  the token inside is RBAC-scoped, read-only, and short-lived (1h) —
  file mode isn't what's keeping it safe. `--yes`/`--server`/`--tls-server-name`
  are optional flags (any position among the arguments) layered on top of
  the original positional `<context> [sa-name] [namespace]` interface —
  added so `cluster-setup` can call it non-interactively against the
  `kind-gateway` server address/SAN (see "Local `kind` cluster network
  model" above) without hardcoding `kind-gateway` into the script itself.
  Token lifetime (1h, no auto-renew beyond re-running the script) and the
  Role's RBAC verb/resource allowlist are both unchanged by any of this.
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

## Work profile (Phase 3)

> This section describes new, nono-specific work and is NOT stale like
> the rest of this file (see the note at the top) -- it covers
> `PLAN.md`'s Phase 3 only (the flake-owned nono "work" profile). The
> launcher/approval-helper wiring that actually invokes this is Phase 4,
> not built yet.

### File layout

- `profiles/work.base.json` -- the flake-owned, static base profile.
  Extends nono's built-in `default`. Vendored from the nolabs-ai `pi`
  pack's `spikes/pi-pack/profiles/pi.json` per `PLAN.md` section 2's
  keep/drop rows: keeps groups `node_runtime`,
  `user_caches_{macos,linux}`, `linux_sysfs_read`, `git_config`,
  `unlink_protection`; `security.signal_mode = isolated`,
  `capability_elevation = false`; `open_urls`; `allow_launch_services`;
  the rollback exclusions. Drops `rust_runtime`, `python_runtime`,
  `nix_runtime`, the pack's `custom_credentials` block, and the
  `$HOME/.pi`/`$HOME/.nvm`/`$HOME/.agents/skills`/`$NONO_PACKAGES`/
  `$NONO_CONFIG/profiles`/`$NONO_CONFIG/profile-drafts` reads. Linux is
  allow-list only: `filesystem.deny` is never used here, since Landlock
  refuses to start with deny-inside-allow (`PLAN.md` section 3, spike
  S3.1). The Nix daemon socket
  (`/nix/var/nix/daemon-socket/socket`) is granted via
  `filesystem.unix_socket`. `network.allow_domain` is seeded with the
  static host whitelist from `PLAN.md`'s "Network mode" row (Anthropic/
  Claude, GitHub, and exa.ai hosts, plus `auth.openai.com` for the OAuth
  flow) and `network.approval_backends`/`approval_defaults` carry a
  `webhook` backend shaped exactly like `spikes/all/approval.template.json`
  (spike-verified), except the URL is the literal placeholder token
  `__APPROVAL_WEBHOOK_URL__` instead of a `__PORT__`/`__TOKEN__` pair --
  `scripts/gen-profile.sh` fills that in at launch time once the Phase 4
  approval helper exists to generate it.
- `scripts/gen-profile.sh` -- composes a launch-ready profile from
  `work.base.json` plus per-launch filesystem grants. Never calls
  `nono` itself (this environment has no `nono` to test against -- see
  "UNVERIFIED" below). `--self-test` exercises its dedupe/substitution
  logic against fixture data with no dependency on `nix` or `nono` (set
  `GEN_PROFILE_CLOSURE_CMD` to override the closure lookup).

### How `gen-profile.sh` composes the final profile

1. Substitutes `__APPROVAL_WEBHOOK_URL__` everywhere it appears in the
   base profile with the actual per-launch webhook URL (passed in by
   the, not-yet-built, Phase 4 approval helper).
2. On Linux, computes the Nix closure (`nix-store -qR`) of
   `/run/current-system/sw` (the host's system profile, so grants track
   `update`; always implicit) plus, for every `--read` path that is
   itself under `/nix/store`, that path's own closure -- falling back to
   granting just that path if the closure lookup fails (today's
   behaviour silently swallowed closure failures and granted nothing at
   all for that root; the fallback is narrower but no longer silently
   drops the grant). `--read` paths OUTSIDE `/nix/store` are never
   closure-expanded at all, just granted as-is. Everything is merged, in
   order, with an **order-preserving deduped** (`awk '!seen[$0]++'`,
   never `sort -u` -- see `PLAN.md` section 3's S3.2 harness-bug note)
   result into `filesystem.read` (read-only, never `filesystem.allow`,
   and never nono's `nix_runtime` group, per the "Exec ceiling (Linux)"
   decision row).
3. On macOS, skips the closure merge entirely rather than guessing at a
   workable substitute -- see the UNVERIFIED list below -- and instead
   grants every `--read` path exactly as given.
4. Adds read-write grants (`filesystem.allow`) for `--workdir`,
   `--state-dir` (the per-run `PI_CODING_AGENT_DIR`, Phase 4), every
   `--add`, and every `--clone`. Judgement call: `--add` paths default
   to read-write (matching `--clone`), since the plan only specified
   this for workdir/state-dir explicitly and `start-agent.sh`'s
   existing `--add` semantics (container era) were already read-write.
5. Every `--read` path that is NOT under `/nix/store` is also appended
   to the `fs_read` array of every `command_policies.commands[].from.
   session.sandbox` that already has one (store paths need not be --
   those sandboxes already grant `/nix/store` itself, e.g.
   `work.base.json`'s `nix` command policy). Never creates an `fs_read`
   array, or a `command_policies` block, where one doesn't already
   exist.
6. Validates the result with `jq empty` and writes it atomically (a
   temp file in `--out`'s own directory, then `mv -f` over the final
   path).

`--extra-closure-root` (the original flag name) was removed outright, no
alias -- `--read` (repeatable) replaces it and subsumes what used to be
two separate concerns (closure-expand a store path; grant a path's read
access at all) into one flag, since both ultimately produce the same
`filesystem.read` entries. See "CA trust-store handling" below for the
main new consumer of non-`/nix/store` `--read` paths.

### UNVERIFIED (no nono binary in this environment to validate against)

- **`command_policies`** (`work.base.json`'s `command_policies` block):
  the KEYS are now schema-sourced, not guessed -- read from nono's own
  `nono-profile.schema.json`
  (`crates/nono-cli/data/nono-profile.schema.json` in the `nolabs-ai/
  nono` repo) and `nono.sh/docs/cli/features/tool-sandbox.md`/
  `dangerous-command-blocking.md`. Top-level shape is
  `{"commands": {<name>: {"from": {"session": ...}}}}`: a bare
  `"deny"` string for the deny-only commands (`update`,
  `nixos-rebuild`, `darwin-rebuild`, `home-manager`, `nix-env`,
  `nix-channel`), and the full edge-policy form
  `{"sandbox": {...}, "invocation_policy": {...}}` for `nix` (mediated,
  not deny-only). `deny_direct_exec_bypass` was removed outright -- it
  takes absolute paths, which a static flake-owned file cannot know in
  advance, and nono already denies direct canonical-path bypass of any
  controlled/deny-only command on its own. `agent-validate` is
  deliberately NOT given a command policy in this pass -- it runs
  through the unmodified session sandbox; **UNVERIFIED**: whether its
  own nested `nix` invocations get attributed through the `nix` command
  policy above (the "nix shim" attribution path) or bypass it entirely
  has not been confirmed against a real `nono` binary. Still
  **UNVERIFIED** beyond the schema shape itself:
  - `invocation_policy` rule evaluation order (whether `deny` is
    checked before `allow`, how overlapping `argv.prefix`/`argv.contains`
    rules interact, whether `default` only applies when no rule
    matches at all) -- the block above relies only on `default: deny`
    plus explicit `allow`/`deny` rules and does not depend on a
    specific evaluation order, but that order itself was not verified.
  - Whether the `nix` command sandbox's `fs_read` of `/nix/store` and
    `/nix/var/nix` (broader than the session sandbox's closure-limited
    read ceiling built by `gen-profile.sh`) is actually sufficient/
    necessary for `nix build`/`eval`/`develop`/`flake check`/`flake
    show` to work in practice -- this is a deliberate trade-off
    (command sandboxes do NOT inherit session grants, per the schema),
    not a spike-verified minimal set.
  - When mediation via `command_policies` is active, the session
    sandbox's own execute grant is reportedly built from every trusted
    `PATH` directory -- how that interacts with `gen-profile.sh`'s
    closure-based read grants (whether it widens exec beyond the
    closure) has not been exercised against a real `nono` binary.
  - Matchers are plain argv predicates with no flag normalisation, so
    `argv.prefix`/`argv.contains` only ever see literal argv tokens in
    the order `nono` received them; a global flag placed before the
    subcommand (e.g. `nix --extra-experimental-features ... build`)
    would shift the subcommand out of `argv.prefix`'s first-token slot
    and could fall through to `default: deny` rather than matching
    `allow`. `NIX_CONFIG` is set via the command sandbox's
    `environment.set_vars` specifically so flake/nix-command
    experimental features don't need an argv flag at all.
- **Environment variable filtering** (`work.base.json`'s top-level
  `environment` block, and the `nix` command policy's nested
  `sandbox.environment`): the field names (`allow_vars`, `deny_vars`,
  `case_insensitive_vars`, `set_vars`) are now schema-sourced, not
  guessed. Confirmed from the schema/docs: exact names and `*` globs
  anywhere in the pattern are both supported, matching is
  case-sensitive by default, and built-in dangerous vars (e.g.
  `LD_PRELOAD`) are always blocked regardless of `allow_vars`. The
  session-level `allow_vars` list (`PATH`, `HOME`, `USER`, `TERM`,
  `LANG`, `LC_*`, `TZ`, `PI_*`, `PI_SANDBOX__SECRET__*`) lets the
  `--secret`/`PI_SANDBOX__SECRET__<NAME>` convention (`PLAN.md`'s
  "Secrets" row) through; still **UNVERIFIED**: actual runtime
  filtering behaviour (e.g. whether a bare `PI_SANDBOX__SECRET__*`
  glob leaks adjacent `PI_SANDBOX__`-prefixed non-secret vars, or
  whether `set_vars` entries are exempt from `allow_vars` filtering)
  against a real `nono` binary.
- **macOS native grants**: `gen-profile.sh` currently adds no
  closure-equivalent grant on macOS at all (see its `TODO(macOS native
  grants)` comment) -- Seatbelt rule-count limits for a closure-sized
  grant list are untested (`PLAN.md` section 6, open item), and macOS
  hasn't been exercised by any spike in this effort at all.
- **`filesystem.allow` vs `filesystem.read` write semantics**: inferred
  from `spikes/all/run.sh`'s S4 profile (`allow` used for a writable
  `$HOME`-like dir alongside a read-only `/nix/store`) and the pi pack's
  `pi.json` (`allow` used for `$HOME/.pi`, a writable agent-state dir);
  not directly asserted by any PASS-reported spike.
- **`unlink_protection` vs worktree cleanup/`agent-stage`**: carried
  over from `PLAN.md` section 6's own open item -- kept per the
  plan's "keep from the pack" row, but its interaction with git
  worktree teardown has not been verified.

## Launcher and approval helper (Phase 4a)

> This section, like "Work profile (Phase 3)" above, is new and NOT
> stale -- it covers `PLAN.md` Phase 4a only (the approval helper and
> `scripts/start-agent.sh`). The `attach`/`ps`/`stop`/`login` wrappers and
> the `nono-sandbox` extension/skill are Phase 4b; the `nix/scripts`
> changes (removing `pkg-install`, rewriting/removing `request-domain`,
> updating `agent-plan-create`'s messages) and `config/agent/` doc/
> permission updates are Phase 4c. Neither is built yet.

### Approval helper (`approval-helper/`)

A stdlib-only Go module (`go.mod` has no `require` block -- see
`flake.nix`'s `packages.approval-helper`, built via `pkgs.buildGoModule`
with `vendorHash = null` since there's nothing to vendor). Runs OUTSIDE
the sandbox, on loopback only, and implements nono's unsigned webhook v1
approval protocol (see `PLAN.md`'s "Approval transport"/"Approval helper
(host side)" decision rows, spike-verified by S1.1-S1.9 against
`spikes/all/handler.sh`/`spikes/all/approval.template.json`):

- Listens on `127.0.0.1:<os-assigned port>`; the bearer token lives in the
  URL path (`/<token>`). A request to any other path gets a bare 404 with
  **no log line at all** -- logging even an access line would risk
  leaking the token into a log file. Startup prints one JSON line
  `{port, token, url}` to stdout once listening (and optionally to
  `--info-file`, written mode `0600`) -- that's how `start-agent.sh` reads
  the webhook URL back.
- Request/response shapes (`types.go`) mirror the spike-verified protocol
  exactly: `{backend, request{capability_type, request_id, session_id,
  host, port, protocol, resolved_ips, reason, child_pid}}` in, `{decision:
  granted|denied(+reason)|granted_session}` out.
- `server.go`'s `decide()` applies, in order: a per-HOST `granted_session`
  cache (kept for the helper's whole process lifetime), a per-`host:port`
  deny cache (`--deny-cache-secs`, default 30s), then in-flight prompt
  dedupe (concurrent requests for the same `host:port` share one prompt
  instead of popping two dialogs) -- only then does it fall back to
  `prompt.go`'s `prompter` interface. A UI error or `--timeout` (default
  **55s**, down from an earlier 120s -- see "Timeout alignment" below)
  expiry is always mapped to `denied` -- fail closed, never a grant.
  `promptAndResolve` now also LOGS every such failure via `server.go`'s
  logger (`host:port`, the underlying error, and whether it was a plain
  UI error vs a timeout specifically, via `errors.Is(ctx.Err(),
  context.DeadlineExceeded)`) -- it never logs the bearer token (the
  token only ever appears in the URL path, which never reaches this
  method). Previously these errors were swallowed silently, which was one
  of the two root causes (together with the `auto`-mode selection bug
  below) behind approvals silently behaving as deny-all with no visible
  reason.
- UI selection (`--ui auto|osascript|kdialog|tmux|deny-all`, `prompt.go`'s
  `selectPrompter`) -- **rewritten to never silently fall back to
  deny-all**: `auto` tries `osascript` on Darwin; then, on Linux, tries
  `kdialog` ONLY if `DISPLAY`/`WAYLAND_DISPLAY` is set AND neither
  `SSH_CONNECTION` nor `SSH_TTY` is set (an SSH client's `DISPLAY` can't
  pop a dialog anyone can see); then tries `tmux` ONLY if `$TMUX` is
  already non-empty (both as the Linux fallback and as Darwin's own
  fallback when `osascript` isn't found -- unchanged in spirit from
  before, just now gated on `$TMUX` rather than merely `tmux` being on
  `PATH`). If nothing matches, `selectPrompter` now returns an ERROR (not
  `denyAllPrompter`) with an actionable message ("start tmux first and
  launch from inside it; or pass --ui deny-all explicitly"); `deny-all`
  remains available, but only via an explicit `--ui deny-all`.
  `selectPrompter` also returns a short, human-readable description of
  the prompter chosen (and why); `main.go` creates its logger BEFORE
  calling `selectPrompter` so both a selection failure and (on success)
  the chosen prompter get logged to stderr, and exits non-zero on a
  selection failure before binding the loopback listener or writing
  `--info-file` at all -- a misconfigured host (most commonly SSH with no
  tmux) now fails loudly at helper startup instead of quietly denying
  every approval it's asked about later. This was the other root cause of
  the "approvals silently denied" bug: over SSH with a `DISPLAY` set but
  no reachable X server, `auto` used to try (and fail) `kdialog`, match
  nothing else, and fall back to `denyAllPrompter` with no log line at
  all. Every concrete prompter implementation (`osascriptPrompter`,
  `kdialogPrompter`, `tmuxPrompter`) remains **UNVERIFIED** -- no nono
  binary and no live macOS/KDE/tmux session was available in this
  environment to exercise any of them; `denyAllPrompter`, the
  dedupe/cache/decision-mapping logic in `server.go`, AND
  `selectPrompter`'s full branch matrix (including the SSH-aware/`$TMUX`-
  gated rules above and the no-usable-UI error path) are exercised by
  `main_test.go`'s table tests (via a fake `prompter`/fake
  `lookPath`/`getenv`).
- `--parent-pid PID`: polls (every 1s, via `kill(PID, 0)` -- a pure
  existence/permission check, no signal is actually delivered) and shuts
  down once that PID is gone, so a foreground launcher's helper exits
  when the launcher does, without needing its own signal plumbing beyond
  the standard SIGINT/SIGTERM handling already in `main.go`. In
  `--detached` mode specifically, this now points at the invoking-user-
  owned `wrapper.sh` process (see "Detached mode" below), not at any
  `pi`-owned process -- a `kill(pid, 0)` from the helper (also running as
  the invoking user) only works at all when both processes share the same
  user.
- **Timeout alignment**: `defaultPromptTimeout` (`server.go`) is now
  **55s**, deliberately kept below the `network.approval_backends.
  dialog.timeout_secs` the nono profiles set for the webhook backend
  (`profiles/work.base.json`, `profiles/login.base.json`, both now
  **60s**, up from an earlier 10s). Before this fix the helper's own 120s
  default was actually LONGER than the profiles' 10s webhook timeout, so
  nono itself would give up and treat the request as denied well before
  the helper ever got a chance to resolve (and log) its own outcome -- the
  5s of headroom here (55s helper vs 60s nono) is intentional so the
  helper's own timeout always fires first and gets logged with a reason,
  rather than nono's own silent timeout winning the race.

### Launcher (`scripts/start-agent.sh`)

Completely rewritten (container/compose/kind logic deleted outright, per
`PLAN.md`'s "Delete as obsolete" list). Flags map to the old->new table in
`PLAN.md` section 2: `--profile work` (only value), `--audit` (->
`nono --audit-integrity`), `--detached` (-> `nono run --detached`),
`--add`/`--clone` (real host paths now, no more `/workspace/<basename>`),
`--secret`/`PI_SANDBOX__SECRET__<NAME>` (unchanged convention, different
plumbing -- see "Secrets handoff" below), `--name` (nono's own session
name), `--resume` (pi's own flag, forwarded after `--`), `--dry-run`
(prints the resolved command, secrets redacted by name only, performs NO
directory creation/sudo/nono calls). `--host-store`, `--persist-pkgs`,
`--no-persist-store`, and `--persist-domains` are gone entirely (no
replacement -- there is no pkg-broker/proxy/kind layering left to
configure).

**Read-as-invoking-user / write-as-`pi` split**: every write under
`/var/lib/pi` goes through a narrow `sudo -u pi <cmd>` invocation
(`mkdir`, `tee`, `tar -xf`, `cp` from a world-readable Nix store path);
every read of the invoking user's own files (the workdir, `--add`/
`--clone` sources, `config/agent/`) runs as the invoking user. The
`tar_copy_to_pi`/`write_as_pi` helpers stream bytes through a pipe rather
than ever granting either user direct filesystem access into the other's
trust domain -- this is what lets the launcher work without the invoking
user needing traversal rights into pi-owned directories, or `pi` needing
read access into the invoking user's home.

**Per-run state layout** (`/var/lib/pi/runs/<name>/`, `<name>` defaulting
to `"pi"` -- deliberately NOT timestamp-suffixed like the old
container-era default, since a fresh name every run would defeat the
idempotent-seeding/`--resume` model below):
```
pi/agent/            <- PI_CODING_AGENT_DIR
  extensions/         <- pi-extra-extensions build output (copied first)
  skills/             <- pi-extra-skills build output (copied first)
  settings.json, AGENTS.md, agents/*, extensions/pi-permission-system/
                      <- config/agent/ layered on top (same order container
                         image.nix's piSeed used: extensions/skills first,
                         config/ on top, never destructively)
pi/web-search.json    <- config/web-search.json
state/sessions/       <- part of the gen-profile.sh --state-dir grant
                         (XDG_STATE_HOME-ish scratch space for this run;
                         NOT where pi's auth.json lives -- see "Shared
                         OAuth auth seeding" below)
workdir/              <- pi-owned copy of the invoking user's cwd (this
                         becomes nono's own "workdir": `nono run` is
                         invoked with this as its cwd, combined with
                         `--allow-cwd` and the profile's
                         `workdir.access: readwrite`)
add-N/, clone-N/      <- one dir per --add/--clone extra, each its own
                         gen-profile.sh --add/--clone grant
profile.json          <- the gen-profile.sh output actually passed to
                         `nono run --profile`
supervisor.sh, supervisor.log, approval-helper-info.json
                      <- --detached mode only, see below
```
**Idempotent seeding / `--resume`**: every launch re-syncs
`pi/agent/{extensions,skills}/` and layers `config/agent/`+
`config/web-search.json` on top again, but NEVER deletes the run
directory first -- it only adds/overwrites those specific paths. Judgement
call: this means re-running with the SAME `--name` reuses the same
pi-owned workdir copy and PI_CODING_AGENT_DIR tree, so anything `pi`
itself writes there (its own session history, included, wherever `pi`
internally keeps that under `PI_CODING_AGENT_DIR`) survives across
launches -- that's what makes `--resume` meaningful at all here. This is a
judgement call, not a spike-verified fact: no spike exercised `pi --resume`
against a per-run `PI_CODING_AGENT_DIR` tree.

**Tool path resolution**: this stack flake -- not `nix/mono-flake` --
owns provisioning both `pi` and `nono` (follow-up decision, superseding
what this section originally said). `flake.nix` re-adds a
`nixpkgs-unstable` input (`github:NixOS/nixpkgs/nixos-unstable`, same ref
the old container-era `nix/agentic-ai-stack/flake.nix` used) and a
per-system `pkgsUnstable` built from it with **no overlay** (the old
`pi-coding-agent-overlay.nix` trim overlay stays deleted; plain unstable
`pi-coding-agent` is used as-is, and unstable's `nono` is confirmed >=
0.81.0, same as what `nix/mono-flake` already uses). Both are exposed as
top-level packages (`nix build .#nono`, `nix build .#pi-coding-agent`,
aliasing `pkgsUnstable.nono`/`pkgsUnstable.pi-coding-agent`).
`apps.start-agent`'s `writeShellApplication` wrapper exports their
absolute store paths -- plus `jq` and this flake's own `approval-helper`
package -- as `PI_STACK_NONO_BIN`, `PI_STACK_PI_BIN`, `PI_STACK_JQ_BIN`,
`PI_STACK_APPROVAL_HELPER_BIN` env vars before `scripts/start-agent.sh`
runs. The script's `resolve_stack_bin` helper reads those first (via
`readlink -f`, so they're still real, symlink-resolved store paths --
needed both for `sudo -u pi` to not depend on whatever `secure_path` gives
`pi`, and for `nix-store -qR` inside `gen-profile.sh`), and only falls
back to `command -v $name` on the invoking user's PATH (with a loud
warning pointing at `nix run .#start-agent`) if the script is somehow run
directly, outside the flake wrapper. `nono`'s mono-flake systemPackage
(`modules/roles/universal/_pi-user.nix`'s `pkgs-unstable.nono`) is now
redundant for this launcher specifically -- it remains in `nix/mono-flake`
only for host-side commands (the `attach`/`ps`/`stop` wrappers planned for
Phase 4b, which run as the invoking user rather than through this flake's
apps).

**`flake.lock` follow-up required**: adding the `nixpkgs-unstable` input
adds `flake.lock` entries that could not be re-locked from inside the
sandbox this change was authored in (no network, `nix` itself blocked
outside the one allowed `agent-validate` invocation) -- `flake.lock` was
deliberately left UNEDITED. **The user must run `nix flake lock` in
`nix/agentic-ai-stack-nono` on a host with network access before this
flake will evaluate.**

**`nix build` dependency**: resolving `pi-extra-extensions`/
`pi-extra-skills`'s store paths at launch time uses `nix build
"$STACK_DIR#pi-extra-extensions" --no-link --print-out-paths` (and
similarly for skills) -- `nix` itself is assumed to already be on the
invoking user's `PATH` (true on any NixOS/nix-darwin host that can run
`nix run .#start-agent` in the first place) rather than declared as a
`runtimeInput`, matching `gen-profile.sh`'s own pre-existing assumption
that `nix-store` is already ambient.

**Secrets handoff**: `--secret NAME=VALUE` / `PI_SANDBOX__SECRET__<NAME>`
are `export`ed as real environment variables on the launcher process
itself (never appended to any command's argv), then threaded through
`sudo --preserve-env=<comma-separated names>` -- the `sudo` invocation's
own argv only ever lists variable NAMES, never values, so a `ps` of the
launcher process cannot recover a secret value (`PLAN.md`'s "Secrets" row:
"never via argv, since that is visible via ps"). This relies on the
NOPASSWD+SETENV sudo rule in `nix/mono-flake`'s `_pi-user-linux.nix`/
`_pi-user-darwin.nix`.

**CA trust-store handling**: the sandbox has no default CA trust store
reachable inside it -- the profile's `environment.allow_vars` strips any
CA env vars by default, and the usual system CA bundle path
(`/etc/ssl/certs/ca-certificates.crt`, a symlink chain through `/etc/
static` into `/nix/store` on NixOS) isn't covered by the sandbox's read
grants on its own, which breaks TLS verification for anything `pi` talks
to over HTTPS (e.g. `nix run .#login`'s OAuth token exchange). Both
`start-agent.sh` and `login.sh` call `lib-common.sh`'s `resolve_ca_bundle`
(duplicated into `start-agent.sh` itself rather than sourced, matching
that script's existing `resolve_or_die`/`resolve_stack_bin` convention --
see `lib-common.sh`'s own header comment) to find a host CA bundle
(`$PI_STACK_CA_BUNDLE` override, then the caller's own
`$NIX_SSL_CERT_FILE`/`$SSL_CERT_FILE`, then the usual system paths), then:
  - grant its PARENT DIRECTORY (not the bundle file itself) via
    `gen-profile.sh --read` -- **UNVERIFIED**: whether nono profiles
    accept single-file grants was not confirmed against a real `nono`
    binary, so the parent directory is granted instead, out of caution;
  - export `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, and
    `NODE_EXTRA_CA_CERTS` (covering OpenSSL/Node's and Nix's own CA
    lookup conventions) set to the resolved bundle path, and add all
    three to the `sudo -u pi --preserve-env=...` list that launches nono.
`profiles/work.base.json` and `profiles/login.base.json` both allow-list
those same three vars in their top-level `environment.allow_vars` (and
`work.base.json`'s `nix` command policy additionally allow-lists them in
its own nested `sandbox.environment.allow_vars`) -- without that, the
exported env vars would be stripped from the sandboxed process regardless
of being set outside it. The old container-era stack never hit this: it
baked `SSL_CERT_FILE` into the `pi` image at build time (see
`nix/agentic-ai-stack/containers/pi/image.nix`), which has no `nono`
equivalent here -- the CA bundle must be resolved and granted fresh on
every launch instead. On NixOS, the resolved bundle is itself a
`/nix/store` path, so its parent directory closure-expands via the same
`/nix/store` handling as any other `--read` path (a trivial closure, in
practice).

**Detached mode (option A: the approval helper runs as the invoking
user, not `pi`)**: an earlier version of this had `--detached` hand the
ENTIRE rest of the lifecycle -- including the approval helper -- to a
single `supervisor.sh` run wholly as `pi` (`setsid sudo -u pi -- bash -c
'exec bash "$1" >"$2" 2>&1 </dev/null' ...`). That was broken: a helper
started as `pi` can never reach the invoking user's tmux server (the
`--ui auto` fallback for any headless/SSH host), so detached-mode
approvals silently had no usable prompter and fell straight through to
the old silent-deny-all bug described above. `--detached` now splits the
lifecycle across three pieces instead:

1. **`supervisor.sh`** (pi-owned, runs as `pi`, logging to
   `$RUN_DIR/supervisor.log` same as before) -- unchanged in spirit,
   EXCEPT it no longer starts or stops the approval helper itself. It now
   takes the already-running helper's webhook URL as its one positional
   argument (`${1:?...}`), generates the profile, runs `nono run
   --detached`, then polls plain `nono ps | grep <name>` every 5s until
   the session is gone, and exits (no helper to kill any more -- that's
   the wrapper's job, see below). **UNVERIFIED judgement call**
   (carried over unchanged): this polling loop is modelled directly on
   `spikes/all/run.sh`'s S5.1-S5.3 (`nono ps`'s output format was only
   ever grepped for a session name substring there, never parsed
   structurally), but no nono binary was available in this environment to
   confirm that behaviour beyond what those PASS-reported spikes already
   exercised.
2. **`wrapper.sh`** (owned AND RUN by the invoking user, written to a
   fresh `mktemp -d`-created scratch directory under `$XDG_RUNTIME_DIR`/
   `$TMPDIR`/`/tmp` -- deliberately NOT under the pi-owned `$RUN_DIR`,
   since the invoking user has no write access there): started via
   `setsid bash "$WRAPPER_SCRIPT" >>"$WRAPPER_LOG" 2>&1 </dev/null &
   disown` (persistent log OUTSIDE that scratch dir, under `$TMPDIR`/
   `/tmp`, so it survives the scratch dir's own cleanup). As the invoking
   user, it:
   - starts the approval helper (`--ui auto --info-file ... --parent-pid
     "$$"` -- `$$` here is the WRAPPER's own PID, not the launcher's or
     `pi`'s; the wrapper runs as the invoking user for its whole life, so
     the helper's `kill(pid, 0)` liveness poll actually works against it,
     unlike pointing it at a `pi`-owned process),
   - polls for the helper's `--info-file` to appear (same `kill -0`-aware
     loop as the foreground/`login.sh` fix above -- if the helper exits
     early, e.g. no tmux, a failure marker file is written and the
     wrapper exits non-zero instead of hanging),
   - reads the webhook URL back out of that info file,
   - runs `sudo -u pi --preserve-env="$PRESERVE_LIST" -- bash -c 'exec
     bash "$1" "$2" >"$3" 2>&1 </dev/null' bash "$SUPERVISOR_SCRIPT"
     "$WEBHOOK_URL" "$RUN_DIR/supervisor.log"` IN THE FOREGROUND (the log
     redirect still has to happen INSIDE the sudo'd process, since the
     invoking user still has no write access into the pi-owned run
     directory to open `supervisor.log` itself first -- that part is
     unchanged from before, just now parameterized with the webhook URL
     as an extra positional arg),
   - and once that returns, kills the helper and `rm -rf`s its own
     scratch directory (removing the `--info-file`, which holds the
     bearer token -- cleaned up, not left lying around).
3. **The launcher itself** (`start-agent.sh`, still attached to the
   terminal) starts the wrapper (`setsid ... & disown`) and then BLOCKS,
   briefly (the same 50x0.1s poll shape used elsewhere in this script),
   watching for the helper's `--info-file` to appear (success) or the
   wrapper's failure marker / the wrapper process itself exiting
   (failure) -- i.e. it confirms the approval helper actually came up
   BEFORE returning control to the user, printing both the wrapper's log
   location and the supervisor's log location either way. On failure it
   exits non-zero with a message pointing at the wrapper's log (which
   holds the helper's own stderr) and the tmux requirement, rather than
   silently leaving a broken detached session behind.

**Sudo non-interactivity**: the wrapper's `sudo -u pi` call happens AFTER
this launcher has already detached -- if that `sudo` needed an
interactive password prompt at that point, with no controlling terminal,
it would simply fail. This still relies on the same NOPASSWD+SETENV sudo
rule every other `sudo -u pi` call in this script already depends on (see
`nix/mono-flake`'s `_pi-user-linux.nix`/`_pi-user-darwin.nix`); the
launcher also runs a bare `sudo -v` right before building the wrapper, as
a defensive/documentary measure (priming the credential cache while still
attached), not because the NOPASSWD rule is expected to need it.

There is deliberately no cross-user (`aidan` watching `pi`'s sessions)
story here yet -- that's `PLAN.md`'s S5.4/"cross-user session registry"
open item, left to the Phase 4b `ps`/`attach`/`stop` wrappers.

**Getting results back out**: this launcher does not automate syncing
`workdir/` changes back to the invoking user's own checkout (unlike the
unrelated `agent-stage`/worktree flow IMPLEMENT subagents use) -- per
`PLAN.md`'s "Sharing files between aidan and pi" decision row, that's a
deliberate UX choice, not a gap: the user inspects/diffs/copies the
per-run `workdir/` copy manually.

**Shared OAuth auth seeding**: `/var/lib/pi/auth/auth.json` (written by
`scripts/login.sh`, see below) is the one cross-run, cross-session shared
state this stack has. It is **never granted to any nono session** -- it
sits entirely outside every run's own filesystem grants. Every
`start-agent.sh` launch instead seeds a per-run COPY from it into
`$AGENT_DIR/auth.json` (`$RUN_DIR/pi/agent/auth.json`, i.e. inside
`PI_CODING_AGENT_DIR` itself, NOT the separate per-run `state/` tree), as
`pi`, mode `0600`, right after that run's `config/agent/` layering (so a
seeded token can never be clobbered by it, even though `config/agent/`
contains no `auth.json` today). The copy is skipped if the run-local file
already exists and is not older than the shared source (`[ "$src" -nt
"$dst" ]`), so a run that has itself refreshed its own auth (e.g. via a
`pi` login performed inside that very session) is never clobbered by an
older shared copy on a later restart. Confirmed by a real `nix run
.#login` run: `pi` writes `auth.json` straight into
`PI_CODING_AGENT_DIR`, not into any separate `state/`-style directory --
an earlier draft of this script guessed `$STATE_DIR/auth/auth.json`
(matching `spikes/pi-pack/skills/nono-sandbox/SKILL.md`'s doc of
`~/.pi/agent/auth.json`'s *parent* layout but not pi's actual write
target), which `pi` never reads, silently requiring re-login on every
run; that guess has been corrected.

## Session wrappers, login, and nono-sandbox extension (Phase 4b)

> This section, like "Work profile (Phase 3)" and "Launcher and approval
> helper (Phase 4a)" above, is new and NOT stale -- it covers `PLAN.md`
> Phase 4b: the `ps`/`attach`/`stop`/`login` wrappers and the
> `nono-sandbox` extension/skill. The `nix/scripts` changes and
> `config/agent/`/`AGENTS.md` permission-rule edits are Phase 4c, not
> built yet.

### `scripts/lib-common.sh`

A small, `source`d-only helper shared by `ps.sh`/`attach.sh`/`stop.sh`/
`login.sh` (NOT by `start-agent.sh`, which predates it and keeps its own
copies of the same tool-resolution/CA-bundle helpers rather than being
sourced itself -- see `resolve_ca_bundle` below): `resolve_or_die`/
`resolve_stack_bin` (identical in shape to `start-agent.sh`'s own),
`RUNS_ROOT=/var/lib/pi/runs`, `validate_run_name` (anchors a run name to
`^[A-Za-z0-9._-]+$`, rejecting anything that could path-traverse out of
`$RUNS_ROOT`), `require_run_dir` (validates a name and fails clearly if
that run's directory doesn't exist), `nono_state_dir_for` (validates a
run name and prints the SINGLE canonical path for that run's nono
`XDG_STATE_HOME`, `/var/lib/pi/<name>-nono-xdg-state` -- a sibling of
`$RUNS_ROOT`, not nested under it; see "Per-run state layout" above and
its own call-out below), and `resolve_ca_bundle` (resolves the host's CA
bundle for `login.sh`'s own TLS trust needs -- see "CA trust-store
handling" below; duplicated, not called, by `start-agent.sh`, following
that script's own pre-existing non-sourcing convention). Requires
`PERSONAL_MONOREPO_LOCATION` (same convention as `start-agent.sh`) and
computes `STACK_DIR` from it.

**`nono_state_dir_for` and `start-agent.sh`'s own copy of it must agree
exactly**: `start-agent.sh` doesn't source `lib-common.sh` (see above), so
it carries its own duplicate `validate_run_name`/`nono_state_dir_for`
pair, header-commented as needing to stay in sync with this file's copy.
A past bug here (now fixed) was exactly this kind of drift:
`start-agent.sh` wrote nono's `XDG_STATE_HOME` to
`/var/lib/pi/<name>-nono-xdg-state` while `ps.sh`/`attach.sh`/`stop.sh`
looked for it at `$RUNS_ROOT/<name>/nono-xdg-state` -- a run's real
session state lived at the former path, so `nix run .#ps`/`.#attach`
found nothing (the latter path, when it existed at all, held nothing but
stray files from an unrelated manual `nono ps` run against it).
`nono_state_dir_for` now gives both scripts one place to agree.

### `scripts/ps.sh` (`nix run .#ps`)

There is no single, cross-run `nono ps` -- every run has its own nono
`XDG_STATE_HOME` at `/var/lib/pi/<name>-nono-xdg-state` (a sibling of
`$RUNS_ROOT`, see "Per-run state layout" above and `lib-common.sh`'s
`nono_state_dir_for`), and nono has no cross-run session registry
(`PLAN.md`'s S5.4 open item, left unresolved upstream). `ps.sh` loops over
every `/var/lib/pi/runs/<name>/` run directory it finds, computes that
run's nono state dir via `nono_state_dir_for`, skips it if that state dir
doesn't exist, and otherwise runs `sudo -u pi env XDG_STATE_HOME=<dir>
nono ps` once per run. It prints a combined, `== run: <name> ==`-labelled
table, treating empty `nono ps` output (a successful call, zero sessions)
as "nothing to show" for that run -- but a non-zero exit from `nono ps`
itself is surfaced, not silently skipped: it's printed to stderr as a
labelled `== run: <name> == (nono ps failed: ...)` line and the script
moves on to the next run, so a single broken run doesn't hide its own
failure OR break the rest of the listing.

### `scripts/attach.sh <name>` / `scripts/stop.sh <name>` (`nix run .#attach
-- <name>` / `nix run .#stop -- <name>`)

Replace the old container-era `shell-agent`/`stop-agent`. Both validate
`<name>` via `lib-common.sh`'s `require_run_dir` (rejecting path
traversal and a nonexistent run directory up front), then run `nono
attach <name>` / `nono stop <name>` as `pi`, against that run's own nono
`XDG_STATE_HOME` (`lib-common.sh`'s `nono_state_dir_for`,
`/var/lib/pi/<name>-nono-xdg-state`) -- the same per-run split `ps.sh`
uses. `attach.sh` only uses `require_run_dir`'s existence check, not its
returned run-dir path, since that path has nothing to do with the state
dir it actually runs against.

**`stop.sh` deletes the per-run nono state dir after a successful stop,
preserving `nono/audit`**: nono records audit history under
`<XDG_STATE_HOME>/nono/audit`, which is worth keeping around after a
session ends; everything else under the state dir is disposable
per-session scratch state. On a successful `nono stop`, `stop.sh` deletes
everything directly under the state dir except the `nono/` directory
itself, then everything under `nono/` except `audit/` -- net effect, only
`nono/audit` survives. If the state dir has no `nono/audit` subtree at
all, it's removed outright instead of being left as an empty shell. If
`nono stop` itself fails, nothing is deleted, and `stop.sh` exits
non-zero.

**The approval helper's lifecycle is NOT `stop.sh`'s job.** An earlier
version of this script tried a best-effort, PID-less teardown of the
approval helper here (reading a port out of
`$RUN_DIR/approval-helper-info.json` and killing whatever was listening
on it via `fuser`/`lsof`) -- that's been removed. The helper is already
fully owned elsewhere: for a foreground run, by `start-agent.sh`'s own
launcher process (dies with the launcher, via its `trap ... EXIT`); for a
detached run, by the invoking-user wrapper `start-agent.sh` starts (see
"Detached mode" above), which stops the helper itself once the pi-owned
supervisor it's waiting on returns -- and `nono stop` is exactly what
makes that supervisor's `nono ps` poll loop notice the session is gone
and return. `pkgs.psmisc` (`fuser`) has since been removed from
`apps.stop`'s `runtimeInputs` in `flake.nix` -- it was stale leftover
from this removed teardown, no longer referenced by `stop.sh` at all --
see "`flake.nix`: new apps" below.

**`stop.sh` also refuses outright (before stopping or deleting anything)
if a `"<name>-shell"` nono session is still running** -- i.e. `scripts/
shell.sh` (see below) has an open shell against this same run. Since
`shell.sh` reuses the run's own nono `XDG_STATE_HOME`, tearing that state
dir down (or even just calling `nono stop <name>`) while a shell session
is still attached to it would be surprising; the user is told to exit
the shell first. This check (`lib-common.sh`'s `nono_session_running`,
shared with `shell.sh`'s own "one shell per run" refusal -- see below)
runs before the existing `nono stop <name>` call, so a run with an open
shell is left completely untouched, not partially torn down.

### `scripts/login.sh` (`nix run .#login`)

Replaces the old container-era `login` compose profile. Runs `pi`'s
native OAuth login flow INSIDE a minimal nono session, as `pi`, using
`profiles/login.base.json` (see below) rather than `profiles/
work.base.json`.

**Directory layout**, all directly under `/var/lib/pi/login/` (none
nested inside one another beyond that single level -- `PI_ROOT`
(`/var/lib/pi/login`) itself is never granted to the sandbox, only its
subdirectories are, so nothing here is ever a *parent* of the
`nono-xdg-state/` dir, honouring the "never grant a parent of a
nono-xdg-state dir" rule):
```
agent/              <- PI_CODING_AGENT_DIR; wiped (rm -rf) and recreated
                       FRESH every run, then layered with config/agent/
                       the same way start-agent.sh does -- login is a
                       one-off flow, not a --resume'able work session, so
                       there is no idempotent-seeding story to preserve
                       here. Judgement call: layering config/agent/ here
                       at all (settings.json defaults, extensions/skills)
                       was not explicitly required by this phase's
                       dispatch, but seemed necessary for `pi` to have
                       any provider/model defaults to log in against;
                       noted here as a deviation worth re-confirming.
                       `pi` writes its resulting auth.json directly here,
                       at agent/auth.json -- confirmed by a real login
                       run (see "Shared OAuth auth seeding" above); no
                       separate --state-dir grant is needed or passed for
                       this profile.
nono-xdg-state/     <- XDG_STATE_HOME for the nono process itself (same
                       overlap-avoidance pattern as start-agent.sh)
profile.json
```

**Approval helper**: started exactly like `start-agent.sh`'s foreground
mode (`--ui auto`, `--info-file`, `--parent-pid "$$"`, torn down via a
`trap ... EXIT`) -- this is duplicated, not factored into
`lib-common.sh`, per this phase's own dispatch note that the duplication
should stay minimal and local rather than be shared.

**Triggering the login flow itself is UNVERIFIED and NOT automated**: no
non-interactive `pi` login subcommand is documented anywhere in this
checkout (`config/agent/`, `extensions/README.md`) that this script could
drive on the user's behalf. `login.sh` starts `pi` inside the sandbox
interactively (`nono run --profile ... --allow-cwd --name pi-login --
<pi>`) and expects the USER to trigger login themselves from inside that
session (e.g. a `/login` command, if one exists) and then exit the
session normally. Once `pi` exits, `login.sh` copies whatever landed at
`agent/auth.json` to the shared `/var/lib/pi/auth/auth.json` (`install -m
0600`, as `pi`) -- or, if nothing is there, logs a warning that login may
not have completed, rather than silently treating a missing file as
success.

**`profiles/login.base.json`**: a minimal sibling of `work.base.json`,
same `groups.include` list (`node_runtime`, `user_caches_{macos,linux}`,
`linux_sysfs_read`, `git_config`, `unlink_protection`) and the same
`network`/`open_urls` blocks (including the webhook approval backend and
`allow_localhost: true`, needed for the OAuth callback) -- but with NO
`unix_socket` grant (no nix daemon access for a login session) and NO
`command_policies` block at all. Judgement call: `allow_launch_services:
true` was added (not explicitly listed in this phase's dispatch) because
the reused `open_urls` block is meaningless without it -- `pi` needs to be
able to actually launch the OAuth URL in a browser for the flow to work
at all. `scripts/gen-profile.sh` itself needed NO changes to support this
profile -- its `// []` jq fallbacks already tolerate the missing
`unix_socket` key, and `--workdir` already covers the one read-write
grant `login.sh` needs (`agent/`, which is also where `pi` writes its
resulting `auth.json` -- no separate `--state-dir` grant is used here).

### `scripts/shell.sh <name>` (`nix run .#shell -- <name>`)

> Unlike every other section in "Session wrappers, login, and
> nono-sandbox extension (Phase 4b)", this one was added AFTER that
> phase, not as part of it -- see this script's own header comment. It
> replaces the old container-era `shell-agent` (`scripts/shell-agent.sh`,
> deleted outright per the top-of-file migration note), which
> `attach.sh` does NOT serve the same purpose as: `nono attach <name>`
> attaches to `pi`'s own TUI PTY, and fails outright for a foreground run
> ("Session <name> already has an active attached client" -- there is no
> free PTY to attach a second client to).

Opens a separate, interactive `bash -i` inside its OWN nono session
(`"<name>-shell"`), reusing the target run's nono `XDG_STATE_HOME`
(`lib-common.sh`'s `nono_state_dir_for`, same as `attach.sh`/`stop.sh`)
so it's labelled under that run in `nono ps`/`ps.sh`, and a per-invocation
COPY of that run's own `profile.json` -- not a call into
`gen-profile.sh` -- with only its webhook approval URL rewritten via
`jq`. The run's own `profile.json` is never modified; the copy
(`$RUN_DIR/shell-profile.json`) is regenerated (overwritten) on every
invocation. **Judgement call (decision 1A in this feature's own plan):**
no `gen-profile.sh` re-composition here at all -- this deliberately
doesn't re-implement its base/closure logic, so the shell's filesystem
grants are exactly whatever the run's own `profile.json` already has
(from whenever `start-agent.sh` last generated it), not independently
recomputed.

**Own approval helper, not the run's.** Exactly like `start-agent.sh`'s
foreground mode / `login.sh` (duplicated, not factored into
`lib-common.sh`, matching their own precedent): started as the invoking
user, `--ui auto --info-file ... --parent-pid "$$"`, torn down via
`trap ... EXIT`. This means `shell.sh` works whether or not the run's
own `pi` session (and its helper) is still alive -- it never depends on
either.

**One shell per run.** Before starting its own helper, `shell.sh` checks
(`lib-common.sh`'s `nono_session_running`, shared with `stop.sh`'s own
refusal -- see above) whether a `"<name>-shell"` session is already
running against the run's state dir, and refuses outright if so -- there
is no support for multiple concurrent shells against one run. This is
the same `nono ps`-substring-grep approach `start-agent.sh`'s detached-
mode supervisor already uses, carrying the same **UNVERIFIED** caveat
(no real `nono` binary in this environment to confirm its output shape,
or to rule out a false-positive substring match against a longer session
name that happens to contain this one, e.g. `"<name>-shell"` vs.
`"<name>-shell-2"`).

**`profile.json` must already exist.** `shell.sh` requires the target
run to already have a `profile.json` (i.e. to have been started at least
once via `start-agent.sh`) -- read via `sudo -u pi cat`, since it's
`pi`-owned -- and errors with "run `<name>` has no profile.json -- start
it with start-agent first" otherwise. It does not create or seed any
other part of the run's state (no `pi/agent/` reseeding, no workdir
copy) -- that's entirely `start-agent.sh`'s job.

**Environment**: identical to `start-agent.sh`'s foreground mode --
`PI_CODING_AGENT_DIR` (the run's `pi/agent/`), `XDG_STATE_HOME` (the
run's nono state dir), and the three CA vars (`SSL_CERT_FILE`/
`NIX_SSL_CERT_FILE`/`NODE_EXTRA_CA_CERTS`, via `lib-common.sh`'s
`resolve_ca_bundle`) -- all threaded through the same `sudo -u pi
--preserve-env=...` / `sh -c 'cd "$1"; shift; exec "$@"'` launch idiom
`start-agent.sh`/`login.sh` already use, with the run's own `workdir/` as
`pi`'s cwd (same as `start-agent.sh`).

**`bash` path, UNVERIFIED fallback.** `flake.nix`'s `apps.shell` resolves
`PI_STACK_BASH_BIN` from THIS flake's own nixpkgs
(`pkgs.bashInteractive`), which is a different closure than the
`nixpkgs-unstable` one `gen-profile.sh` closure-expanded into the run's
`profile.json` `filesystem.read` grants when `start-agent.sh` generated
it -- there is no guarantee the resolved bash path is covered by those
grants. `shell.sh` checks the copied profile's `filesystem.read` array
for a prefix match of the resolved bash path and, if none is found,
falls back to `/run/current-system/sw/bin/bash` (covered by every
profile's own implicit system-closure grant, see `gen-profile.sh`),
printing a note to stderr. Not exercised against a real `nono` binary --
marked **UNVERIFIED** in `shell.sh --help` itself.

**`--dry-run`**: prints the resolved binaries/paths and the illustrative
`nono run` command, performing NO sudo/nono calls at all -- this means
the "already running" check, the `profile.json` existence check, and the
bash-path-fallback check (all three require a `sudo -u pi` call) are all
SKIPPED in `--dry-run` mode, same convention `start-agent.sh`/`login.sh`
already follow for their own `--dry-run`.

### `nono-sandbox` extension and skill

`config/agent/extensions/nono-sandbox/index.ts` is a rewritten
`spikes/pi-pack/extensions/nono-sandbox.ts`, vendored directly as source
(NOT pulled through the npm/git extensions pipeline in
`extra-extensions.nix` -- it's hand-authored, copied as-is by the same
`tar_copy_to_pi "$CONFIG_AGENT_DIR" ...` step that copies every other
file under `config/agent/`). Kept unchanged in spirit: the
`NONO_CAP_FILE`-based detection mechanism, the `before_agent_start`
system-prompt note, and the `/nono-status` command. **Replaced**: the
pack's remediation text, which told the agent to run `nono run --allow`
itself or draft a profile under `~/.config/nono/profile-drafts/` -- both
conflict with this stack's model (the untrusted `pi` user has no business
drafting or applying its own sandbox policy; the flake alone owns
`profiles/work.base.json`). The new remediation text instead tells the
agent to report the blocked path/host to the user and ask them to
relaunch with `start-agent.sh --add <path> --name <same-session-name>`,
then `pi --resume` -- and explicitly never to edit profiles,
profile-drafts, or any nono state itself.

`config/agent/skills/nono-sandbox/SKILL.md` is a from-scratch rewrite (not
a line-edit of the pack's skill) matching that same single remediation
path -- it deliberately does not offer the pack's "Option B" (profile
draft) at all. Placed under `config/agent/skills/nono-sandbox/` because
`config/agent/` is tar-copied wholesale onto `$AGENT_DIR` by
`start-agent.sh`/`login.sh`, landing on top of (not instead of) the
`pi-extra-skills` Nix-built bundle already copied into `$AGENT_DIR/
skills/` earlier in the same seeding sequence -- i.e. this directory did
not exist before this phase, but the pipeline that picks it up (plain
recursive copy, last-write-wins) already did.

**Not registered in `config/agent/settings.json`**: no existing extension
in this checkout (including `pi-permission-system`, npm-sourced) is
registered via a `packages` array entry there -- `settings.json` has no
`packages` key at all today, and `extra-extensions.nix`'s own
`packagesListFragment` output is explicitly documented as "still needs to
be merged into settings.json's packages array by hand where relevant"
(i.e. an acknowledged, pre-existing gap, not something this phase
introduced or was asked to close). Since the existing pattern does not
require registration, `nono-sandbox` was not registered either, per this
phase's own instruction to only do so "if the existing pattern requires
it".

### `flake.nix`: new apps

`apps.ps`, `apps.attach`, `apps.stop`, `apps.login`, and (added later,
see "`scripts/shell.sh <name>`" above) `apps.shell` are added following
`apps.start-agent`'s exact wrapper shape (`writeShellApplication`
exporting `PI_STACK_*_BIN` store paths, then `builtins.readFile` of the
corresponding `scripts/*.sh`). `apps.shell` is the one exception to
"minus `pi`": it never runs `pi` at all (just a plain `bash`), so it
exports `PI_STACK_NONO_BIN`/`PI_STACK_JQ_BIN`/
`PI_STACK_APPROVAL_HELPER_BIN` (same as `apps.start-agent`) plus
`PI_STACK_BASH_BIN=${pkgs.bashInteractive}/bin/bash` instead of
`PI_STACK_PI_BIN` -- see `shell.sh`'s own "bash path, UNVERIFIED
fallback" note above for why that's a different nixpkgs closure than the
one `pi`/`nono` are drawn from. `apps.stop`'s now-unused `pkgs.psmisc`
(`fuser`) `runtimeInput` -- stale leftover from the approval-helper
teardown `stop.sh` no longer does, see "`scripts/attach.sh <name>` /
`scripts/stop.sh <name>`" above -- has been removed. None of these touch
`flake.lock`.

