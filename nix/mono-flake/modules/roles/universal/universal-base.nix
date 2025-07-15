# Note: This file is likely going to be pretty small, although the bigger we can get it, the better
# This file is going to be imported by ALL machine categories, so you better make sure it's truly universal
{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./_update.nix
    ./_home-manager.nix
  ];

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  networking.hostName = machine-config.hostname;

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
  ];

  users.users."${machine-config.username}" = {
    home = "${machine-config.userBase}/${machine-config.username}";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos"
    ];
  };
}