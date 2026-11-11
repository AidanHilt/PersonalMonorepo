# agentic-ai-stack-nono: Implementation Plan

Status: agreed plan, spike-verified on Linux (macOS not yet tested). This
document is the single source of truth handed to later planning dispatches
for nix/agentic-ai-stack-nono. It replaces conversational planning context;
do not re-derive decisions from elsewhere, and do not invent new ones --
anything not settled here is recorded as OPEN in section 6.

This is a plan/spec document, not an implementation-details doc, so it
lives as `PLAN.md` rather than `IMPLEMENTERS.md`, even though root
`AGENTS.md` otherwise routes implementation details to `IMPLEMENTERS.md`
files.

## 1. Goal and non-goals

### Goal

Replace the container-based isolation of `nix/agentic-ai-stack` (Docker
Compose: `pi` + squid proxy + pkg-broker + mounters) with a lighter,
cross-platform sandbox built on **nono** (nolabs-ai/nono, formerly
always-further/nono), which uses Landlock on Linux and Seatbelt on macOS.

The replacement must preserve the same agent workflow end to end: plan ->
dispatch an `IMPLEMENT-n` subagent -> `agent-validate` -> `agent-stage` ->
user reviews and commits with `kommit`.

The work happens in a **copy**, `nix/agentic-ai-stack-nono`, sitting
alongside the original `nix/agentic-ai-stack`. The original stack is left
completely untouched until the copy is confirmed working end to end on
both target platforms; only then does a later, separate effort retire it.

### Non-goals / explicitly out of scope for this effort

- Per-endpoint L7 network rules (deeper than host-level allow/approve).
- Resource limits (cgroups) -- noted as a future improvement only.
- Windows support. nono itself only supports macOS, Linux, and WSL2;
  `windows-setup/` is untouched by this work.
- Any change to the original `nix/agentic-ai-stack`.
- Any change to `nix/mono-flake`'s `cluster-setup`: it still passes
  `--server https://kind-gateway:6443`, and that staleness is accepted as-is
  in the copy.
- A debug profile (deferred -- see section 5, "Improvements").
- Phantom-token credentials (deferred -- see section 5, "Improvements").

## 2. Decisions

The table below is the authoritative decision record. Treat every row as
binding; where a row says "OPEN", treat it as unresolved and carry it into
section 6.

| Topic | Decision |
|---|---|
| Platforms | macOS and Linux (NixOS) are both first-class targets from day one. WSL2 support is a bonus, not a requirement. Windows is out of scope (see section 1). |
| Copy location / name | The new stack lives at `nix/agentic-ai-stack-nono`. Runtime state and per-run copies live under `/var/lib/pi` on the host, not inside the repo. |
| nono source | The stack owns a nixpkgs overlay that bumps nono to >= 0.81.0. Both nixpkgs and nixpkgs-unstable are behind this (the user's host had 0.61.1 before any overlay). Do **not** consume upstream's `v0.81.0` flake output `#prebuilt` directly: its per-platform prebuilt hash was found stale (a hash mismatch was hit for x86_64-linux). Instead, compute our own hashes -- either `fetchurl` of the release tarballs per platform, or build from source -- and re-verify those hashes on every version bump. Spikes used `nix shell github:nolabs-ai/nono#prebuilt` pinned to `main` (not the tagged release), which worked for the spike harness. |
| Isolation user | The agent runs as a dedicated, **untrusted** `pi` user -- i.e. not listed in Nix `trusted-users`. `nix/mono-flake` already defines a `pi` group (gid 10001) in `machines/x86_64-linux/big-boi-desktop/configuration.nix` and `machines/aarch64-linux/devbox/configuration.nix`, with `aidan` a member, but there is no `pi` user yet. On Darwin, `modules/roles/darwin/personal.nix` sets `trusted-users = [ aidan root ]`. We need to add a `pi` user on both NixOS and nix-darwin (home/state under `/var/lib/pi`), plus a sudo/polkit path allowing `aidan` to launch processes as `pi`. The user has accepted this scope expansion into `mono-flake`. |
| Sharing files between `aidan` and `pi` | User-facing behaviour: the agent works inside a `pi`-owned **copy** (a clone/worktree under `/var/lib/pi`), and `agent-stage` brings results back into the user's own checkout; there is no in-place ACL sharing of the user's working files. The agent must never hand-edit system configuration directly -- it edits a copy of `mono-flake`, and the user runs the host's `update` command to apply it. The exact mechanism (bind mount, git worktree, rsync, etc.) is left as an implementation detail; what matters is this UX contract. |
| Filesystem model | The nono profile (a flake-owned JSON file) is the **ceiling**. `pi-permission-system` is the **floor**, constraining what pi's own tool calls may do within that ceiling. Escalating beyond the floor means relaunching with an added grant and `pi --resume` -- this mechanism is uniform across platforms. nono's own capability-expansion path (seccomp-notify, Linux-only) is **disabled and not used**: Seatbelt profiles on macOS cannot be updated live, and nono has no workaround for that, so relying on it would create a platform asymmetry. The floor only constrains the pi tool's own calls; subprocesses it spawns get the full nono ceiling. It's accepted that deterministic tools spawned as subprocesses may end up wider than the pi tool itself. |
| Linux work profile shape | Allow-list only. Spike S3.1 confirmed that nono **refuses to start** when `filesystem.deny` sits inside a broader `filesystem` allow on Linux, because Landlock cannot deny inside an allow. macOS (Seatbelt) does not have this restriction and can mix allow/deny. |
| Network mode | Approval-only. `network.block = false`; `allow_domain` is a flake-owned static whitelist that replaces `containers/proxy/allowed-domains.txt`; `network.approval_backends` configures a webhook backend pointing at a host-side approval helper; `approval_defaults` names that backend as the default. Static allow-listed hosts never prompt. Unlisted hosts prompt. Grants from a prompt are session-scoped only -- there is **no persistence** of dynamic grants (no equivalent of `--persist-domains`). `network.block = true` cannot be combined with approvals, so is not used. Metadata/link-local hosts are always denied outright (spike: a 403, and the helper is never even asked). |
| Approval transport | Loopback TCP webhook: `http://127.0.0.1:<random-port>/<random-token>`, with the token embedded in the URL path. The helper returns 404 and logs nothing for a wrong path. The `unix://` webhook transport in nono 0.81.0 **fails client-side** (`approval webhook failed: http: invalid format`, no connection even attempted), while the identical handler reached over TCP works -- so `unix://` is not used. Spike S1.7: the sandboxed child cannot reach the helper port directly or through the proxy. Spike S1.5: bypassing the proxy fails. Spike S1.8: an unreachable webhook fails closed (denies). |
| Approval helper (host side) | Runs outside the sandbox, started and stopped by the launcher -- it needs an explicit lifecycle to support detached sessions. Speaks nono's unsigned webhook protocol v1: receives a POST with JSON body `{backend, request{capability_type: "network", request_id, session_id, host, port, protocol, resolved_ips, reason, child_pid}}`, and replies `200` with JSON `{decision: granted | denied (+reason) | granted_session}`. UI: a desktop dialog via `osascript` on macOS, `kdialog` on KDE Plasma 6 (mono-flake's `linux-desktop` role uses Plasma), with a `tmux` pane fallback for headless hosts (e.g. `devbox`, aarch64, which may be headless). The helper should dedupe/rate-limit repeated prompts for the same host. |
| `request-domain` / domain-gate | The old runtime-domain-request flow becomes unnecessary: nono's proxy now asks the user directly when the agent connects to an unlisted host. Default plan: **remove** `request-domain` and its permission rules entirely. OPEN: confirm with the user whether any agent-facing "request" CLI should still remain for some other purpose. |
| Exec ceiling (Linux) | The nono read-grant list **is** the exec ceiling on Linux: read implies exec, there is no "read-only but not executable" state (spikes S3.3/S3.5 -- a `jq` outside the grant list could not run; a `jq` inside the grant list could). The profile's store grants are generated from the closure of the host's system profile, **recomputed at each launch** so grants track `update`, plus the stack's own tools (`pi`, `node`, the `nix/scripts` tools). Never include nono's `nix_runtime` group -- spike confirmed it grants the whole Nix store. nono's default profile already denies exec of arbitrary store binaries on NixOS, so this is on top of that baseline, not instead of it. Closure size 2932 paths worked on Linux with order-preserving dedupe (N=1000/2000/2932 all tested OK). macOS Seatbelt rule-count limits for a closure this size are **UNTESTED** (see section 6, OPEN). This mechanism should be treated as defence in depth, not a hard guarantee: interpreters already present in the baseline closure can still run agent-written scripts, and the "load via dynamic linker" trick is moot anyway because read already implies exec. Consequence: the agent cannot read build outputs without also being able to execute them -- an "output directory the agent can read but not exec" design is **not achievable** on Linux with nono's current grant model (tracked as a future improvement, section 5). Use nono's `command_policies` mediation (PATH shims) for `agent-validate` and `nix`; set `deny_direct_exec_bypass` to stop absolute-path bypass of those shims. Note that nono's older `commands.deny` is deprecated and launch-time only. Linux's `exec_paths` setting is ignored on macOS, and in general pinning is weaker on macOS. |
| Nix daemon access | Allow the daemon socket (`/nix/var/nix/daemon-socket/socket` via `filesystem.unix_socket`) plus read access on the store paths actually needed. Spikes S4.1-S4.5 showed store info queries, eval, path-info, realising an existing path, and building a trivial derivation all work from inside the sandbox. Mediate `nix` via `command_policies` `invocation_policy`: allow `build`, `eval`, `develop`, `flake check`, `flake show`; deny `profile`, `copy`, `--option`, `--extra-substituters`, `--accept-flake-config`. The untrusted `pi` user is what prevents trusted-user-style abuse of these allowances. Deny system-rebuild commands entirely: `update`, `nixos-rebuild`, `darwin-rebuild`, `home-manager`, `nix profile`, `nix-env`. Accepted residual risk: fixed-output-derivation fetches run inside the Nix daemon and therefore bypass the sandbox's network-approval proxy -- this is a low-bandwidth egress path, accepted as-is; disk-filling via this path is a nuisance, mitigated by periodic GC rather than prevented outright. |
| pkg-broker / pkg-install | **Removed entirely.** Tools come only from what the machine provides: to add a tool, edit `mono-flake` and the user runs `update`. This requires updating: `agent-plan-create`'s missing-tools message, `config/agent/AGENTS.md`'s planning-step instructions (step 1 should tell the agent to ask the user to add the tool to `mono-flake` instead of running `pkg-install`), permission rules referencing `pkg-install`, and any docs mentioning it. This decision touches the sibling `nix/scripts` flake (home of `pkg-install`, `request-domain`, `agent-plan-create`), but that flake itself is edited in a later phase, not as part of this planning document. |
| Secrets | Keep the existing `--secret NAME=VALUE` interface and `PI_SANDBOX__SECRET__<NAME>` environment-variable convention exactly as today: the user still passes values in from a KeePassXC subshell, and nono itself never touches KeePassXC. Values are injected as environment variables into the agent process, so the agent can see them -- same exposure as today, not a regression. nono's environment filtering must be configured to allow the injected names through. Hand values to the `pi` user over a pipe or via `sudo`'s environment handling -- never via `argv`, since that is visible via `ps`. OAuth: use the native login flow; `auth.json` lives in `/var/lib/pi` state; no phantom tokens in the MVP (see section 5 for the deferred phantom-token work). |
| Config / extension ownership | The flake owns extensions, skills, and agent config. Every start seeds a **fresh per-run** `PI_CODING_AGENT_DIR` under `/var/lib/pi` from the flake; this seeding is idempotent, and this per-run directory is also where `agent-plan-create` writes `IMPLEMENT-n.md`. The existing extensions/skills pipeline (`extra-extensions.nix`, `extra-skills.nix`, `extensions/`, `update-pi-extensions.sh`, `config/agent/`) is kept as-is -- only its destination directory changes. There is **no `--raw` flag**: the user decided it has no use case here. |
| nono profile baseline | The flake-owned work profile (JSON) is based on the nolabs-ai/pi pack's profile. Facts about that pack: `profiles/pi.json` extends `default`, declares `min_nono_version 0.55.0`, and ships an extension `nono-sandbox.ts` plus a skill `nono-sandbox`, along with wiring that appends the pack to pi's `settings.json` `packages` list. See the "keep / drop" breakdown immediately below. |
| nono profile: keep from the pack | Groups `node_runtime`, `user_caches_{macos,linux}`, `linux_sysfs_read`, `git_config`, `unlink_protection` (OPEN: verify worktree cleanup and `agent-stage` still work correctly under `unlink_protection`); `security.signal_mode = isolated`; `capability_elevation = false`; `open_urls` (`auth.openai.com`, `claude.ai`, `github.com`, plus `allow_localhost`); `allow_launch_services`; the rollback exclusions list. |
| nono profile: drop from the pack | `rust_runtime`, `python_runtime`, `user_tools`/`homebrew` groups, `nix_runtime` (per the exec-ceiling decision above), the `$HOME/.nvm` and `$HOME/.agents/skills` reads, the `$NONO_PACKAGES` / `$NONO_CONFIG/profiles` reads, `$NONO_CONFIG/profile-drafts` (the agent must not be able to draft its own policy), the pack's `custom_credentials` block, and the `$HOME/.pi` grant (replaced by the fresh per-run directory described above). |
| `nono-sandbox.ts` and skill | Vendor our own version into the flake, keeping the pack's detection mechanism (`NONO_CAP_FILE`), its system-prompt note, and its `/nono-status` command, but **replace** its remediation text: the pack currently tells the agent to run `nono run --allow` or draft its own profile, which conflicts with our model. Our remediation text instead tells the agent to ask the user to relaunch with an added `--add <path>`. Write our own skill to replace the pack's skill, matching this new remediation flow. Note: nono itself protects `~/.nono` and `$XDG_STATE_HOME/nono`, and rejects grants placed over them -- no extra protection is needed for those paths. |
| Launcher and UI surface changes | See the "old -> new" command table below. |
| Delete as obsolete | See the dedicated list below. |
| Documentation | Update `README.md`, `IMPLEMENTERS.md` (architecture section, and a threat-model section explaining that the container boundary is replaced by nono + the `pi` user), `config/agent/README.md`, and `AGENTS.md`. Add an "Improvements (not built)" section to `IMPLEMENTERS.md" capturing section 5 of this document. |

### Launcher / UI surface: old -> new

| Old | New |
|---|---|
| `start-agent` | Gains `--profile work` (only `work` exists in the MVP), `--audit` (opt-in, maps to `nono --audit-integrity`), `--detached` (maps to `nono run --detached`). Keeps `--add`, `--clone` (now real host paths, no more `/workspace/<basename>` layout), `--secret`, `--name` (now maps to the nono session name), `--resume` (this remains pi's own flag, unrelated to nono). Removes `--host-store`, `--persist-pkgs`, `--no-persist-store`, `--persist-domains`, and all of the kind/kube compose layering. |
| `shell-agent` | Renamed/replaced by `attach`. |
| `stop-agent` | Replaced by a thin wrapper over `nono stop`. |
| (new) | Add a `ps` wrapper (over nono's own session listing). |
| `login` | Runs the native login flow directly; no container indirection. |
| `verify-acceptance.sh` | Rewritten for the new stack. |
| `gen-kubeconfig.sh`, `update-pi-extensions.sh` | Unchanged. |

Same-user nono sessions are confirmed working end to end by spike S5
(detached start, `ps`, stop). Cross-user session visibility -- i.e. `aidan`
being able to see `pi`'s running sessions -- is **OPEN**: the wrappers will
need to either run `nono` as `pi` themselves, or share `XDG_STATE_HOME`
between the two users; neither approach has been chosen yet.

### Delete as obsolete

- `compose*.yaml`
- `containers/` in its entirety (`pi`, `proxy`, `pkg-broker`,
  `nix-store-mounter`, `workspace-mounter`, `kind-gateway`)
- nix2container image builds and the load/start/stop wiring around them
- `CGO_ENABLED`/`GOCACHE`/`GOPATH` container workarounds
- `NO_PROXY` compose-name handling
- The `/workspace` convention generally (this requires updating `AGENTS.md`,
  skills, and docs that reference it)
- Container read-only-root / `cap_drop` acceptance checks
- `pkg-install` and its permission rules
- `request-domain` (default decision above; still OPEN whether something
  replaces it)
- `config/web-search.json`'s `trustEnvProxy` setting -- a spike showed DNS
  resolves inside the sandbox and `node fetch` works both with and without
  `NODE_USE_ENV_PROXY`, but this should be **re-verified running as `pi`**
  before actually deleting the setting, since the spike ran as a trusted
  user, not yet as `pi` (see S2 in section 3, and the Phase 0 remaining
  work in section 4).

### Keep unchanged

- `gen-kubeconfig.sh`
- `update-pi-extensions.sh`
- The `extensions/` and skills pipelines
- `config/agent/` (though its contents are edited per the decisions above)

## 3. Spike results

Spikes ran on Linux x86_64, nono 0.81.0, nix 2.34.9. macOS has not been
exercised at all yet.

| ID | Result | Note |
|---|---|---|
| S1.1-S1.8 | PASS | Validates the whole approval pipeline: profile validates; an approved host returns 200; a denied host returns 000; a session-scoped grant is asked for only once; proxy bypass fails; metadata-host access returns 403 without ever asking the helper; a child process cannot reach the helper directly; an unreachable webhook fails closed. |
| S1.9 | PASS | Request body shape matches the "Approval helper (host side)" decision row above exactly. |
| S2 | PASS, with an open caveat | DNS resolves inside the sandbox even for hosts that are not approved -- this is an open exfiltration channel that Landlock does not close by itself (accepted for now; tracked as an OPEN mitigation in section 6). `node fetch` works correctly with and without `NODE_USE_ENV_PROXY`. Running `pi` itself under nono is **UNTESTED** because `pi` was not on `PATH` during this spike. |
| S3.1 | PASS (confirms a constraint) | On Linux, `filesystem.deny` nested inside a broader `filesystem` allow is a hard refusal to start -- Landlock cannot express deny-within-allow. |
| S3.2 | PASS, harness bug found and fixed | Closure scaling to 2932 paths works. The harness itself had a bug: `sort -u` on the padded closure list destroyed the base-first ordering it depended on; fixed by a manual re-run with ordering preserved (see Phase 0 follow-up: replace with an order-preserving dedupe). |
| S3.3 | PASS (confirms a constraint) | A binary outside the grant list is denied when exec'd. |
| S3.4 | PASS | A binary inside the grant list runs normally. |
| S3.5 | PASS (confirms a constraint) | A read grant alone, with no separate exec grant, is sufficient to allow exec -- i.e. read implies exec on Linux, there is no finer-grained state. |
| S4.1-S4.5 | PASS | Nix daemon access, store queries, eval, path-info, realising an existing path, and building a trivial derivation all work correctly from inside the sandbox. |
| S5.1-S5.3 | PASS | Detached session start, `ps`-equivalent listing, and stop all work for same-user sessions. |

Other things learned along the way:

- nono reports a failed/denied exec as plain exit code **127**, with no
  distinguishing signal that it was a sandbox denial rather than a missing
  binary ("may be unrelated to sandbox restrictions" -- i.e. don't trust a
  127 alone as proof of a sandbox effect). Tests that assert denial should
  run `test -x` first to rule out a simple missing-binary false positive.
- `coreutils`' `true`/`echo`/`sleep` are multicall binaries reached via
  symlinks, so they exec through the unresolved package `bin` path, not a
  resolved individual binary path -- relevant when constructing the grant
  list.

### Still untested (carried into section 6 as open work)

- S4.6: `pi` user interaction with the Nix daemon specifically.
- S5.4: the cross-user session registry question.
- The entire harness on macOS, including Seatbelt-specific behaviour.

## 4. Implementation phases

Each phase ends with a user review before the next phase starts. Note that
implementation subagents cannot run `pkg-install` or `request-domain`
themselves -- any tools or network domains a phase's checks will need must
be prepared by the planning agent *before* dispatch, per the standard
process (see "Process per dispatch" below).  
  
Human here. The previous agent had a poor understanding of the context, so it put some of the work in the wrong order. Treat this section as overriding anything in the following section. Obviously, we need to do the mono-flake host setup before we can run the user spikes, and we also don't need to resolve the user's access to the nix daemon before we have the stack existing. 

**Phase 0 (mostly done): spikes.** Remaining work:
- Running `pi` itself under nono (covering the proxy, DNS, and
  `trustEnvProxy` questions together, as `pi`, not as a trusted user).
- S4.6: `pi` user access to the Nix daemon.
- S5.4: the cross-user session registry.
- A full run of the spike harness on macOS, including checking Seatbelt
  rule-count limits.
- Fixing the ordering bug in `spikes/all/run.sh`: replace `sort -u` on the
  padded closure with an order-preserving dedupe, e.g. `awk '!s[$0]++'`.

**Phase 1: mono-flake host setup.** Add the `pi` user/group on both NixOS
and nix-darwin, provision `/var/lib/pi`, add the launch path via
sudo/polkit, and add the nono overlay with our own computed hashes.

**Phase 2: copy the stack.** Copy the stack into
`nix/agentic-ai-stack-nono` (merging with the existing `spikes/` directory
already there), and delete the container-era code (see the "Delete as
obsolete" list in section 2).

**Phase 3: work profile.** Build the flake-owned nono work profile:
vendored from the pi pack per the keep/drop lists above, closure-generated
exec/read grants recomputed at each launch, the Linux allow-list generator,
native macOS grants, approval-only network configuration, the environment
variable allowlist, mediated `agent-validate` and `nix` via
`command_policies`, and all the relevant denies.

**Phase 4: launcher, approval helper, and clients.** Implement the new
`start-agent` flags, per-run `PI_CODING_AGENT_DIR` seeding, the
copy/`agent-stage` mechanism, the secrets handoff, the approval helper's
full lifecycle, the `attach`/`ps`/`stop` wrappers, the native `login` flow,
the rewritten `nono-sandbox` extension and skill, and the `nix/scripts`
changes (remove `pkg-install`; rewrite or remove `request-domain`; update
`agent-plan-create`'s messages).

**Phase 5: finishing.** Rewrite `verify-acceptance.sh`, update
`README.md`/`IMPLEMENTERS.md`/`AGENTS.md` (including the "Improvements (not
built)" section from section 5 below), and delete `spikes/pi-pack`.

**Process per dispatch, throughout:** install any needed tools with
`pkg-install`, request any needed domains with `request-domain`, run
`agent-plan-create`, dispatch the `IMPLEMENT-n` subagent, run
`agent-stage`, and have the user review and commit with `kommit` before
moving to the next phase.

## 5. Improvements (not built)

These are deliberately **not** built as part of this effort. This list is
destined for an "Improvements (not built)" section of `IMPLEMENTERS.md`,
written during Phase 5, not acted on now.

- **(A) Mediated tools with their own credentials.** `kubectl`, `gh`,
  `agent-validate` with per-plan domains; this could replace both
  `kind-gateway` and the world-readable `644` kubeconfig. nono already
  ships example profiles for `kubernetes` and `github-cli` that could seed
  this.
- **Phantom-token credentials.** An OAuth capture provider for `pi`'s login
  (unverified against `@gotgenes/pi-anthropic-auth`) and credential routes
  for static API keys (this needs per-provider base-URL override support in
  `pi`, which is itself unverified).
- **(D) Rollback snapshots** (`--rollback`), primarily useful for the debug
  profile below.
- **(E) Signed instruction files/skills** via Sigstore trust.
- **(F) A curated `deny_domain` list** -- hosts that can never be
  approved, regardless of user action. Sources for such a list are
  undecided; start hand-curated and auditable rather than importing a
  third-party blocklist wholesale.
- **The whole debug profile.** Restricts only critical files/secrets and
  any ability to update or rebuild the system, rather than the much
  narrower work profile's allow-list model. On macOS: a native `$HOME`
  grant with secret-path denies. On Linux: a generated allow-list of
  `$HOME` minus secrets (deny-within-allow is impossible there, per section
  2). Read-only exposure of the user's home to the `pi` user (via ACLs or
  bind mounts), and system state access via group membership (e.g.
  `systemd-journal`). Edits to system config would still go through a
  mono-flake copy + `agent-stage` + the user running `update`, same as the
  work profile. The debug profile's rebuild-command deny set is the same
  one already listed in section 2 under "Nix daemon access".
- **Output-directory exec gate** (build results readable but not
  executable): not achievable on Linux today, because read implies exec
  there (see section 2, "Exec ceiling (Linux)"). Revisit only if nono
  separates read and exec grants in a future version.
- **(H) Resource limits** (cgroups), Linux-only.
- **DNS exfiltration mitigation** -- closing the channel identified in
  spike S2 (section 3), where DNS resolves inside the sandbox even for
  hosts that haven't been network-approved.

**Not planned at all:** (B) per-endpoint L7 network rules (see section 1,
non-goals).

## 6. Open items / risks

Checklist of everything left unresolved by this plan; each of these must
be settled before -- or explicitly deferred during -- the phase that
depends on it:

- [ ] Running `pi` itself under nono: proxy behaviour, DNS resolution, and
      the `trustEnvProxy` question, all as the untrusted `pi` user rather
      than a trusted user.
- [ ] `pi` user interaction with the Nix daemon, and how `trusted-users`
      interacts with that (S4.6).
- [ ] The cross-user session registry: whether `aidan` can see `pi`'s nono
      sessions, and by what mechanism (S5.4).
- [ ] Launching as `pi` on macOS: nix-darwin user creation and the
      necessary sudo rules.
- [ ] macOS Seatbelt rule-count limits for a closure-sized grant list, and
      general macOS exec behaviour under nono.
- [ ] Whether any `request-domain`-equivalent CLI should remain for the
      agent, now that nono's proxy prompts directly.
- [ ] Whether `unlink_protection` is compatible with worktree cleanup and
      `agent-stage`'s operations.
- [ ] Keeping the nono >= 0.81.0 hash pins correct across future version
      bumps (nono is pre-1.0; flags and schema may still change, and the
      overlay pins a minimum version that will need re-verification each
      time it moves).
- [ ] Approval helper behaviour on headless hosts (e.g. `devbox`), and
      general mitigation of "chatty agent" dialog spam from repeated
      approval prompts.
- [ ] WSL2: it lacks capability expansion, has proxy-only enforcement
      caveats (`wsl2_proxy_policy`), and is a bonus target rather than a
      requirement -- any gaps found there should not block Linux/macOS
      delivery.
- [ ] nono's startup "Share &lt;cwd&gt;?" prompt: always pass `--allow-cwd`
      or set the working directory explicitly in the profile to avoid an
      interactive prompt at every launch.
- [ ] nono reports denied execs as plain exit code 127 with no
      sandbox-specific signal -- anything scripting around exec denials
      needs to account for this ambiguity (see section 3).
