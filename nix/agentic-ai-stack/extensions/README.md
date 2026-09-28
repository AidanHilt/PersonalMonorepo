# extensions/

Template/config for the **pre-built npm & git extensions** convenience
path (`../extra-extensions.nix`). This is a separate, opt-in mechanism
from `../pi-packages.nix` / `../hashes.nix`, which builds extensions from
a pinned, fully-reproducible pnpm workspace. Extensions sourced through
this directory trade that reproducibility for the convenience of pulling
straight from npm or an arbitrary git repo/rev.

**This directory is NOT wired into the main image build
(`containers/pi/image.nix`).** Building `../extra-extensions.nix` produces
a standalone derivation; it is the consumer's responsibility to manually
copy its output into their own image build (e.g.
`cp -r ${extraExtensions}/. ~/.pi/agent/extensions/`) and to merge its
`packagesListFragment` output into their own `settings.json`'s `packages`
array by hand.

## Files here

| File | Purpose |
|---|---|
| `package.json` | Plain npm (not pnpm) manifest declaring npm-sourced extensions as `dependencies`. Edit this to add/remove one. |
| `package-lock.json` | **Currently a fake, minimal placeholder** (`packages: {}`) -- it does not actually resolve `package.json`'s dependencies. Run `nix run .#update-pi-extensions` once (requires npm + network) to regenerate it for real before relying on `../extra-extensions.nix`'s npm-sourced output. |
| `git-extensions.nix` | Hand-editable, `../hashes.nix`-style map of `"git:github.com/owner/repo@rev"` specs to `fetchFromGitHub` output hashes. Currently empty (infrastructure only, no extension pinned yet). |

## Adding an npm-sourced extension

1. Add it to `package.json`'s `dependencies` (`"name": "version"`).
2. Run `nix run .#update-pi-extensions` to refresh `package-lock.json`.
3. Commit both files.

## Adding a git-sourced extension

1. Add a line to `git-extensions.nix`:
   `"git:github.com/owner/repo@rev" = pkgs.lib.fakeHash;` (or the literal
   `"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`).
2. Run `nix run .#update-pi-extensions` to compute and fill in the real hash.
3. Commit the file.

## Keeping things in sync

`nix run .#update-pi-extensions` (see `../scripts/update-pi-extensions.sh`)
regenerates `package-lock.json` from `package.json` and fills in any
unset hashes in `git-extensions.nix`. A local pre-commit hook
(`sync-pi-extensions` in the repo root's `.pre-commit-config.yaml`) runs
this automatically whenever `package.json` or `git-extensions.nix` change,
and stages the regenerated files for you.
