# nix/mono-flake — Implementers

NixOS, nix-darwin and home-manager configuration for all hosts/machines in
this repository.

See the [root IMPLEMENTERS.md](../../IMPLEMENTERS.md) for the repo-wide
convention and architecture overview, and
[IMPROVEMENTS.md](IMPROVEMENTS.md) for known issues referenced below.

## Overview

`flake.nix` only exposes `nixosConfigurations` and `darwinConfigurations`.
It computes `systems` as the subset of `inputs.systems` (the
[nix-systems](https://github.com/nix-systems/default) list) that have a
`machines/<system>/` directory, builds a `pkgsFor.<system>` package set
per system (with overlays — see "Overlays and pinned inputs" below), and
hands everything to `lib-internal/configs.nix`'s `buildAllConfigs`, which
discovers and builds every host.

## Directory layout

- `machines/<system>/<name>/` — per-host configuration. A directory only
  becomes a host if it has a `configuration.nix` (that's the entire
  discovery rule — see "How it works").
- `modules/` — shared NixOS/nix-darwin modules:
  - `modules/roles/{darwin,nixos,universal}` — composable role modules,
    organized by platform; `universal` applies to everything.
  - `modules/shared-disko-configs`, `modules/shared-hardware-configs`,
    `modules/shared-machine-configs` — larger, host-category-level
    bundles (e.g. `homelab-node.nix`, `linux-desktop.nix`,
    `bootstrap-image.nix`) that a host's `configuration.nix` imports
    directly.
  - `modules/shared-values` — shared `machine-config` fragments (see
    "Values / machine-config merge" below).
- `home-manager/{modules,shared-configs,config-files}` — home-manager
  modules and shared config consumed by per-host `home.nix` files.
- `lib-internal/` — internal Nix library code used by this flake (see
  below).
- `templates/` — scaffolding templates. These back the
  `mono-flake-new-machine` / `mono-flake-copy-machine` /
  `mono-flake-new-module` scripts (see "Making changes"); you shouldn't
  normally need to copy them by hand.
- `secrets/*.age` + `secrets/secrets.nix` — agenix-encrypted secrets (see
  "Secrets" below).

## How it works

### Discovery and `mkSystem`

- `lib-internal/discovery.nix`'s `getConfigsForSystem system machinesDir`
  lists every subdirectory of `machines/<system>` that contains a
  `configuration.nix`; that's the full host list for that system. This is
  the function `configs.nix` actually uses.
  `discovery.getAllHosts` is dead/broken code — it calls
  `builtins.discovery.getConfigsForSystem`, which doesn't exist as a Nix
  builtin, and nothing in the flake calls `getAllHosts`. See
  [IMPROVEMENTS.md](IMPROVEMENTS.md).
- `lib-internal/configs.nix`'s `buildAllConfigs` runs discovery per
  system, then `lib-internal/builders.nix`'s `mkSystemsForArch` /
  `mkSystem` build each host.
- `mkSystem` picks `darwin.lib.darwinSystem` for `aarch64-darwin`,
  otherwise `nixpkgs.lib.nixosSystem`. Every host always gets
  `home-manager`, `agenix` and `comin`'s module, plus
  `nixpkgs.pkgs = pkgsFor.<system>`; NixOS hosts (anything not
  `aarch64-darwin`) additionally get the `wsl`, `disko` and `nixos-lima`
  modules, whether or not the host actually uses them.
- `specialArgs` passed to every host module: `machine-config` (see
  below), `inputs`, `globals`, and `machineDir = "<system>/<name>"` (used
  only by `_home-manager.nix`, to resolve `machines/<machineDir>/home.nix`).

### Values / `machine-config` merge

`lib-internal/values.nix`'s `getMachineConfig name system` builds the
`machine-config` attrset every module receives, by merging, in order
(host wins via `lib.recursiveUpdate`):

1. The shared values file named by the host's `values.nix`
   `defaultValues` attribute (if set) —
   `modules/shared-values/<defaultValues>.nix` (currently
   `laptop-cluster`, `prod-cluster`, `staging-cluster`).
2. `hostname = <host name>` and `userBase` (`/Users` on
   `aarch64-darwin`, `/home` otherwise).
3. The host's own `machines/<system>/<name>/values.nix`.

### Role composition

- `modules/roles/universal/universal-base.nix` is imported by both
  `modules/roles/nixos/linux-universal.nix` and
  `modules/roles/darwin/darwin-universal.nix`, and in turn imports
  `_update.nix` (installs the `update` command, see the README) and
  `_home-manager.nix` (wires up `home-manager.users.${machine-config.username}`
  from `machines/<machineDir>/home.nix`). Nearly every host imports
  `linux-universal.nix` or `darwin-universal.nix` (directly, or via a
  `shared-machine-configs/*.nix` bundle), so this is where truly
  universal config belongs — see the comment at the top of the file.
- NixOS homelab nodes import
  `modules/shared-machine-configs/homelab-node.nix`, which pulls in
  `roles/nixos/server/{adguard,rke,gitops-updater}.nix` and
  `roles/nixos/fixed-ip-machine.nix`, plus
  `roles/nixos/server/keepalived.nix` when the host's
  `machine-config.networking.loadBalancerIp` is set.
- Darwin hosts import `roles/darwin/darwin-universal.nix` plus a
  "flavor" module (`personal.nix` or `work.nix`) that adds
  machine-specific packages/Homebrew casks/etc.

### comin (GitOps auto-update)

`modules/roles/nixos/server/gitops-updater.nix` (imported by
`homelab-node.nix`) configures `services.comin` with
`repositorySubdir = "nix/mono-flake"` against `remotes.origin.url =
globals.personalMonorepoURL`. Two tracked branches:

- `main` (comin's local branch name) tracks the remote branch named
  `"master"`.
- `testing` tracks the remote branch named `globals.personalMonorepoBranch`
  (hardcoded to `"main"` in `flake.nix`), with `operation = "switch"`.

This naming is confusing by design of the current code, not a typo in
this doc — see [IMPROVEMENTS.md](IMPROVEMENTS.md).

### `PERSONAL_MONOREPO_LOCATION`

Set by `modules/roles/universal/_personal-monorepo-constants.nix`
(default `<userBase>/<username>/PersonalMonorepo`, only wired up via
`modules/roles/universal/development-machine.nix`) and directly by
`modules/roles/darwin/personal.nix`. The scripts referenced throughout
this doc require it (via the `nix/scripts` `env-checks` lib's
`require_monorepo`).

### The `pi` user

The `pi` user/group (uid/gid 10001, home `/var/lib/pi`) is a dedicated,
**untrusted** user that the `nix/agentic-ai-stack-nono` agent sandbox runs
as — see that project's `PLAN.md`, section 2 ("Isolation user"), for why.
It's defined across three files rather than one, because NixOS modules
cannot select *option names* based on `pkgs` (`pkgs` itself derives from
`config`, so branching an option's existence on
`pkgs.stdenv.hostPlatform.isLinux`/`isDarwin` inside a single shared
module is a recursion bug, not just a style choice — an earlier version
of this module did exactly that and triggered infinite recursion on
evaluation):

- `modules/roles/universal/_pi-user.nix` (imported by `universal-base.nix`,
  so every NixOS and nix-darwin host gets it) declares only the options
  that exist identically on both platforms: `users.groups.pi`,
  `users.users.pi`'s common attrs (`uid`, `home`, `description`, `shell`),
  and `environment.systemPackages = [ pkgs.nono ]`.
- `modules/roles/nixos/_pi-user-linux.nix` (imported only by
  `linux-universal.nix`) adds the NixOS-only options:
  `users.users.pi.group`/`isSystemUser`, `systemd.tmpfiles.rules`
  (provisions `/var/lib/pi`), and `security.sudo.extraRules` (the
  `NOPASSWD`+`SETENV` rule letting `machine-config.username` run
  `sudo -u pi` without a password, with `PI_SANDBOX__SECRET__*` env vars
  surviving the call).
- `modules/roles/darwin/_pi-user-darwin.nix` (imported only by
  `darwin-universal.nix`) adds the nix-darwin-only options:
  `users.users.pi.gid`/`isHidden`, `users.knownUsers`/`knownGroups`,
  `security.sudo.extraConfig` (the raw sudoers-fragment equivalent of the
  NixOS rule above, since nix-darwin's `security.sudo` module has no
  structured `extraRules`), and `system.activationScripts.piHome` (the
  nix-darwin equivalent of `systemd.tmpfiles`, since darwin has no
  tmpfiles). This whole file is **unverified** — it has not been built or
  run on an actual Darwin host.

`machine-config.username` is made a member of the `pi` group via
`users.groups.pi.members` (not per-user `extraGroups`), so adding a new
host doesn't require repeating the membership by hand — this replaced a
hand-rolled `users.groups.pi` + `extraGroups` pair that used to live
directly in `machines/x86_64-linux/big-boi-desktop/configuration.nix` and
`machines/aarch64-linux/devbox/configuration.nix`. `pi` is deliberately
kept out of `nix.settings.trusted-users`, has no password/SSH keys/wheel
membership, and is reached only via `sudo -u pi` from
`machine-config.username`.

### Overlays and pinned inputs

`lib-internal/packages.nix`'s `genPkgsFor` applies, per system:
`baseOverlays` (nur, agenix, nix-vscode-extensions, nix-cachyos-kernel,
`overlays/nono.nix`), any `platformOverlays.<system>` from `flake.nix`
(currently just a
`nodejs_22` override on `aarch64-darwin`), and a fixed `patches` overlay
that re-hashes two `grub2` patches and disables `aiohttp`'s test suite
(`doCheck = false`, with a block of commented-out `disabledTests` left in
place). These look like temporary pins against specific nixpkgs
revisions rather than permanent policy — see
[IMPROVEMENTS.md](IMPROVEMENTS.md) before assuming they're still needed.
`config.permittedInsecurePackages` also hardcodes two exact `lima`
package-version strings.

`flake.nix`'s `inputs.scripts` is pinned to the
`project-lockstep/release-mgmt` branch of this repo (not `main`), and
`inputs.personalMonorepo` to `main` — see IMPROVEMENTS.md for the
resulting inconsistency with `globals.personalMonorepoBranch`.
`kernel70Nixpkgs` and `nix-cachyos-kernel` are pinned to bare commit
SHAs rather than branches/tags.

`overlays/nono.nix` builds `pkgs.nono` (the Landlock/Seatbelt sandbox used
by `nix/agentic-ai-stack-nono`) from source via `rustPlatform.buildRustPackage`,
pinned to a `nolabs-ai/nono` git tag, because nixpkgs lags far behind
upstream's releases and upstream's own flake `#prebuilt` output was found
to ship a stale hash for x86_64-linux. Its `src.hash`/`cargoHash` are
hand-computed and **must be re-verified on every version bump** — see the
comment at the top of that file for the fake-hash-then-rebuild procedure.
Its first version bump (to 0.81.0, done alongside the `pi` user work above)
could not be completed in a sandboxed environment with no general network
or build access; both hashes are still placeholders there and must be
filled in by whoever next has the access to actually build it.

## Secrets

`secrets/secrets.nix` defines age recipient groups (lists of SSH public
keys) and, at the bottom, which group can decrypt each `*.age` file:
per-user/dev machines (`user-machines`), and per-cluster machine groups
(`laptop-cluster-machines`, `staging-cluster-machines`,
`prod-cluster-machines`, `external-user-1-machines`) composed into each
secret's `publicKeys` list (e.g. `hosts.age`, `github-config.age`,
`rclone-config.age`, `kubeconfig.age`, `adguardhome.age`, and one
`rke-config-<cluster>.age` per cluster).

- **Adding a new host's key and rekeying** (the common case — installing
  a new machine, or rotating a key): use
  [`nix/scripts/scripts/nixos/nixos-key-retrieval`](../scripts/scripts/nixos/nixos-key-retrieval),
  which appends the key to `secrets.nix` via
  [`_modify-secrets-nix-let-statement`](../scripts/scripts/_modify-secrets-nix-let-statement)
  and then runs `agenix -r` from the `secrets/` directory to rekey every
  file.
- **Adding a brand-new secret *file*** (a new `*.age` nobody has created
  before): there is no script for this. Add an entry (name +
  `publicKeys`) to `secrets/secrets.nix` by hand, then run
  `agenix -e <file>.age` from `nix/mono-flake/secrets/`.
- Don't confuse this with `app-creator-add-secret` (`nix/scripts`) —
  that script adds a secret to the Kubernetes `vault-config` Helm chart,
  which is unrelated to agenix/`secrets.nix`.

## Making changes

Prefer the scripts under `nix/scripts/scripts/` over hand-editing, in
roughly this order of how often you'll need them:

- New host: `mono-flake-new-machine` (scaffolds from
  `templates/blank-machine`).
- Clone an existing host: `mono-flake-copy-machine`.
- New module: `mono-flake-new-module` (`--home-manager` for a
  home-manager module; otherwise from `templates/module.nix`).
- New host's SSH key / rekey: `nixos-key-retrieval`.
- Bootstrap ISOs: `nixos-build-x86_64-iso` / `nixos-build-aarch64-iso`.

See the [README](README.md#common-tasks) for the full list with
descriptions, and "Secrets" above for the one common manual step (new
secret *file*). Everything else not covered by a script (editing a
`modules/roles/*` file, wiring a new `shared-machine-configs/*.nix`
bundle, adjusting `lib-internal/`) is a normal hand-edit — there's no
generated/derived state in this flake beyond what's described above.

## Gotchas

- `discovery.getAllHosts` is broken (see "How it works") — don't build
  on it; use `getConfigsForSystem` (what `configs.nix` actually calls)
  if you need the host list for a system.
- Several `machines/x86_64-linux/staging-cluster-*/configuration.nix`
  files inline a `home-manager = { ... }` block that duplicates what
  `universal-base.nix` → `_home-manager.nix` already provides for every
  host; harmless (NixOS module merge), but don't copy it into new hosts.
- `modules/shared-values/{laptop-cluster,staging-cluster}.nix` commit a
  `mkpasswd`-hashed password in plaintext to the repo (not agenix); keep
  this in mind if you're basing a new shared-values file on them.
- `modules/shared-machine-configs/bootstrap-image.nix` (the ISO image
  config) permits root SSH login with an empty password — intentional
  for an unattended installer image, but don't reuse the module for
  anything that isn't the bootstrap ISO.
- See [IMPROVEMENTS.md](IMPROVEMENTS.md) for a fuller list of known
  issues (input pinning, overlay cruft, branch-naming inconsistencies,
  the Darwin install flow) that aren't repeated here.
