# nix-darwin-only half of the `pi` user (see
# ../universal/_pi-user.nix for the platform-agnostic part, and why the
# split exists). Imported only by ./darwin-universal.nix.
#
# UNVERIFIED on macOS (no Darwin host available to build/test against in
# this change) -- written carefully from nix-darwin's documented
# `users`/`security.sudo` module shape, but not exercised.
{ machine-config, ... }:

{
  users.users.pi = {
    # nix-darwin's users.users.<name> takes a numeric `gid` directly
    # rather than a group name. UNVERIFIED on macOS.
    gid = 10001;
    isHidden = true;
  };

  # UNVERIFIED on macOS: nix-darwin's `users.groups.<name>.members` is
  # assumed to mirror the nixpkgs/NixOS option of the same name (declared
  # in ../universal/_pi-user.nix), but this has not been built or tested
  # on a Darwin host.
  users.knownUsers = [ "pi" ];
  users.knownGroups = [ "pi" ];

  # nix-darwin's security.sudo module has no `extraRules` equivalent to
  # NixOS's structured rule list, only this raw sudoers fragment.
  # `SETENV` here has the same purpose as the NixOS rule in
  # ../nixos/_pi-user-linux.nix: letting PI_SANDBOX__SECRET__* env vars
  # survive the `sudo -u pi` call.
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
}
