# pi: a dedicated, UNTRUSTED user that the nono-based agent sandbox (see
# nix/agentic-ai-stack-nono/PLAN.md, section 2, "Isolation user") runs as.
# It must stay out of `nix.settings.trusted-users` -- that's what makes it
# safe to allow this user Nix daemon access at all (see the same PLAN.md,
# "Nix daemon access" row).
#
# Imported from ./universal-base.nix, so this applies to every NixOS and
# nix-darwin host in the fleet. Split into its own file (rather than folded
# into universal-base.nix) because it's a reasonably self-contained unit of
# config, matching the pattern of _update.nix/_home-manager.nix next to it.
#
# This file is deliberately platform-agnostic: it only declares options
# (`users.groups.pi`, `users.users.pi`, `environment.systemPackages`) that
# exist identically on both NixOS and nix-darwin, and it never branches on
# `pkgs.stdenv.hostPlatform` or anything else config/pkgs-derived to decide
# which *option names* to set. Module option names cannot depend on `pkgs`
# (`pkgs` itself derives from `config`, so that's recursive by
# construction) -- only option *values* may. The platform-specific options
# (`isSystemUser`, `systemd.tmpfiles.rules`, `security.sudo.extraRules`,
# `users.knownUsers`, the darwin `gid`/activation script, etc.) live in
# ../nixos/_pi-user-linux.nix and ../darwin/_pi-user-darwin.nix instead,
# each imported only by that platform's `*-universal.nix`.
{
  pkgs,
  machine-config,
  pkgs-unstable,
  ...
}:

{
  users.groups.pi = {
    gid = 10001;
    # `members` (rather than per-user `extraGroups`, which is what the
    # two hosts that predated this module used) so this one definition
    # of "machine-config.username can act as pi" works the same on both
    # platforms, instead of hardcoding a username per host. UNVERIFIED
    # on macOS: nix-darwin's `users.groups.<name>.members` is assumed to
    # mirror the nixpkgs/NixOS option of the same name, but this has not
    # been built or tested on a Darwin host.
    members = [ machine-config.username ];
  };

  users.users.pi = {
    uid = 10001;
    home = "/var/lib/pi";
    description = "Sandboxed agent user (nono isolation; see nix/agentic-ai-stack-nono)";
    # Needed so `sudo -u pi <command>` (see the sudo rules in
    # ../nixos/_pi-user-linux.nix / ../darwin/_pi-user-darwin.nix) can
    # actually exec a command for this user. No password is set and
    # there is no interactive login path (no SSH keys, no wheel/sudo
    # membership, not in `nix.settings.trusted-users`), so this does
    # not grant pi any shell *access* -- only lets commands run *as*
    # pi once machine-config.username has already authenticated.
    shell = pkgs.bash;
  };

  environment.systemPackages = [
    pkgs-unstable.nono
  ];
}
