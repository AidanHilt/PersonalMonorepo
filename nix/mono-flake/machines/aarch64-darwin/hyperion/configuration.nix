{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.aidan = import ./home.nix {inherit inputs globals machine-config pkgs; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/personal.nix

    ../../../modules/roles/universal/development-machine.nix
    ../../../modules/roles/universal/linux-admin.nix
  ];
}