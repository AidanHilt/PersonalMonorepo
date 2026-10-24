# nix/mono-flake — Improvements

Known issues and cleanups found while documenting this flake, not yet
scheduled or triaged. Each item notes where it lives, what's wrong, and
why it matters. Nothing here is fixed by this document — it's a backlog.

## Darwin install flow (`darwin-install.sh`)

- **Hostname selection is cosmetic only.** The script lists hostnames
  from `machines/aarch64-darwin` and prompts for a selection, but always
  rebuilds with `selected_hostname=${hostnames[@]:0:1}` — the first
  hostname in the list — regardless of what the user picked. On a repo
  with more than one Darwin host, this silently installs the wrong
  machine's config.
- **Rebuild flake reference is pinned to `staging-cluster-k8s-work`,**
  not `main`/`master`, in the final `darwin-rebuild switch --flake
  github:AidanHilt/PersonalMonorepo/staging-cluster-k8s-work?dir=nix/mono-flake#...`
  invocation.
- **Branch default/comment mismatch.** The `branch="${1:-master}"` line
  (used only for listing hostnames via the GitHub API, not for the
  rebuild itself) is commented `# Default branch is main` but actually
  defaults to `master`.
- **No shebang, `zsh`-only syntax, Determinate Nix installer.** The file
  has no `#!/...` line and uses `zsh` array/glob syntax
  (`"${(f)$(...)}"`), so it silently requires being run under `zsh`. It
  also unconditionally installs Nix via the [Determinate Nix
  installer](https://install.determinate.systems/), which conflicts with
  the previous README text ("do NOT install determinate nix, it
  breaks... something") — that note was never reconciled with the
  script's actual behavior, and it's unclear which is correct.

## Discovery / lib-internal

- `lib-internal/discovery.nix`'s `getAllHosts` calls
  `builtins.discovery.getConfigsForSystem`, which is not a real Nix
  builtin — this function is dead and broken. Nothing in `flake.nix` or
  `lib-internal/configs.nix` calls it (they call
  `discovery.getConfigsForSystem` directly), so it has no live impact,
  but it's misleading dead code.

## Input pinning / overlays

- `flake.nix`: `inputs.scripts` is pinned to
  `github:aidanhilt/PersonalMonorepo/project-lockstep/release-mgmt?dir=nix/scripts`
  (a non-`main` branch), while `inputs.personalMonorepo` tracks `main`
  and `globals.personalMonorepoBranch` is hardcoded to `"main"`. These
  three should probably agree.
- `kernel70Nixpkgs` and `nix-cachyos-kernel` are pinned to bare commit
  SHAs rather than a branch/tag, making them harder to bump
  intentionally (Renovate/manual bumps may not notice them the same way).
- `lib-internal/packages.nix`'s `config.permittedInsecurePackages` lists
  two exact version strings (`lima-full-1.2.2`,
  `lima-additional-guestagents-1.2.2`); these will silently stop working
  the moment `nixos-lima` bumps its lima version, with no indication of
  why until the build fails.
- `lib-internal/packages.nix`'s `patches` overlay re-hashes two specific
  `grub2` patches by name and sets `aiohttp`'s `doCheck = false`, with a
  large block of commented-out `disabledTests` left in the file. Both
  look like temporary pins against a specific nixpkgs revision rather
  than permanent policy; worth revisiting (and cleaning up the dead
  comment) next time nixpkgs is bumped.

## Branch naming inconsistency

- `modules/roles/nixos/server/gitops-updater.nix` configures comin's
  local branch `main` to track the remote branch named `"master"`, and
  local branch `testing` to track `globals.personalMonorepoBranch`
  (`"main"`). Combined with `_update.nix`'s own mixed `main`/`master`
  defaults (remote default branch prompt defaults to `"main"`, but the
  non-interactive fallback inside the "if ! -z UPDATE__REMOTE_URL"
  branch defaults to `"master"`), the `main`/`master` naming is
  inconsistent enough across the flake to cause real confusion about
  which branch a given host is actually tracking.

## Duplicated config

- `machines/x86_64-linux/staging-cluster-1/configuration.nix`,
  `staging-cluster-2/configuration.nix` and
  `staging-cluster-3/configuration.nix` each inline a `home-manager =
  { ... }` block (`useGlobalPkgs`, `useUserPackages`,
  `backupFileExtension`, `extraSpecialArgs`, `users.${username} = import
  ./home.nix ...`) that duplicates what
  `modules/roles/universal/_home-manager.nix` (pulled in transitively via
  `linux-universal.nix` → `universal-base.nix`) already provides for
  every host. Not currently harmful (NixOS merges the two module
  definitions), but it's copy-pasted cruft that should be removed, and a
  trap for anyone copying one of these hosts as a template.

## Darwin guided setup

- `modules/roles/darwin/_guided-setup.nix`'s `finish-setup` script runs
  `darwin-rebuild switch --flake ~/PersonalMonorepo/nix/mac-setup`, but
  the flake actually lives at `nix/mono-flake` in this repo — `nix/mac-setup`
  doesn't exist. This step of `finish-setup` will fail as written.

## Secrets / credentials in-repo

- `modules/shared-values/laptop-cluster.nix` and
  `modules/shared-values/staging-cluster.nix` commit a `mkpasswd`-hashed
  login password directly in plaintext Nix (not agenix-encrypted).
  Low-severity (it's a hash, not the password, and these are
  dev/lab-cluster values files) but worth flagging since it's an
  unencrypted credential in version control.
- `modules/shared-machine-configs/bootstrap-image.nix` (used by the
  `iso-image-*` hosts) sets `services.openssh.settings.PermitRootLogin =
  "yes"`, `PermitEmptyPasswords = "yes"`, and
  `security.pam.services.login.allowNullPassword = true`. This is almost
  certainly intentional for an unattended installer image that only root
  SSH keys can reach, but it's worth a second pair of eyes confirming
  that's the intent and that the image is never left running longer than
  the install.

## Secrets tooling gaps

- There is no script for adding a **new** agenix secret file (as opposed
  to adding a host's key / rekeying existing files, which
  `nixos-key-retrieval` handles). It's a fully manual process: add an
  entry to `secrets/secrets.nix`, then `agenix -e <file>.age` from
  `nix/mono-flake/secrets/`.
- `app-creator-add-secret` (`nix/scripts`) is easy to mistake for an
  agenix tool because of its name's proximity to this area, but it
  targets the Kubernetes `vault-config` Helm chart, not agenix/
  `secrets.nix`. Worth a naming or doc nudge to reduce confusion.
