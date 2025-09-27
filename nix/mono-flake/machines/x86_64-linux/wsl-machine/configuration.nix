{ config, pkgs, machine-config, inputs, globals, ... }:


{
  imports = [
    ../../../modules/shared-machine-configs/linux-desktop-terminal.nix
    ../../../modules/nixos/rclone.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  networking.hostName = "wsl-machine";

  wsl = {
    enable = true;
    defaultUser = "${machine-config.username}";
  };
}