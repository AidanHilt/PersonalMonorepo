{ inputs, globals, pkgs, ...}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs; };
    users.aidan = import ./home.nix {inherit inputs globals pkgs; system = pkgs.system; lib = inputs.home-manager.lib; };
  };

  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/personal.nix

    ../../../modules/roles/universal/development-machine.nix
  ];

  nixpkgs.config.allowUnfree = true;

}