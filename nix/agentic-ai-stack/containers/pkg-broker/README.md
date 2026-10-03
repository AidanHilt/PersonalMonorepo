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
third-party deps), one HTTP endpoint, no persistent install-state beyond
what the nix store naturally provides.

## What it does

`pkg-broker` is dual-homed on both the `internal` and `external` compose
networks (same shape as `proxy`), but unlike `proxy` it does **not** sit
in `pi`'s egress path at all. It exposes exactly one endpoint, reachable
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

**This changes the trust boundary**: the host's nix-daemon becomes part
of what `pkg-broker` (and transitively, anything `pkg-broker` resolves)
can reach. Only use this override on a host where that's an acceptable
tradeoff for you — it is not the default for exactly this reason.

## Sandbox note

`pkg-broker`'s baked `nix.conf` sets `sandbox = false` and runs
single-user (no `build-users-group`). This container has no spare
privilege to set up nix's own build sandbox (user namespaces / bind
mounts), and — per `PROJECT-SPEC.md` §2's stated philosophy — the actual
security boundary for this whole stack is the container + network
isolation around each service, not nix's own build sandbox nested inside
one of them. Builds still run as `pkg-broker`'s own unprivileged uid
(10003), never root.

## Deferred follow-up

Fuzzy/by-binary-name package discovery (e.g. "what package provides
`protoc`?") was deliberately deferred out of this pass — see
`FOLLOWUP.md`.
