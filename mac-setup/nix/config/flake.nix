{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager }:
  let
    configuration = {pkgs, ...}: {
      services.nix-daemon.enable = true;

      programs.zsh.enable = true;

      environment.systemPackages = [
        pkgs.vim
        pkgs.python3
        pkgs.act
        pkgs.git
        pkgs.kubectl
      ];
      security.pam.enableSudoTouchIdAuth = true;

      nixpkgs.hostPlatform = "aarch64-darwin";

      system.stateVersion = 5;
    };

    home-dot-nix = builtins.fetchGit {
      url = "https://github.com/AidanHilt/PersonalMonorepo.git";
      ref = "feat/nix-darwin";
      rev = "a7ab75c98588602e37ce636a045cd8de68379cae"; #pragma: allowlist secret
    } + "/nix/home-manager/home.nix";
  in
  {
    darwinConfigurations."testmans-Virtual-Machine" = darwin.lib.darwinSystem {

      modules = [
        configuration

        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.aidan = import home-dot-nix;
        }
      ];
    };
  };
}
