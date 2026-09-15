# Ollama: native host setup (spec §3.3)

Ollama is **not** part of the compose stack. It runs natively on the
host — on macOS/Apple Silicon this avoids the ~15-20% inference
throughput cost of GPU passthrough into a Colima `krunkit` VM; on NixOS
it just runs with direct hardware access by default. `nix run
.#start-agent` checks that it's reachable and fails fast with a clear
message if it isn't; it does not install or start Ollama for you.

## Install

- **macOS:** `brew install ollama`, or the Ollama.app download.
- **NixOS:** `services.ollama.enable = true;` in your host configuration
  (enables GPU acceleration automatically if a supported discrete GPU
  is present — no passthrough question at all, since it's native).

## Harden before pointing the sandbox at it (spec §3.3)

Ollama is a real network service with its own attack surface — treat it
as semi-trusted, not a passive black box:

1. **Bind to a narrow interface, not `0.0.0.0`.** Only the interface
   reachable from the container network needs to see it (loopback, plus
   whatever bridge address `proxy`'s `OLLAMA_UPSTREAM` resolves to).
   Set via `OLLAMA_HOST` — check `docs.ollama.com` for the current
   default and confirm your version doesn't already bind broadly.
2. **Check current CVEs before deploying, and re-check periodically.**
   Ollama has had multiple 2026 CVEs, including an unauthenticated
   remote memory-disclosure bug and a path-traversal bug in
   model-transfer handling. Pin a patched version and set a recurring
   reminder to check again — this surface moves fast.
3. **Never expose it directly to the `pi` container.** All
   container→Ollama traffic goes through `proxy`'s Ollama gate
   (`containers/proxy/ollama-gate.nginx.conf.template`), which allows
   only inference endpoints and denies model management
   (`/api/pull`, `/api/create`, `/api/push`, `/api/delete`,
   `/api/copy`). Pulling/managing models is a manual, host-side
   operation — e.g. `ollama pull qwen2.5-coder:7b` — performed outside
   this stack entirely.

## Model

Default: `qwen2.5-coder:7b` (spec §10). Pull it once on the host:

```sh
ollama pull qwen2.5-coder:7b
```

To use a different model, override it in `.env` /
`config/pi/models.json`, and pass `--override-model` to
`start-agent` if you've wired that flag into your local copy of the
script (spec §10 asks for a start-agent override option — add a
`MODEL=` env passthrough here if the default doesn't fit your
hardware).

## Confirm host-loopback-from-container behavior before relying on it

This differs by platform and by Docker/Colima version (spec §3.3/§9):

- **Colima:** verify whether `host.docker.internal` resolves inside
  containers on the Colima version in use — behavior has changed
  across releases. `compose.yaml`'s `extra_hosts: host-gateway` entry
  is there specifically to make this reliable either way.
- **NixOS native Docker:** typically needs the explicit
  `host-gateway` special value in `extra_hosts` (already set in
  `compose.yaml`) or the bridge network's gateway IP directly.

If `nix run .#start-agent`'s health check passes but the `proxy`
container's Ollama gate still can't reach it, this is almost always
where to look first.
