# nix/agentic-ai-stack — Implementers

A Nix-built sandbox for running the Pi coding agent against real
projects, isolated by [nono](https://github.com/nolabs-ai/nono)
(Landlock on Linux, Seatbelt on macOS) and a dedicated, untrusted `pi`
user — not a container boundary. See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md)
for the repo-wide convention, and [README.md](README.md) for the
practical "how do I run it" usage guide — this file is architecture/
design, not a usage guide.

## Goal

- A hard, OS-level isolation boundary around the agent (filesystem and
  network), not just app-level permission prompts.
- Reproducible, declarative deployment via Nix — no manual host setup, no
  config drift.
- Multi-provider frontier model access, no local model serving.
- No secrets ever committed to the repo or baked into the Nix store.

Supported on both macOS and Linux (NixOS).

## Threat model

**In scope:** a prompt-injection or misbehaving-agent scenario where `pi`
is induced to run destructive commands, exfiltrate data, or reach
systems/hosts it shouldn't; accidental credential leakage (into git, into
the Nix store, into logs).

**Explicitly out of scope / accepted risk:** a fully malicious, targeted
attack against the host OS itself (not a hard security boundary against a
determined attacker with local code execution already on the host).
Availability/performance guarantees. A low-bandwidth DNS exfiltration
channel and fixed-output-derivation Nix fetches that bypass the sandbox's
network-approval path entirely (see "Improvements (not built)" below).

**Key architectural principle:** `pi`'s own permission system (ask/allow/
deny prompts, `config/agent/extensions/pi-permission-system/config.json`)
is a *habit-forming guardrail*, not the security boundary. The actual
boundary is two independent layers:

1. **nono** enforces filesystem and network limits at the OS level
   (Landlock on Linux, Seatbelt on macOS) before `pi` even starts, driven
   by a flake-owned JSON profile (`profiles/work.base.json`) that is the
   **ceiling** on what the sandboxed process can ever do. nono's own
   capability-expansion path (seccomp-notify, Linux-only) is disabled and
   never used: Seatbelt profiles can't be updated live, so relying on a
   mechanism that only works on Linux would create a platform asymmetry.
   Escalating beyond a running session's grants means relaunching with an
   added `--add <path>` and `pi --resume` — uniform across platforms.
2. **The untrusted `pi` user** is a dedicated, non-`trusted-users` system
   account (`nix/mono-flake` provisions it, with home/state under
   `/var/lib/pi`) that `pi` always runs as, via a narrow NOPASSWD+SETENV
   sudo rule. This is what prevents trusted-user-style abuse of the Nix
   daemon access the sandbox grants (see "Nix daemon access" below), and
   is the reason `pi-permission-system`'s own prompts can stay a
   guardrail rather than a boundary.

`pi`'s own tool-call permission floor (`pi-permission-system`) constrains
only `pi`'s own calls within the nono ceiling; subprocesses it spawns get
the full nono ceiling, so a deterministic tool spawned as a subprocess may
end up wider than the `pi` tool itself.

## Work profile and `gen-profile.sh` composition

- `profiles/work.base.json` — the flake-owned, static base profile.
  Extends nono's built-in `default`. Groups kept: `node_runtime`,
  `user_caches_{macos,linux}`, `linux_sysfs_read`, `git_config`,
  `unlink_protection`; `security.signal_mode = isolated`;
  `capability_elevation = false`; `open_urls` (`auth.openai.com`,
  `claude.ai`, `github.com`, plus `allow_localhost`); `allow_launch_services`.
  Linux is allow-list only: `filesystem.deny` is never used, since
  Landlock refuses to start with deny-inside-allow — macOS (Seatbelt)
  doesn't have this restriction but the profile stays allow-list-shaped
  on both for consistency. The Nix daemon socket
  (`/nix/var/nix/daemon-socket/socket`) is granted via
  `filesystem.unix_socket`. `network.allow_domain` is a static host
  whitelist (Anthropic/Claude, GitHub, exa.ai, `auth.openai.com`);
  `network.approval_backends`/`approval_defaults` configure a `webhook`
  backend whose URL is the literal placeholder token
  `__APPROVAL_WEBHOOK_URL__`, filled in at launch time by
  `scripts/gen-profile.sh` once the approval helper is running.
- `profiles/login.base.json` — a minimal sibling for `scripts/login.sh`'s
  OAuth flow: same groups/`open_urls`/webhook backend, but no
  `unix_socket` grant (no Nix daemon access for a login session) and no
  `command_policies` block at all.
- `scripts/gen-profile.sh` — composes a launch-ready profile from a base
  profile plus per-launch filesystem grants. Never calls `nono` itself —
  it only produces the JSON `nono run --profile <out>` is later given.
  `--self-test` exercises its dedupe/substitution logic against fixture
  data with no dependency on `nix`/`nono` (`GEN_PROFILE_CLOSURE_CMD`
  overrides the closure lookup).

**Composition steps:**

1. Substitutes `__APPROVAL_WEBHOOK_URL__` everywhere it appears in the
   base profile with the actual per-launch webhook URL.
2. On Linux, computes the Nix closure (`nix-store -qR`) of
   `/run/current-system/sw` (the host's system profile, so grants track
   `update`; always implicit) plus, for every `--read` path that is
   itself under `/nix/store`, that path's own closure — falling back to
   granting just that path if the closure lookup fails. `--read` paths
   OUTSIDE `/nix/store` are never closure-expanded, just granted as-is.
   Everything is merged, in order, with an **order-preserving dedupe**
   (`awk '!seen[$0]++'`, never `sort -u`, which would destroy closure
   ordering) into `filesystem.read` (read-only, never `filesystem.allow`,
   and never nono's `nix_runtime` group, which spikes confirmed grants
   the whole Nix store).
3. On macOS, skips the closure merge entirely and grants every `--read`
   path exactly as given, rather than guessing at a workable Seatbelt
   closure substitute.
4. Adds read-write grants (`filesystem.allow`) for `--workdir`,
   `--state-dir` (the per-run `PI_CODING_AGENT_DIR`), every `--add`, and
   every `--clone`.
5. Every `--read` path that is NOT under `/nix/store` is also appended to
   the `fs_read` array of every `command_policies.commands[].from.
   session.sandbox` that already has one (store paths need not be — those
   sandboxes already grant `/nix/store` itself, e.g. `work.base.json`'s
   `nix` command policy). Never creates an `fs_read` array, or a
   `command_policies` block, where one doesn't already exist.
6. Validates the result with `jq empty` and writes it atomically (a temp
   file in `--out`'s own directory, then `mv -f` over the final path).

**Exec ceiling (Linux)**: the nono read-grant list *is* the exec ceiling
on Linux — read implies exec, there is no "read-only but not executable"
state. The profile's store grants are the closure of the host's system
profile, recomputed at each launch so grants track `update`, plus this
stack's own tools (`pi`, `agent-validate`/`agent-plan-create` if present).
This is defence in depth, not a hard guarantee: interpreters already
present in the baseline closure can still run agent-written scripts.

**Nix daemon access**: the daemon socket plus read access on the store
paths actually needed. `nix` is mediated via `command_policies`'
`invocation_policy`: allows `build`, `eval`, `develop`, `flake check`,
`flake show`; denies `profile`, `copy`, `--option`,
`--extra-substituters`, `--accept-flake-config`, and denies system-
rebuild commands entirely (`update`, `nixos-rebuild`, `darwin-rebuild`,
`home-manager`, `nix profile`, `nix-env`). The untrusted `pi` user is
what prevents trusted-user-style abuse of these allowances.

**Environment variable filtering**: `work.base.json`'s top-level
`environment` block (and the `nix` command policy's nested
`sandbox.environment`) allow-lists `PATH`, `HOME`, `USER`, `TERM`,
`LANG`, `LC_*`, `TZ`, `PI_*`, `PI_SANDBOX__SECRET__*` — letting the
`--secret`/`PI_SANDBOX__SECRET__<NAME>` convention (see "Credentials"
below) through. `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_*`/
`GIT_CONFIG_VALUE_*` and `SSL_CERT_FILE`/`NIX_SSL_CERT_FILE`/
`NODE_EXTRA_CA_CERTS` are also allow-listed, for `safe.directory`
registration and CA trust respectively (see "Credentials" below).

## Launcher and approval helper

### Approval helper (`approval-helper/`)

A stdlib-only Go module (`vendorHash = null` — nothing to vendor). Runs
OUTSIDE the sandbox, on loopback only, and implements nono's unsigned
webhook v1 approval protocol:

- Listens on `127.0.0.1:<os-assigned port>`; the bearer token lives in
  the URL path (`/<token>`). A request to any other path gets a bare 404
  with **no log line at all** — logging even an access line would risk
  leaking the token into a log file. Startup prints one JSON line
  `{port, token, url}` to stdout once listening (and optionally to
  `--info-file`, mode `0600`) — that's how `start-agent.sh` reads the
  webhook URL back.
- `server.go`'s `decide()` applies, in order: a per-HOST
  `granted_session` cache (kept for the helper's whole process
  lifetime), a per-`host:port` deny cache (`--deny-cache-secs`, default
  30s), then in-flight prompt dedupe (concurrent requests for the same
  `host:port` share one prompt), before falling back to `prompt.go`'s
  `prompter` interface. A UI error or `--timeout` (default 55s) expiry is
  always mapped to `denied` — fail closed, never a grant — and logged
  with the reason.
- UI selection (`--ui auto|osascript|kdialog|tmux|deny-all`): `auto`
  tries `osascript` on Darwin; on Linux, tries `kdialog` only if
  `DISPLAY`/`WAYLAND_DISPLAY` is set AND neither `SSH_CONNECTION` nor
  `SSH_TTY` is set; then tries `tmux` only if `$TMUX` is already
  non-empty (both as the Linux fallback and as Darwin's own fallback when
  `osascript` isn't found). If nothing matches, `selectPrompter` returns
  an error with an actionable message rather than silently denying every
  approval — a misconfigured host (most commonly SSH with no tmux) fails
  loudly at helper startup instead of quietly denying every approval it's
  asked about later.
- `--parent-pid PID`: polls (every 1s, via `kill(PID, 0)`) and shuts down
  once that PID is gone. In `--detached` mode this points at the
  invoking-user-owned `wrapper.sh` process (see "Detached mode" below),
  not any `pi`-owned process — a liveness check only works when both
  processes share the same user.
- **Timeout alignment**: the helper's own prompt timeout (55s) is kept
  deliberately below the `network.approval_backends.dialog.timeout_secs`
  the nono profiles set for the webhook backend (60s), so the helper's
  own timeout always fires first and gets logged with a reason, rather
  than nono's own timeout winning the race silently.

### Launcher (`scripts/start-agent.sh`)

Flags: `--profile work` (only value today, leaving room for a future
debug profile), `--audit` (-> `nono --audit-integrity`), `--detached`
(-> `nono run --detached`), `--add`/`--clone` (real host paths, live-
shared — see "Live file sharing" below), `--secret`/
`PI_SANDBOX__SECRET__<NAME>`, `--name` (nono's own session name),
`--resume` (pi's own flag, forwarded after `--`), `--dry-run` (prints the
resolved command, secrets redacted by name only, performs no directory
creation/sudo/nono calls).

**Read-as-invoking-user / write-as-`pi` split**: every write under
`/var/lib/pi` (the launcher's own per-run state tree, as opposed to the
live-shared workdir/`--add`/`--clone` paths) goes through a narrow
`sudo -u pi <cmd>` invocation (`mkdir`, `tee`, `tar -xf`, `cp` from a
world-readable Nix store path); every read of the invoking user's own
files (`config/agent/` in particular) runs as the invoking user. The
`tar_copy_to_pi`/`write_as_pi` helpers stream bytes through a pipe rather
than granting either user direct filesystem access into the other's
trust domain — this is what lets the launcher work without the invoking
user needing traversal rights into pi-owned directories.

**Per-run state layout** (`/var/lib/pi/runs/<name>/`, `<name>` defaulting
to `"pi"`):
```
pi/agent/            <- PI_CODING_AGENT_DIR
  extensions/, skills/ <- pi-extra-extensions/pi-extra-skills build output
  settings.json, AGENTS.md, agents/*, extensions/pi-permission-system/
                      <- config/agent/ layered on top (extensions/skills
                         first, config/ on top, never destructively)
pi/web-search.json    <- config/web-search.json
state/sessions/       <- the gen-profile.sh --state-dir grant (scratch
                         space for this run; NOT where auth.json lives)
shared-paths          <- one realpath per line (workdir first, then
                         every --add/--clone extra) -- see "Live file
                         sharing" below
workdir-path          <- the single realpath of this run's live-shared
                         workdir
profile.json          <- the gen-profile.sh output passed to
                         `nono run --profile`
supervisor.sh, supervisor.log, approval-helper-info.json
                      <- --detached mode only, see "Detached mode" below
```

**Idempotent seeding / `--resume`**: every launch re-syncs
`pi/agent/{extensions,skills}/` and layers `config/agent/`+
`config/web-search.json` on top again, but never deletes the run
directory first — it only adds/overwrites those specific paths. This
means re-running with the SAME `--name` re-shares the same workdir/
`--add`/`--clone` paths (merged with whatever was already recorded) and
reuses the same `PI_CODING_AGENT_DIR` tree, so anything `pi` itself
writes there (its own session history) survives across launches — that's
what makes `--resume` meaningful here.

**Live file sharing** (see "Live-share ACLs" below for the mechanism):
the workdir and every `--add`/`--clone` extra are shared LIVE and
read-write at their real host path via `scripts/lib-common.sh`'s
`share_grant`. `--clone` is treated as `--add` once the host-side
clone/fetch is done — both get the identical read-write grant.

**Secrets handoff**: `--secret NAME=VALUE` / `PI_SANDBOX__SECRET__<NAME>`
are `export`ed as real environment variables on the launcher process
itself (never appended to any command's argv), then threaded through
`sudo --preserve-env=<comma-separated names>` — the `sudo` invocation's
own argv only ever lists variable NAMES, never values, so a `ps` of the
launcher process cannot recover a secret value. This relies on the
NOPASSWD+SETENV sudo rule in `nix/mono-flake`'s `_pi-user-linux.nix`/
`_pi-user-darwin.nix`.

**Detached mode** splits the lifecycle across three pieces, so the
approval helper can run as the invoking user (required for its tmux
fallback to reach a real terminal) while the agent session itself runs
as `pi`:

1. **`supervisor.sh`** (pi-owned, runs as `pi`): takes the already-running
   helper's webhook URL as its one argument, generates the profile, runs
   `nono run --detached`, then polls `nono ps` every 5s until the session
   is gone.
2. **`wrapper.sh`** (owned and run by the invoking user, in a scratch
   directory under `$XDG_RUNTIME_DIR`/`$TMPDIR`/`/tmp`): starts the
   approval helper, waits for its info file, then runs `sudo -u pi --
   supervisor.sh <webhook-url>` in the foreground; once that returns,
   kills the helper and cleans up its scratch directory (which holds the
   bearer token).
3. **The launcher itself**, still attached to the terminal, starts the
   wrapper (`setsid`, backgrounded, disowned) and blocks briefly to
   confirm the helper actually came up before returning control to the
   user, printing both the wrapper's and the supervisor's log locations.

**CA trust-store handling**: the sandbox has no default CA trust store
reachable inside it. Both `start-agent.sh` and `login.sh` call
`lib-common.sh`'s `resolve_ca_bundle` to find a host CA bundle
(`$PI_STACK_CA_BUNDLE` override, then `$NIX_SSL_CERT_FILE`/
`$SSL_CERT_FILE`, then the usual system paths), grant its PARENT
DIRECTORY (not the bundle file itself) via `--read`, and export
`SSL_CERT_FILE`/`NIX_SSL_CERT_FILE`/`NODE_EXTRA_CA_CERTS` set to the
resolved bundle path, threaded through `sudo -u pi --preserve-env`.

## Session wrappers

### `scripts/lib-common.sh`

A small, `source`d-only helper shared by every script
(`start-agent.sh`, `ps.sh`, `attach.sh`, `stop.sh`, `login.sh`,
`shell.sh`). Provides `resolve_or_die`/`resolve_stack_bin`,
`RUNS_ROOT=/var/lib/pi/runs`, `validate_run_name` (anchors a run name to
`^[A-Za-z0-9._-]+$`, rejecting path traversal), `require_run_dir`,
`nono_state_dir_for` (the single canonical path for a run's nono
`XDG_STATE_HOME` — `/var/lib/pi/<name>-nono-xdg-state` on Linux,
`/Users/Shared/pi-nono-state/<name>-nono-xdg-state` on macOS by default,
a sibling of `$RUNS_ROOT` chosen so it never overlaps nono's own
protected state root), `resolve_ca_bundle`, `nono_session_running`, and
the live-file-sharing primitives described below.

### `scripts/ps.sh` (`nix run .#ps`)

There is no single, cross-run `nono ps` — every run has its own nono
`XDG_STATE_HOME`, and nono has no cross-run session registry. `ps.sh`
loops over every run directory, computes its nono state dir, skips it if
that doesn't exist, and otherwise runs `nono ps` once per run as `pi`,
printing a combined, `== run: <name> ==`-labelled table. A non-zero exit
from `nono ps` for one run is surfaced as a labelled failure line, not
silently skipped, and the listing continues for the rest.

### `scripts/attach.sh <name>` / `scripts/stop.sh <name>`

Both validate `<name>` via `require_run_dir`, then run `nono attach
<name>` / `nono stop <name>` as `pi`, against that run's own nono
`XDG_STATE_HOME`.

`stop.sh`, on a successful `nono stop`, first releases every live-shared
path recorded for this run (`share_release`, interactive sudo), then
deletes everything under the run's nono state directory except
`nono/audit` (worth keeping; everything else is disposable scratch
state). This is also the documented recovery path for a crashed/
interrupted `start-agent.sh` launch whose own teardown never ran.
`stop.sh` refuses outright, before stopping or deleting anything, if a
`"<name>-shell"` session is still running — exit the shell first (see
`shell.sh` below). The approval helper's lifecycle is NOT `stop.sh`'s
job: it's owned by the launcher process (foreground) or the invoking-
user wrapper (detached), both of which stop it once `nono stop` makes
the session they're watching exit.

### `scripts/login.sh` (`nix run .#login`)

Runs `pi`'s native OAuth login flow inside a minimal nono session, as
`pi`, using `profiles/login.base.json`. State lives directly under
`/var/lib/pi/login/` (`agent/` — wiped and recreated fresh every run,
since login is a one-off flow, not a `--resume`'able session;
`nono-xdg-state/`; `profile.json`). No non-interactive `pi` login
subcommand is documented anywhere in this checkout, so the script starts
`pi` inside the sandbox interactively and expects the user to trigger
login themselves (e.g. a `/login` command) and then exit the session
normally; `login.sh` then copies `agent/auth.json` to the shared
`/var/lib/pi/auth/auth.json` (`install -m 0600`, as `pi`), or logs a
warning if nothing is there.

### `scripts/shell.sh <name>` (`nix run .#shell -- <name>`)

Opens a separate, interactive `bash -i` inside its OWN nono session
(`"<name>-shell"`), reusing the target run's nono `XDG_STATE_HOME` (so
it's labelled under that run in `nono ps`/`ps.sh`) and a per-invocation
COPY of that run's own `profile.json` — not a call into `gen-profile.sh`
— with only its webhook approval URL rewritten. This exists because
`nono attach` attaches to `pi`'s own TUI PTY and fails outright for a
foreground run ("Session <name> already has an active attached client").

Starts its own approval helper (as the invoking user), so it works
whether or not the run's own `pi` session is still alive. Refuses to
start if a `"<name>-shell"` session is already running — one shell per
run. Requires the target run to already have a `profile.json` (i.e. to
have been started at least once via `start-agent.sh`). Re-shares the
run's recorded workdir/`--add`/`--clone` paths for the shell's lifetime
and releases them on exit, but never while the run's own main session is
still live and also shares that path.

## Live-share ACLs

`scripts/lib-common.sh`'s `share_grant`/`share_release` share the
invoking user's workdir and every `--add`/`--clone` extra LIVE,
read-write, at their real host path — not a `pi`-owned copy and not an
`agent-stage`-style sync-back:

- **Grant** (`share_grant`): POSIX ACLs on Linux (`setfacl -R -m
  u:pi:rwX`, plus default entries on directories for both `pi` and the
  invoking user); NFSv4-style ACLs on macOS (`chmod +a`, split into
  separate file/directory entries since macOS rejects inheritance flags
  on regular files, and the invoking user's own file entries omit
  `execute` so `access(2)`-based tools like pre-commit's
  `check-executables-have-shebangs` don't see every shared file as
  executable). Plus (`share_ensure_parent_traverse`) a bare traverse
  (`x`/`search`) grant on every parent directory up to (excluding) `/` —
  but only where `pi` can't already traverse it AND the invoking user
  owns it; a parent neither condition covers fails the whole grant
  loudly instead of ever escalating with `sudo`.
- **Checks** (`share_path_check`): every path is checked — refuses `/`,
  the invoking user's own `$HOME`, or a path not owned by the invoking
  user — for ALL paths up front, before granting any of them, so a late
  refusal never leaves a partial set of grants behind. A failure partway
  through a batch releases everything already granted in that same call.
- **Release** (`share_release`): normalizes ownership of anything `pi`
  left behind back to the invoking user (interactive `sudo` by default;
  `--noninteractive` for the detached-mode wrapper, which has no
  controlling terminal), then removes the ACL entries `share_grant`
  added — on the path itself, and on each parent UNLESS some other still-
  live run's own share still needs that parent, or the parent isn't owned
  by the invoking user (nothing of ours to remove there). "Still live" is
  checked via `nono_session_running` against either run's main or shell
  session. Three call sites: `start-agent.sh`'s own foreground `EXIT`
  trap, the detached-mode wrapper once its supervisor returns
  (`--noninteractive`), and `stop.sh` (interactive, the recovery path for
  a crashed launch).
- **`git safe.directory`**: `pi` and the invoking user are different uids
  sharing the same live path, which trips git's "detected dubious
  ownership" guard. `git_safe_dir_env` exports `GIT_CONFIG_COUNT`/
  `GIT_CONFIG_KEY_*`/`GIT_CONFIG_VALUE_*` (one pair per shared path),
  threaded through the same `sudo --preserve-env` list as everything
  else — never a written `.gitconfig`.

## Credentials

No secrets live in the repo or the Nix store. Two mechanisms, usable
together:

- Static API keys / third-party secrets: `start-agent.sh --secret
  NAME=VALUE` (repeatable) or `PI_SANDBOX__SECRET__<NAME>` host env vars
  — see "Launcher" above for how they reach the sandboxed process without
  ever appearing in argv.
- OAuth: `nix run .#login` writes `auth.json` to a shared, cross-run
  store at `/var/lib/pi/auth/auth.json`, which is never itself granted to
  any nono session. Every `start-agent.sh` launch seeds a per-run COPY
  from it into `PI_CODING_AGENT_DIR/auth.json`, as `pi`, mode `0600`,
  after that run's `config/agent/` layering — skipped if the run-local
  file already exists and isn't older than the shared source, so a run
  that has refreshed its own auth (e.g. via a login performed inside that
  session) is never clobbered by an older shared copy on restart.

## Configuration bundling

`config/` is a 1:1 mirror of `~/.pi/` — `config/agent/` mirrors
`~/.pi/agent/` (`settings.json`, `AGENTS.md`, `agents/*`, each
extension's `config.json`). See [config/agent/README.md](config/agent/README.md)
for the file-by-file breakdown. Every launch of `start-agent.sh`/
`login.sh` layers this directory (via a tar-pipe copy, so it never needs
to be `pi`-readable in place) onto that run's `PI_CODING_AGENT_DIR`, on
top of the `pi-extra-extensions`/`pi-extra-skills` build outputs already
copied there. **Config only, never a secret** — edit the SOURCE under
`config/agent/`, never a deployed copy.

`config/agent/extensions/nono-sandbox/index.ts` and
`config/agent/skills/nono-sandbox/SKILL.md` detect a nono sandbox denial
(`NONO_CAP_FILE`, tool-result error patterns) and tell the agent to ask
the user to relaunch with `start-agent.sh --add <path> --name
<same-session-name>` then `pi --resume` — never to run `nono run --allow`
or draft its own profile, since the untrusted `pi` user has no business
applying its own sandbox policy.

## Permission model (Pi-level)

`@gotgenes/pi-permission-system`
(`config/agent/extensions/pi-permission-system/config.json`) provides
pattern-based allow/ask/deny rules for `edit`/`write`/`read`/`bash`. This
is a guardrail on top of the real boundary described above, not a
substitute for it — see "Threat model" above.

## Making changes

- **Changing the work/login profile**: edit `profiles/work.base.json`/
  `profiles/login.base.json` directly (static content) or
  `scripts/gen-profile.sh` (per-launch composition logic).
- **Adding a permanent egress domain**: add it to `work.base.json`'s
  `network.allow_domain`. For a one-off exception, let the approval
  helper prompt instead (see README.md's "Approvals" section) — grants
  from a prompt are session-scoped only.
- **Changing agent config**: edit the source under `config/agent/` (see
  [config/agent/README.md](config/agent/README.md)) — never a deployed
  copy. Never add a secret here.
- **Updating pinned extensions**: `nix run .#update-pi-extensions`
  (`scripts/update-pi-extensions.sh`) regenerates
  `extensions/package-lock.json`/`git-extensions.nix`; see
  [extensions/README.md](extensions/README.md).
- **Updating pinned skills**: edit `extra-skills.nix` (sources/`enable`
  list) — see README.md's "Agent skills" section.
- **The `IMPLEMENT` agent definition and worktrees**: `config/agent/
  agents/IMPLEMENT.md` is the base template for the implementation
  subagent. `config/agent/subagents-worktrees.json` opts `IMPLEMENT` and
  its per-dispatch `IMPLEMENT-1`..`IMPLEMENT-4` slot copies into isolated
  git worktrees via `@gotgenes/pi-subagents-worktrees`. See
  `config/agent/AGENTS.md`'s "Worktrees" section for how dispatch/
  validate/stage fits together.

## Improvements (not built)

- **Mediated tools with their own credentials**: `kubectl`, `gh`,
  `agent-validate` with per-plan domains via nono's `command_policies`,
  using per-provider credential routing instead of broad ambient access.
- **Phantom-token credentials**: an OAuth capture provider for `pi`'s
  login and credential routes for static API keys, instead of handing
  `pi` the real token/key value directly.
- **Rollback snapshots** (`--rollback`), primarily useful for a future
  debug profile.
- **Signed instruction files/skills** via Sigstore trust.
- **A curated `deny_domain` list** — hosts that can never be approved,
  regardless of user action. Sources for such a list are undecided; start
  hand-curated and auditable rather than importing a third-party
  blocklist wholesale.
- **A debug profile**: restricts only critical files/secrets and any
  ability to update or rebuild the system, rather than the much narrower
  work profile's allow-list model — read-only exposure of the user's home
  (via ACLs) and system state access via group membership (e.g.
  `systemd-journal`). Edits to system config would still go through a
  mono-flake copy + `agent-stage` + the user running `update`, same as
  the work profile.
- **Output-directory exec gate** (build results readable but not
  executable): not achievable on Linux today, because read implies exec
  there (see "Exec ceiling (Linux)" above). Revisit only if nono
  separates read and exec grants in a future version.
- **Resource limits** (cgroups), Linux-only.
- **DNS exfiltration mitigation**: DNS resolves inside the sandbox even
  for hosts that haven't been network-approved — an open exfiltration
  channel that Landlock does not close by itself.
- **`unlink_protection` vs. worktree cleanup/`agent-stage`**: this group
  is kept in the work profile, but its interaction with git worktree
  teardown and `agent-stage`'s own operations has not been verified end
  to end — confirm before relying on it under load.

**Not planned at all**: per-endpoint L7 network rules (deeper than
host-level allow/approve).
