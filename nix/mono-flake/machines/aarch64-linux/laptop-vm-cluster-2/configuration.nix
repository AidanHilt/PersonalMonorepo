{ config, pkgs, machine-config, inputs, globals, ... }:

{
  home-manager = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "bak";
    home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
    home-manager.users.${machine-config.username} = import ../../../home-manager/shared-configs/server.nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
  };

  networking.hostname = "laptop-vm-cluster-2";

  imports = [
    ../../../modules/machine-categories/laptop-vm-cluster.nix
  ];
}