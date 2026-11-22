# start-pi-agent

Launches the pi agent sandbox (`nix run .#start-agent` from
`nix/agentic-ai-stack`) with the `GITHUB_TOKEN` and `EXA_API_KEY` secrets
pulled from KeePass and the personal monorepo added, runnable from
anywhere.

## Usage

```sh
start-pi-agent [-- extra start-agent args]
```

Any arguments are passed straight through to `nix run .#start-agent --`,
after the `--secret`/`--add` flags this script adds itself.

## What it does

- Requires `PERSONAL_MONOREPO_LOCATION` to be set and point at an existing
  directory.
- Retrieves `GITHUB_TOKEN` (`Internet/Github`, key `PI_GITHUB_TOKEN`) and
  `EXA_API_KEY` (`Internet/Personal Computers, Servers, and Services/Exa
  AI`, default `Password` field) via `keepass-retrieve-secret`.
- `cd`s into `$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack` and execs
  `nix run .#start-agent -- --secret GITHUB_TOKEN=... --secret
  EXA_API_KEY=... --add "$PERSONAL_MONOREPO_LOCATION" "$@"`.

## Prerequisites

- Same as [keepass-retrieve-secret](../keepass-retrieve-secret/README.md):
  `keepassxc-cli`/`age` on `PATH`, KeePass config env vars set.
- `PERSONAL_MONOREPO_LOCATION` set to the personal monorepo checkout.
