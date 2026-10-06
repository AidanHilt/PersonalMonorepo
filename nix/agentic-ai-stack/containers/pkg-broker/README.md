# `pkg-broker`

An always-on sidecar service that lets the `pi` container (and the human
operator, via `pkg-install`, see `nix/scripts/scripts/pkg-install/`)
install arbitrary nixpkgs software on demand, without growing the baked
`pi` image and without giving the sandboxed `pi` container itself a nix
toolchain, a nix-daemon socket, or broad network access. See
`PROJECT-SPEC.md` for the full design rationale; this file documents the
service itself.

Deliberately minimal, in the same spirit as `containers/proxy` (also a
trust-boundary-adjacent component): a single Go binary (stdlib only, no
third-party deps), two narrow HTTP endpoints, no persistent install-state
beyond what the nix store naturally provides.

## What it does

`pkg-broker` is dual-homed on both the `internal` and `external` compose
networks (same shape as `proxy`), but unlike `proxy` it does **not** sit
in `pi`'s egress path at all. It exposes two endpoints, both reachable
only from the `internal` network (never published to the host, never on
`external`):

```
POST /resolve
{"attr": "ripgrep"}
```

1. Validates `attr` is a plain, dot-separated nixpkgs attribute path
   (letters/digits/`_`/`-`/`'`, dot-separated segments) — no flake refs,
   no arbitrary nix expressions. See `main.go`'s `attrPattern`.
2. Resolves it via `nix-build -A <attr> <pinned-nixpkgs-path>`, where
   `<pinned-nixpkgs-path>` is this flake's own `nixpkgs` input (baked
   into the image at `/etc/pkg-broker/nixpkgs`, see `image.nix`) — the
   exact same nixpkgs revision everything else in this flake builds
   against. Binary-cache-first / build-from-source-fallback is just
   `nix-build`'s normal substituter behavior (see `nix.conf`); nothing
   special-cased here. Building from source is what gives this
   reliability beyond a cache miss, using pkg-broker's own unproxied
   `external` network leg (bypasses the `proxy` Squid allowlist entirely
   by design — same precedent as `proxy`/`login`'s own external leg).
3. Symlinks every entry under the resolved store path(s)' `bin/`
   directory into the shared `pkg-bin` volume.

```
POST /lookup-binary
{"binary": "protoc"}
```

1. Validates `binary` is a plain executable name (letters/digits/`_`/`.`/
   `+`/`-`, no `/`, no leading `-`, no whitespace or shell metacharacters)
   — see `main.go`'s `binaryPattern`/`validateBinaryName`.
2. Answers "which nixpkgs attribute(s) provide a binary named `<binary>`"
   by invoking a prebuilt **nix-index** database **lazily, at request
   time**, via:

   ```
   nix run <PKG_BROKER_NIX_INDEX_REF>#nix-index-with-db -- \
     --at-root --whole-name --minimal -- /bin/<binary>
   ```

   (nix-locate restricts to top-level nixpkgs attrs by default now -- no
   `--top-level` flag is passed; `--all` would disable that default.)

   `PKG_BROKER_NIX_INDEX_REF` is a pinned
   `github:Mic92/nix-index-database/<rev>` flake ref baked into the image
   (see "Pinning nix-index-database" below) — never a locally-built index,
   and never baked into the image's own closure. This is the first thing
   that differs from `/resolve`: `nix.conf` needs the `flakes` experimental
   feature enabled (alongside `nix-command`) for `nix run <flakeref>` to
   work at all — see `nix.conf`'s comments; `/resolve`'s plain
   `nix-build -A` never needed it.
3. **The very first `/lookup-binary` call ever made against a given
   `PKG_BROKER_NIX_INDEX_REF` downloads the whole nix-index database** —
   this can take a while (minutes, depending on network conditions), which
   is why the server gives this call a generous (10 minute) timeout.
   Subsequent calls reuse `nix`'s own eval/store cache and are fast.
   `pkg-broker`'s server also serializes all `/lookup-binary` calls with a
   mutex so concurrent first-time requests don't race to download the
   database independently (see `main.go`'s `dbMu`).
4. Parses the resulting candidate attribute names (nix-index's `--minimal`
   output), strips any nix output suffix (e.g. `protobuf.out` →
   `protobuf`), re-validates each one against the same `attrPattern` used
   by `/resolve` (defense in depth — this is third-party tool output, not
   fully trusted), deduplicates, and sorts.
5. Returns the candidate list and nothing else. **`/lookup-binary` never
   builds or publishes anything** — unlike `/resolve`, it has no
   build-from-source cost and makes no change to the shared `pkg-bin`/
   `nix-store` volumes. Zero candidates is reported as a clear error
   (HTTP 404), one or more candidates as a plain JSON list (HTTP 200). A
   caller (`pkg-install --by-binary`, or a human) picks a candidate and
   makes a **separate** `/resolve` call to actually install it — that
   second call goes through `/resolve`'s own independent validation and
   `nix-build`, so a candidate surfaced here is never trusted or installed
   without being revalidated end to end.

### Pinning nix-index-database

`nix-index-database` (`github:Mic92/nix-index-database`) is a flake
**input** of `nix/agentic-ai-stack/flake.nix` — pinned the same way every
other input is, via `flake.lock` — but it is deliberately **not** wired
into `pkg-broker`'s image closure/`rootEnv`/`copyToRoot` the way e.g.
`nixpkgs` is. Only a derived string, `github:Mic92/nix-index-database/<locked
rev>` (computed from `inputs.nix-index-database.rev` in `flake.nix`), is
passed into `image.nix` and baked in as the `PKG_BROKER_NIX_INDEX_REF` env
var. This keeps the (sizeable) index database itself out of every image
build — it's fetched by `nix run` lazily, directly from `pkg-broker`'s own
unproxied `external` network leg, only the first time someone actually
uses `/lookup-binary` — while still letting `flake.lock` own the pin (so
`nix flake lock` / `nix flake update nix-index-database` control exactly
which database revision gets used, same as any other input). The pin is
included in `image.nix`'s `contentId`, so `nix run .#load` reloads the
image whenever it changes, even though the input itself never touches the
image's actual contents. `inputs.nixpkgs.follows` is deliberately **not**
set on this input — the lazy `nix run` invocation resolves against
`nix-index-database`'s own flake lock, not this repo's pinned nixpkgs, so
the index database and the nixpkgs revision it was actually built from
stay matched to each other.

### Trust note

`/lookup-binary`'s output is **candidate attribute names derived from
third-party tool output** (a community-maintained nix-index database), not
from this repo's own pinned nixpkgs evaluation the way `/resolve`'s
validation is. Treat it as advisory, not authoritative: candidates are
regex-validated the same as any other attribute name before being
returned, but their *existence* in current nixpkgs is not verified by
`/lookup-binary` itself — that verification happens for free the moment a
caller actually sends one to `/resolve`, which is exactly why
`/lookup-binary` never auto-resolves or auto-installs a candidate itself.

`pi` never talks to `pkg-broker` directly — the `pkg-install` CLI
(`nix/scripts/scripts/pkg-install/`) is the only client, and it's not
allow-listed in `pi`'s own permission policy by default (see
`.AGENT-PLAN.md` decision 6 / `PROJECT-SPEC.md`) — a human operator runs
it manually via `nix run .#shell-agent` until that's revisited.

## Volumes

Two named Docker volumes, both read-write into `pkg-broker`, both
read-only into `pi` (see `compose.yaml`):

- `pkg-bin`, mounted at `/srv/pkg-broker/bin` in `pkg-broker` and at
  `/usr/local/bin` in `pi`. `/usr/local/bin` is on `pi`'s default
  container `$PATH` (the OCI/Docker default `PATH`) but otherwise empty
  in the baked `pi` image (everything else lives under `/bin`, provided
  by `pi-image`'s own `buildEnv` closure) — so mounting this volume there
  adds resolved binaries to `pi`'s `$PATH` without shadowing anything
  that's already there.
- `nix-store`, mounted at `/nix` in both containers (rw in `pkg-broker`,
  ro in `pi`). The `pkg-bin` symlinks point at absolute `/nix/store/...`
  paths; `pi` needs this volume too so those paths — and the resolved
  binaries' own RPATH/dynamic-linker dependency references — actually
  resolve inside `pi`, not just inside `pkg-broker`.

`pi` never gets write access to either volume, and never gets a
nix-daemon socket of its own.

**Persistence across runs** is opt-in/opt-out per volume via
`scripts/start-agent.sh`/`scripts/stop-agent.sh` flags or
`PI_SANDBOX__PERSIST_*` env vars (see the top-level `README.md`'s
"Persistence flags" section): `pkg-bin` defaults to **ephemeral** (removed
on teardown, so resolved binaries have to be re-resolved next run unless
`--persist-pkgs` is passed), while `nix-store` defaults to **persistent**
(kept across runs by default, so the store built up here survives
teardown; pass `--no-persist-store` to make it ephemeral too). Neither is
an `external: true` volume — these scripts just choose whether to run
`docker volume rm` on them, never tmpfs.

## Store backend (default vs. host-shared)

By default, `nix-store` is an isolated Docker volume owned by
`pkg-broker` alone — a brand-new, empty nix store the first time the
stack comes up, built up over time purely from what gets resolved
through `/resolve`. This is the safer default: `pkg-broker`'s trust
boundary doesn't extend onto the host's real nix store or daemon.

The tradeoff is reliability/speed: every resolution is a cold nix-store
lookup from `pkg-broker`'s own, initially-empty store, so even
cache-hit packages still get copied in from `cache.nixos.org` from
scratch rather than reusing anything already on the host.

`compose.pkgbroker-host-store.yaml` is an opt-in compose override that
swaps this for the host's real `/nix/store` plus the host's real
nix-daemon socket:

```sh
docker compose -f compose.yaml -f compose.pkgbroker-host-store.yaml up -d
```

The override also sets `PKG_BROKER_HOST_STORE=1`, which is what
`entrypoint.sh` keys its host-store branch off of (alongside providing
its own `NIX_REMOTE=daemon`) — without it, `entrypoint.sh` falls through
to its default chroot-store setup instead.

**This changes the trust boundary**: the host's nix-daemon becomes part
of what `pkg-broker` (and transitively, anything `pkg-broker` resolves)
can reach. Only use this override on a host where that's an acceptable
tradeoff for you — it is not the default for exactly this reason.

**Nixpkgs path differs by mode.** In the default, isolated mode,
`entrypoint.sh` copies the pinned nixpkgs tree to a plain path at
`/srv/pkg-broker/nixpkgs` on first start (see "Pinned nixpkgs copy mode
preservation" below) and resolves `nix-build` against that copy — needed
because evaluating a store-path source through a chroot store can fail.
In host-store mode there is no chroot store, so `entrypoint.sh` skips the
copy entirely and points `PKG_BROKER_NIXPKGS_PATH` straight at
`/etc/pkg-broker/nixpkgs` (the image's baked symlink to its pinned
`pkgs.path`), resolved through the host's real `/nix/store` (now
bind-mounted in at `/nix`, replacing the image's own store view).

**Prerequisite for host-store mode**: the image must have been built on
the *same host* it's run on in this mode. Because the host's real
`/nix/store` is bind-mounted over the image's own, the target of
`/etc/pkg-broker/nixpkgs` must already exist in the host's store —
an image built on a different host (or whose closure was since garbage
collected from this host's store) will fail fast at startup with a clear
error instead of serving broken `/resolve` requests. This is not made
robust beyond that fail-fast check; it's a documented constraint of this
opt-in mode, not something worked around here.

## Sandbox note

`pkg-broker`'s baked `nix.conf` sets `sandbox = true`. This is required
because `pkg-broker` builds against a *chroot store*
(`NIX_REMOTE=local?root=/srv/shared-nix`, see `entrypoint.sh`): the
store's logical dir (`/nix/store`) differs from its physical on-disk
location (`$ROOT/nix/store`). `entrypoint.sh` also exports
`PKG_BROKER_STORE_READ_ROOT` so the Go server knows where to actually
read resolved packages' `bin/` dirs from on disk (`$ROOT` in this mode,
or `/` in host-store mode, where logical and physical paths coincide) —
symlinks published into `pkg-bin` still point at the logical path, which
`pi` resolves via its own store view. Separately, the Nix sandbox is what bind-mounts
that physical location onto `/nix/store` inside each builder. Without
the sandbox, an unsandboxed build execs `/nix/store/...` builder paths
against the *broker image's own* `/nix/store` instead of the chroot
store's, and fails (`executing .../bash-static-5.3/bin/bash: No such
file or directory`). Builds still run as `pkg-broker`'s own
unprivileged uid (10003), never root -- still single-user Nix, no
`build-users-group`; the sandbox itself uses Linux user namespaces, not
setuid build users.

For the sandbox to work inside Docker, `pkg-broker`'s compose service
needs three targeted `security_opt` opt-outs (see `compose.yaml`) --
deliberately not `privileged: true` and no added capabilities:

- `seccomp:unconfined` -- the sandbox needs `unshare(CLONE_NEWUSER)`
  (user namespaces), which Docker's default seccomp profile blocks.
- `apparmor:unconfined` -- the sandbox needs to mount-bind the chroot
  store's real paths onto `/nix/store`, which Docker's default AppArmor
  profile blocks.
- `systempaths=unconfined` -- the sandbox needs a fresh `/proc` mounted
  inside its new user namespace, which Docker's masked `/proc` paths
  otherwise block.

The trade-off: these are real, if narrow, relaxations of Docker's
default container hardening (still scoped to `pkg-broker`'s own
service, still with `cap_drop: [ ALL ]` and `no-new-privileges:true`),
accepted so the chroot-store design doesn't require giving `pkg-broker`
the host's real store (see "Store backend" above) just to get working
builds.

`entrypoint.sh` runs a startup self-test in the default (chroot-store)
mode -- a tiny, uniquely-named sandboxed build -- before accepting any
`/resolve` traffic, and refuses to start (with a message pointing at
the likely causes) if sandboxed builds don't actually work. This step
is skipped in host-store mode (`compose.pkgbroker-host-store.yaml`),
where the *host's* nix-daemon does the building, not this container.

**Host prerequisite:** the host kernel must allow unprivileged user
namespaces (the default on most modern Linux distros). Some
distros/configurations restrict this further even with the above
opt-outs applied -- e.g. Ubuntu 24.04+ with
`kernel.apparmor_restrict_unprivileged_userns=1` -- in which case the
startup self-test will fail with a clear error; relaxing that sysctl is
a host-side fix outside this repo's scope.

### Pinned nixpkgs copy mode preservation (isolated mode only)

This section applies only to the default, isolated (chroot-store) mode.
Host-store mode never copies nixpkgs at all -- see "Store backend" above.

The pinned-nixpkgs copy described above (`entrypoint.sh`, first start
only, isolated mode) preserves file modes and drops only ownership
(`cp -r --no-preserve=ownership`, then `chmod -R u+w`). Nix hashes a
source path's file modes (including the executable bit) when importing
a `./path` expression, so stripping modes (the previous
`--no-preserve=mode,ownership`) changed the computed derivation hashes
and caused silent cache misses against `cache.nixos.org` -- rebuilding
everything from `bootstrap-stage0` instead of substituting.

## Fuzzy/by-binary-name package discovery

"What nixpkgs package provides the `protoc` binary?" is answered by
`POST /lookup-binary` (see above) — implemented using a prebuilt
nix-index database (`Mic92/nix-index-database`), invoked lazily via
`nix run`, candidates-only (never builds/installs). See `FOLLOWUP.md` for
the original design discussion/deferral this implements.
