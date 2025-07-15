{ inputs, globals, pkgs, machine-config, ...}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };
}