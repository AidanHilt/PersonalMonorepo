{ inputs, globals, pkgs, ...}:

{
  home-manager = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "bak";
    home-manager.extraSpecialArgs = { inherit inputs globals pkgs; };
    home-manager.users.aidan = import ./home.nix {inherit inputs globals pkgs; system = pkgs.system; lib = home-manager.lib; };
  };

  networking.hostName = "hyperion";

  imports = [
    ../../../modules/common.nix
    ../../../modules/personal.nix
  ];

}