{ inputs, globals, pkgs, ...}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs; };
    users.aidan = import ./home.nix {inherit inputs globals pkgs; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  networking.hostName = "hyperion";

  imports = [
    ../../../modules/common.nix
    ../../../modules/personal.nix
  ];

}