{ inputs, globals, pkgs, machine-config, ...}:

let 
  importingDir = builtins.toString (builtins.dirOf (__curPos.file or ./.));
in

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.${machine-config.username} = import "${importingDir}/home.nix" {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };
}