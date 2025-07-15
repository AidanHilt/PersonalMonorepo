{ inputs, globals, pkgs, machine-config, machineDir, ...}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import "../../../machines/${machineDir}/home.nix" {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };
}