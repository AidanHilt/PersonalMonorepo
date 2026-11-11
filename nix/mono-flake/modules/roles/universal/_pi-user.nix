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
# NOTE on structure: this file deliberately builds its return value with
# `lib.optionalAttrs isLinux { ... }` / `lib.optionalAttrs isDarwin { ... }`
# rather than `lib.mkIf` for anything that is a NixOS-only or
# nix-darwin-only *option* (e.g. `systemd.tmpfiles.rules`,
# `security.sudo.extraRules`, `users.knownUsers`, `isSystemUser`).
# `lib.mkIf` only makes a *value* conditional; the option itself still has
# to be declared somewhere in the imported module set, and NixOS's module
# system doesn't declare `systemd.tmpfiles.rules` when evaluating a
# nix-darwin host (and vice versa for `users.knownUsers`). `optionalAttrs`
# drops the key from the attrset entirely when the condition is false, at
# the Nix-language level, before the module system ever sees it, which is
# what's needed for options that only exist on one platform.
{
  inputs,
  globals,
  pkgs,
  machine-config,
  lib,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in

lib.mkMerge [
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
      # Needed so `sudo -u pi <command>` (see the sudo rules below) can
      # actually exec a command for this user. No password is set and
      # there is no interactive login path (no SSH keys, no wheel/sudo
      # membership, not in `nix.settings.trusted-users`), so this does
      # not grant pi any shell *access* -- only lets commands run *as*
      # pi once machine-config.username has already authenticated.
      shell = pkgs.bash;
    }
    // lib.optionalAttrs isLinux {
      group = "pi";
      isSystemUser = true;
    }
    // lib.optionalAttrs isDarwin {
      # nix-darwin's users.users.<name> takes a numeric `gid` directly
      # rather than a group name. UNVERIFIED on macOS.
      gid = 10001;
      isHidden = true;
    };

    environment.systemPackages = [
      pkgs.nono
    ];
  }

  (lib.optionalAttrs isLinux {
    # /var/lib/pi: pi's home directory and all per-run sandbox state.
    systemd.tmpfiles.rules = [
      "d /var/lib/pi 0750 pi pi - -"
    ];

    # Let machine-config.username launch the agent as `pi` without a
    # password, and without sudo stripping the PI_SANDBOX__SECRET__* env
    # vars the launcher passes through: the SETENV tag permits env vars
    # supplied on the sudo command line (or via `sudo -E`) through this
    # rule regardless of the usual `env_reset`/`env_keep` sudoers
    # defaults. No polkit path is added alongside this -- see
    # nix/agentic-ai-stack-nono/PLAN.md.
    security.sudo.extraRules = [
      {
        users = [ machine-config.username ];
        runAs = "pi";
        commands = [
          {
            command = "ALL";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];
  })

  (lib.optionalAttrs isDarwin {
    # UNVERIFIED on macOS (no Darwin host available to build/test against
    # in this change) -- written carefully from nix-darwin's documented
    # `users`/`security.sudo` module shape, but not exercised.
    users.knownUsers = [ "pi" ];
    users.knownGroups = [ "pi" ];

    # nix-darwin's security.sudo module has no `extraRules` equivalent to
    # NixOS's structured rule list, only this raw sudoers fragment.
    # `SETENV` here has the same purpose as the NixOS rule above: letting
    # PI_SANDBOX__SECRET__* env vars survive the `sudo -u pi` call.
    security.sudo.extraConfig = ''
      ${machine-config.username} ALL=(pi) NOPASSWD:SETENV: ALL
    '';

    # nix-darwin has no tmpfiles equivalent; provision /var/lib/pi on
    # activation instead.
    system.activationScripts.piHome.text = ''
      mkdir -p /var/lib/pi
      chown pi:pi /var/lib/pi
      chmod 0750 /var/lib/pi
    '';
  })
]
