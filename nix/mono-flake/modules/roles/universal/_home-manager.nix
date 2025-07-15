{ inputs, globals, pkgs, machine-config, ...}:

let 
  callerFile = builtins.unsafeGetAttrPos "imports" config;
  callerDir = if callerFile != null then builtins.dirOf callerFile.file else ./.;
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