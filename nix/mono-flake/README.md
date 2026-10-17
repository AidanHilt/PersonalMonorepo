# nix/mono-flake

NixOS, nix-darwin and home-manager configuration for every host in this
homelab, built from a single flake (`nix/mono-flake/flake.nix`).

See [IMPLEMENTERS.md](IMPLEMENTERS.md) if you're adding or modifying a
host/module instead of just using an existing one, and
[IMPROVEMENTS.md](IMPROVEMENTS.md) for known issues referenced below.

## What this is

The flake exposes `nixosConfigurations` and `darwinConfigurations`. Hosts
are auto-discovered: any directory `machines/<system>/<name>/` that
contains a `configuration.nix` becomes `<flake>#<name>` for that system.
There's no separate host registry to edit — adding the directory is
enough (see "Common tasks" below for the script that does this for you).

## Assumption: `PERSONAL_MONOREPO_LOCATION`

Most of the day-2 scripts referenced below (and `finish-setup` on Darwin)
expect a `PERSONAL_MONOREPO_LOCATION` environment variable pointing at a
local checkout of this monorepo (default `<home>/PersonalMonorepo`, set
up by `modules/roles/universal/_personal-monorepo-constants.nix` on
development machines, and directly by `modules/roles/darwin/personal.nix`
on Darwin). If it isn't set, the scripts' `require_monorepo` check will
tell you so.

## NixOS setup

1. Build a bootstrap ISO with
   [`nix/scripts/scripts/nixos-build-x86_64-iso`](../scripts/scripts/nixos-build-x86_64-iso)
   or
   [`nix/scripts/scripts/nixos-build-aarch64-iso`](../scripts/scripts/nixos-build-aarch64-iso)
   (these just `nix build` the `iso-image-x86_64` / `iso-image-aarch64`
   hosts, which are built from
   `modules/shared-machine-configs/bootstrap-image.nix` — root SSH
   access with a fixed set of authorized keys, passwordless sudo, no
   password required). Write the resulting ISO to a USB drive and boot
   the target machine from it.
2. Once it's booted and reachable over SSH, optionally pull its hardware
   configuration with
   [`nix/scripts/scripts/nixos-hardware-config-retrieval`](../scripts/scripts/nixos-hardware-config-retrieval).
3. Run
   [`nix/scripts/scripts/nixos-remote-install`](../scripts/scripts/nixos-remote-install)
   from a machine with your `PersonalMonorepo` checkout. It will prompt
   you to pick one of the machines listed above (or pass
   `--machine-name`), ask for the target IP (`--remote-ip`), and run
   [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere)
   against it. Key flags:
   - `--homelab-node` / `--desktop` — which extra-files/secrets bundle to
     generate for the new host.
   - `--cluster-name` — required for `--homelab-node`, used to find the
     right `rke-config-<cluster>.age` secret.
   - `--post-install-ip` — IP to reconnect to once the installed system
     reboots (defaults to prompting).
   - `--retrieve-kubeconfig` / `--cluster-endpoint` — for homelab nodes,
     fetch the new cluster's kubeconfig afterwards.
   - `--nixos-anywhere-args` — extra args passed through to
     `nixos-anywhere`.

   Read the script itself for the full flow. For `--homelab-node` /
   `--desktop`, it generates the new host's SSH host key (and, for
   homelab nodes, decrypts the right `rke-config-<cluster>.age` into
   `etc/rancher/rke2/config.yaml`) via the `generate_homelab_node_files`
   / `generate_desktop_files` library functions in
   `nix/scripts/scripts/generate-node-files/lib.sh` (the identity used to
   decrypt the secret is your default OpenSSH ed25519 identity, overridable
   with `NODE_FILES_AGE_IDENTITY`). It then calls `nixos-key-retrieval` to
   add the new host's SSH key to `secrets/secrets.nix` and rekey, runs
   `nixos-anywhere` with `--extra-files`, and finishes by retrying SSH to
   the new machine and running `update`.

## Darwin setup

tl;dr:
`curl https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/refs/heads/staging-cluster-k8s-work/nix/mono-flake/darwin-install.sh -o /tmp/installer && /tmp/installer`

This runs [`darwin-install.sh`](darwin-install.sh), which installs Nix
(via the [Determinate Nix
installer](https://install.determinate.systems/)) and Homebrew, lists the
hostnames under `machines/aarch64-darwin` on GitHub, and runs
`darwin-rebuild switch` against this flake. Afterwards, open a new
terminal and run `finish-setup` (installed by
`modules/roles/darwin/_guided-setup.nix`) to set up your Firefox profile,
agenix secrets, and an rclone sync of a couple of personal directories.

**Known issues** (see [IMPROVEMENTS.md](IMPROVEMENTS.md) for the full
list and more detail):

- The hostname selection prompt is cosmetic only — `darwin-install.sh`
  always installs the *first* hostname returned by the GitHub API
  (`${hostnames[@]:0:1}`) regardless of what you select.
- The flake reference it rebuilds from is hardcoded to the
  `staging-cluster-k8s-work` branch, not `main`/`master`.
  `darwin-install.sh`'s own `branch` variable (used only for listing
  hostnames) defaults to `master`, despite a comment next to it saying
  "Default branch is main".
- It has no shebang and uses `zsh`-only array syntax
  (`"${(f)$(...)}"`), so it must be run with `zsh` even though nothing
  marks that requirement.
- It unconditionally installs Determinate Nix. The previous version of
  this README said "do NOT install determinate nix, it breaks...
  something" — that note was never reconciled with what the script
  actually does; treat the note as unverified and the script's current
  behavior (installing Determinate Nix) as what will actually happen if
  you run it.

Given the above, treat the tl;dr command as "this is what currently
ships", not as a recommendation — read `darwin-install.sh` before running
it on a new machine, and expect to need to edit the hostname/branch by
hand.

## Day-to-day updates

Every host gets an `update` command (from
`modules/roles/universal/_update.nix`, imported by `universal-base.nix`
on all hosts). Running `update` with no setup prompts you for a remote
(GitHub) or local flake source and a machine name, then runs
`nixos-rebuild switch` / `darwin-rebuild switch` accordingly; your
answers are cached in `~/.atils/update-config.env` for next time.

Homelab nodes (anything importing
`modules/shared-machine-configs/homelab-node.nix`) additionally run
[comin](https://github.com/nlewo/comin)
(`modules/roles/nixos/server/gitops-updater.nix`), which polls this
repo's `nix/mono-flake` subdirectory and auto-switches: its `main` branch
tracks the `master` branch of this repo, and its `testing` branch tracks
whatever `globals.personalMonorepoBranch` is currently set to (`main`,
hardcoded in `flake.nix`) with a `switch` operation. See
[IMPROVEMENTS.md](IMPROVEMENTS.md) for the branch-naming inconsistency
this creates.

## Common tasks

Prefer these scripts (all under `nix/scripts/scripts/`, all require
`PERSONAL_MONOREPO_LOCATION`) over hand-editing files:

- **New machine**:
  [`mono-flake-new-machine`](../scripts/scripts/mono-flake-new-machine)
  — scaffolds `machines/<system>/<name>/` from `templates/blank-machine`
  (`-s`/`--system`, `-m`/`--machine` to skip the interactive prompts).
- **Copy an existing machine**:
  [`mono-flake-copy-machine`](../scripts/scripts/mono-flake-copy-machine)
  — `-s`/`--source`, `-d`/`--destination`, `-t`/`--target-system`.
- **New module**:
  [`mono-flake-new-module`](../scripts/scripts/mono-flake-new-module)
  — scaffolds a new module from `templates/module.nix` (or
  `templates/home-manager-module.nix` with `--home-manager`) at
  `--module-path`, or interactively under `modules/`.
- **Pull a remote machine's hardware config**:
  [`nixos-hardware-config-retrieval`](../scripts/scripts/nixos-hardware-config-retrieval).
- **Build a bootstrap ISO**:
  [`nixos-build-x86_64-iso`](../scripts/scripts/nixos-build-x86_64-iso) /
  [`nixos-build-aarch64-iso`](../scripts/scripts/nixos-build-aarch64-iso).
- **Install NixOS on a new machine**:
  [`nixos-remote-install`](../scripts/scripts/nixos-remote-install) (see
  "NixOS setup" above).
- **Add a host's SSH key to `secrets/secrets.nix` and rekey**:
  [`nixos-key-retrieval`](../scripts/scripts/nixos-key-retrieval).
- **Retrieve a homelab node's kubeconfig**:
  [`nixos-kubeconfig-retrieval`](../scripts/scripts/nixos-kubeconfig-retrieval).
- **Generate a hashed password** (for a machine's `values.nix` /
  `modules/shared-values/*.nix`):
  [`system-tasks-generate-hashed-password`](../scripts/scripts/system-tasks-generate-hashed-password).
- **Commit your changes**: `kommit` (see the root
  [IMPLEMENTERS.md](../../IMPLEMENTERS.md) for repo-wide tooling).

For anything not covered by a script (e.g. adding a brand-new agenix
secret *file*), see [IMPLEMENTERS.md](IMPLEMENTERS.md#secrets).
