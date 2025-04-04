{ config, pkgs, machine-config, inputs, globals, ... }:


{
  imports = [
    ../../../modules/machine-categories/linux-desktop-terminal.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs; };
    users.${machine-config.username} = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = home-manager.lib; };
  };

  networking.hostName = "wsl-machine";

  wsl = {
    enable = true;
    defaultUser = "nixos";
  };

  specialArgs = { inherit inputs globals; };
}