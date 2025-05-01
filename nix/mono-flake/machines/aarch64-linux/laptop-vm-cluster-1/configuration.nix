{ config, pkgs, machine-config, inputs, globals, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs; };
    users.${machine-config.username} = import ../../../home-manager/shared-configs/server.nix {inherit inputs globals pkgs; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  imports = [
    ../../../modules/machine-categories/laptop-vm-cluster.nix
  ];

}