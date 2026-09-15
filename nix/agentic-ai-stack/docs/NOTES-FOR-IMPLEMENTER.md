# Notes for the implementer

This repo is a complete, working scaffold, built and cross-checked
against current upstream docs/source where network access allowed it
during authoring (pi's own docs, `@gotgenes/pi-permission-system`'s
README/ADRs, and Ollama's current API reference). It was **not** built
or run against a live Nix daemon or Docker socket — neither was
available in the environment that produced it. Before treating this as
done, work through the following:

## Must verify / finish before first real run

1. **`npmDepsHash` in `containers/pi/image.nix` is a placeholder.**
   `buildNpmPackage` needs the real fixed-output-derivation hash for
   `containers/pi/npm-src/package-lock.json` (which *is* real — pinned
   to `@earendil-works/pi-coding-agent@0.85.1` and
   `@gotgenes/pi-permission-system@32.0.2` via a live `npm install
   --package-lock-only` against the real registry). Run `nix build
   .#pi-image` once; Nix's hash-mismatch error prints the correct value
   — paste it in.
2. **`config/pi/settings.json` keys are a best-effort guess** at the
   current schema (`shellPath`, `thinking.default`, `notifications.*`,
   `npmCommand`, `compaction.auto`) based on prose in `docs/settings.md`,
   not a copy of a confirmed example file. Diff against that doc for
   pi 0.85.1 before relying on any key here mattering.
3. **`config/pi/permission-system.config.json`** schema (the flat
   `permission.{*, path, read, write, edit, bash, external_directory}`
   shape, most-restrictive-wins layering) is confirmed against
   `@gotgenes/pi-permission-system`'s README and ADR-0013 for v32.x.
   Re-check `docs/configuration.md` in that package for the exact glob
   syntax it expects (this repo uses `**/…` glob patterns for
   kubeconfig/SSH/cloud-credential paths — confirm the matcher supports
   that syntax before trusting the deny rules).
4. **Colima rootless Docker support** (spec §3.1's "rootless if the
   runtime supports it cleanly on both hosts") needs a real check
   against the Colima version you deploy — this scaffold does not set
   a rootless runtime by default; it relies on `cap_drop: [ALL]` +
   `no-new-privileges` + `read_only` instead, which work everywhere.
   Layer rootless on top once confirmed compatible.
5. **`host.docker.internal` / host-gateway behavior** — see
   `ollama/README.md`. `compose.yaml` sets `extra_hosts:
   host-gateway`, which should cover both platforms, but confirm on
   the actual Colima/Docker versions in use.
6. **Ollama API surface**: confirmed against Ollama's current docs
   (Sept 2026) — inference: `/api/generate`, `/api/chat`, `/api/embed`
   (superseding `/api/embeddings`), plus OpenAI-compatible
   `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`,
   `/v1/models`; management (denied by the gate):
   `/api/pull`, `/api/create`, `/api/push`, `/api/delete`, `/api/copy`.
   Since `config/pi/models.json` uses `api: openai-completions` against
   `/v1`, the gate's `/v1/*` rules are what actually matter in
   practice — re-verify path names against the exact Ollama version you
   deploy (`ollama --version`), since this has shifted before.
7. **A Linux builder for `nix build` on macOS** is required (spec §9)
   — either `nix-darwin`'s `nix.linux-builder` or the NixOS box as a
   remote builder over SSH. Not configured here since it's host-specific.
8. **Compose `login` OAuth callback path**: this scaffold gives the
   `login` profile a normal bridged network so a loopback OAuth
   redirect can complete, but doesn't attempt to reserve/forward a
   specific callback port — check `docs/providers.md` for whether the
   provider you use needs one, and add a `ports:` entry to the `login`
   service in `compose.yaml` if so.

## Deliberately out of scope (per spec §2)

- Hardening against a fully malicious actor with local code execution
  already on the host/hypervisor. The container + network boundary is
  meant to contain "agent went off the rails," not a targeted escape.
- Availability/performance guarantees.

## Suggested first run order

```sh
cd pi-sandbox-stack
cp .env.example .env            # fill in keys or plan to use `nix run .#login`
nix run .#gen-kubeconfig -- <your-dev-context>
ollama pull qwen2.5-coder:7b    # on the host, natively
nix build .#pi-image            # fix npmDepsHash from the error, retry
nix build .#proxy-image
nix run .#login                 # if using OAuth; type /login inside pi
nix run .#start-agent
nix run .#verify                # in another terminal, once pi is up
```
