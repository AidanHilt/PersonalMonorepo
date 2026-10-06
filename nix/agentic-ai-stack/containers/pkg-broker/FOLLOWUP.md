# Follow-up: fuzzy / by-binary-name package discovery for pkg-broker

**Status: implemented.** `POST /lookup-binary` (see `README.md` for full
behavior) answers "which nixpkgs attribute(s) provide a binary named X" —
e.g. "what provides `protoc`?" → `protobuf`. This file is kept as a record
of the original design discussion and where the final implementation
deliberately diverged from it; `README.md` is the authoritative,
up-to-date description of the endpoint itself.

## What was originally discussed (and what changed)

The original planning discussion (preserved below) proposed using
**nix-index** together with its **comma** (`,`) companion tool, and
suggested that an exact single match could be auto-resolved (reusing the
`/resolve` build/publish path) rather than always returned as a
disambiguation list. The actual implementation differs from both of
those on points the user decided explicitly when this was built:

- **`nix-locate`, not `comma`.** `comma` is built for "run this binary
  right now, installing it transiently if needed" — a different shape
  than "tell me the candidate attribute(s) and let the caller decide
  what to do next." `/lookup-binary` shells out to `nix-locate` (also
  part of nix-index, via the `Mic92/nix-index-database` flake's
  `nix-index-with-db` app) directly.
- **`/lookup-binary` always returns candidates only — never builds or
  installs, even for a single unambiguous match.** The caller (the
  `pkg-install --by-binary` CLI mode, or a human) always makes a
  separate `/resolve` call with the attribute it wants. This keeps the
  trust/validation story simple: every attribute that actually gets
  built goes through `/resolve`'s own independent validation, every
  time, with no implicit "good enough, just build it" path hanging off
  looked-up (community-tool-derived) data.
- **`nix-index-database` is pinned as a real flake input** (`flake.lock`
  owns it, see `flake.nix`'s `nix-index-database` input and its
  `nixIndexRef` derivation), not left referenced only by a hardcoded
  string in `main.go`/`image.nix`. The database itself still isn't part
  of any image closure, and is still fetched lazily via `nix run` only
  on first actual use — see README.md's "Pinning nix-index-database"
  section for the full rationale (the original concern about bloating
  every image build still holds and is still avoided).

## Original discussion (for context)

What follows is the original note, substantially unchanged except where
it's now wrong about the tool choice / auto-resolve behavior (corrected
above).

`pkg-broker` (`containers/pkg-broker/`) originally only supported
resolving an **exact** nixpkgs attribute name via `POST /resolve
{"attr": "..."}`. If you don't already know the exact attribute name for
a package — e.g. you know you want "whatever provides the `protoc`
binary" but not that it's `nixpkgs#protobuf` — `/lookup-binary` is what
answers that question now.

Key design point that *did* carry through to the implementation: invoke
nix-index **lazily via `nix run`** against the `Mic92/nix-index-database`
prebuilt database, rather than pinning it into every `pkg-broker` image
build — building a nix-index database from scratch is a slow,
full-nixpkgs-eval operation that's a bad fit for a container that's
supposed to stay small and respond quickly, and baking the database
itself (even pre-built) into the image closure would bloat every build
regardless of whether fuzzy lookup is ever used.

`pkg-install` (`nix/scripts/scripts/pkg-install/`) has a `--by-binary
<name>` mode that hits `/lookup-binary` and prints the candidate(s) (and,
for an unambiguous single candidate, the exact follow-up `pkg-install
<attr>` command) — it does not auto-install.

`compose.yaml`/network topology did not need to change for this —
`pkg-broker` already had the external network leg this needs.
