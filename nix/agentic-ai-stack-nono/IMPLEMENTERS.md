# nix/agentic-ai-stack-nono — Implementers

> **Mid-migration note (Phase 4a of `PLAN.md`):** this directory is a
> structural copy of `nix/agentic-ai-stack`, with the container-era code
> (compose files, `containers/`, container-only scripts/flake wiring)
> deleted. The nono work profile (Phase 3), launcher, and approval helper
> (Phase 4a) are now built -- see "Work profile (Phase 3)" and "Launcher
> and approval helper (Phase 4a)" below. Still not built: the
> `attach`/`ps`/`stop`/`login` wrappers, the `nono-sandbox` extension/
> skill, and the `nix/scripts` changes (Phase 4b/4c) -- see `PLAN.md`
> section 4 for the full phase breakdown. Everything ELSE below this note
> still describes the old container architecture almost entirely verbatim
> and is known-stale pending the Phase 5 documentation rewrite; do not
> trust it as a description of this copy's current or future behaviour. In
> particular, known-stale areas:
> - "Threat model", "Components and network access", "Build and run
>   flow", "Credentials", "Acceptance criteria", and "Gotchas" all
>   describe the removed Docker Compose / container boundary.
> - `scripts/shell-agent.sh`, `scripts/stop-agent.sh`, and
>   `scripts/verify-acceptance.sh` were deleted outright (purely
>   container-based; rewritten/replaced in Phase 4b/5 per `PLAN.md`'s
>   launcher/UI table).
> - `flake.nix` no longer builds any container image or exposes
>   `load`/`shell-agent`/`stop-agent`/`verify`/`login` apps; see its
>   top-of-file comment for what remains.
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
   `update`) plus every `--extra-closure-root` (the stack's own tool
   store paths -- `pi`, `node`, `nix/scripts` tools), in order, and
   merges the **order-preserving deduped** (`awk '!seen[$0]++'`, never
   `sort -u` -- see `PLAN.md` section 3's S3.2 harness-bug note) result
   into `filesystem.read` (read-only, never `filesystem.allow`, and
   never nono's `nix_runtime` group, per the "Exec ceiling (Linux)"
   decision row).
3. On macOS, skips the closure merge entirely rather than guessing at a
   workable substitute -- see the UNVERIFIED list below.
4. Adds read-write grants (`filesystem.allow`) for `--workdir`,
   `--state-dir` (the per-run `PI_CODING_AGENT_DIR`, Phase 4), every
   `--add`, and every `--clone`. Judgement call: `--add` paths default
   to read-write (matching `--clone`), since the plan only specified
   this for workdir/state-dir explicitly and `start-agent.sh`'s
   existing `--add` semantics (container era) were already read-write.
5. Validates the result with `jq empty` and writes it atomically (a
   temp file in `--out`'s own directory, then `mv -f` over the final
   path).

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
  120s) expiry is always mapped to `denied` -- fail closed, never a grant.
- UI selection (`--ui auto|osascript|kdialog|tmux|deny-all`, `prompt.go`'s
  `selectPrompter`): `auto` tries `osascript` on Darwin, then `kdialog` on
  Linux if `DISPLAY`/`WAYLAND_DISPLAY` is set, then `tmux`, then falls
  back to `deny-all` (fail closed) if nothing is found. Every concrete
  prompter implementation (`osascriptPrompter`, `kdialogPrompter`,
  `tmuxPrompter`) is **UNVERIFIED** -- no nono binary and no live
  macOS/KDE/tmux session was available in this environment to exercise
  any of them; only `denyAllPrompter` and the dedupe/cache/decision-mapping
  logic in `server.go` are exercised by `main_test.go`'s table tests (via
  a fake `prompter`).
- `--parent-pid PID`: polls (every 1s, via `kill(PID, 0)` -- a pure
  existence/permission check, no signal is actually delivered) and shuts
  down once that PID is gone, so a foreground launcher's helper exits
  when the launcher does, without needing its own signal plumbing beyond
  the standard SIGINT/SIGTERM handling already in `main.go`.

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
state/{auth,sessions}/  <- XDG_STATE_HOME for this run
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

**Detached mode**: `--detached` hands the rest of the lifecycle to a
generated `supervisor.sh`, run via `setsid sudo -u pi -- bash -c 'exec
bash "$1" >"$2" 2>&1 </dev/null' ...` (the log redirect has to happen
INSIDE the sudo'd process, since the invoking user has no write access
into the pi-owned run directory to open that file itself first). The
supervisor starts its own approval helper, generates the profile, runs
`nono run --detached`, then polls plain `nono ps | grep <name>` every 5s
until the session is gone, at which point it kills its approval helper and
exits. **UNVERIFIED judgement call**: this polling loop is modelled
directly on `spikes/all/run.sh`'s S5.1-S5.3 (`nono ps`'s output format was
only ever grepped for a session name substring there, never parsed
structurally), but no nono binary was available in this environment to
confirm that behaviour beyond what those PASS-reported spikes already
exercised. There is deliberately no cross-user (`aidan` watching `pi`'s
sessions) story here yet -- that's `PLAN.md`'s S5.4/"cross-user session
registry" open item, left to the Phase 4b `ps`/`attach`/`stop` wrappers.

**Getting results back out**: this launcher does not automate syncing
`workdir/` changes back to the invoking user's own checkout (unlike the
unrelated `agent-stage`/worktree flow IMPLEMENT subagents use) -- per
`PLAN.md`'s "Sharing files between aidan and pi" decision row, that's a
deliberate UX choice, not a gap: the user inspects/diffs/copies the
per-run `workdir/` copy manually.

