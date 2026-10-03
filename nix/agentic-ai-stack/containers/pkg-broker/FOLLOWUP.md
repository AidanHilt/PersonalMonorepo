# Follow-up: fuzzy / by-binary-name package discovery for pkg-broker

**Status:** deliberately deferred, not implemented. This note exists so a
fresh agent with no other context can pick this up later — the user
expects to destroy and recreate their working environment before this
follow-up happens, so don't assume any planning-session context survives.

## What exists today

`pkg-broker` (`containers/pkg-broker/`) only supports resolving an
**exact** nixpkgs attribute name via `POST /resolve {"attr": "..."}` (see
`main.go`). If you don't already know the exact attribute name for a
package — e.g. you know you want "whatever provides the `protoc`
binary" but not that it's `nixpkgs#protobuf` — there is currently no way
to ask pkg-broker that question. The caller has to already know (or
guess, or search nixpkgs some other way) the exact attribute.

## What was discussed and deferred

Add a second, equally narrow endpoint — something like
`POST /lookup-binary {"binary": "protoc"}` — that answers "which nixpkgs
attribute(s) provide a binary named X" using **nix-index**
(github.com/nix-community/nix-index) and its "comma" (`,`) companion
tool, specifically using the **prebuilt database** from
**Mic92/nix-index-database** (https://github.com/Mic92/nix-index-database)
rather than building/maintaining the index locally — building a nix-index
database from scratch is a slow, full-nixpkgs-eval operation that's a bad
fit for a container that's supposed to stay small and respond quickly.

Key design point from the planning discussion: invoke this **lazily via
`nix run`** (e.g. `nix run github:nix-community/nix-index#comma -- <name>`
or equivalent, against the Mic92/nix-index-database flake output) rather
than pinning nix-index/comma/nix-index-database as flake inputs of
`nix/agentic-ai-stack/flake.nix`. Pinning them as inputs would bloat
every `pi-image`/`pkg-broker` build and the flake.lock regardless of
whether fuzzy lookup is ever used; invoking lazily via `nix run` against
pkg-broker's own unproxied `external` network leg keeps the image small
and only pays the (larger) nix-index-database download cost the first
time someone actually uses fuzzy lookup.

## Where this plugs into pkg-broker

- New handler in `main.go`, parallel to `handleResolve`: validate the
  requested binary name (same spirit as `attrPattern`/`validateAttr` —
  strict allow-list, no shell metacharacters), shell out to
  `nix run` with the nix-index-database flake ref + `comma`/`nix-locate`
  equivalent, parse the resulting candidate attribute name(s), and either:
  - if there's exactly one unambiguous match, resolve it the normal way
    (reuse the existing `nixBuild`/`publishBinaries` path), or
  - if there are multiple candidates, return them as a disambiguation
    list for the caller (`pkg-install` CLI or a human) to choose from
    rather than guessing.
- `pkg-install` (`nix/scripts/scripts/pkg-install/`) would need a new
  flag/mode (e.g. `pkg-install --by-binary <name>`) to hit this endpoint
  instead of `/resolve`.
- `compose.yaml`/network topology do **not** need to change for this —
  `pkg-broker` already has the external network leg this needs.

## Why it was deferred

Scoped out to keep this implementation pass's surface small and
reviewable: exact-attribute resolution is the minimum viable version of
"install arbitrary nixpkgs software on demand," and fuzzy lookup is a
genuinely separate feature (different trust/validation story for
user-supplied binary names vs. attribute names, a new external
dependency to vet, and a UX question — disambiguation — that the
exact-attr path doesn't have). Build and validate the exact-attr path
first; revisit this once that's proven out.
