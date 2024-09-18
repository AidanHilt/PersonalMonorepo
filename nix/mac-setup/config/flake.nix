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
        pkgs.p7zip
        pkgs.syncthing
        pkgs.pre-commit
        pkgs.detect-secrets
        pkgs.k9s
        pkgs.kubectx
        pkgs.kubernetes-helm
        pkgs.pipx
        pkgs.kind
        pkgs.wget
        pkgs.eza
        # TODO I think we can install NVM with Homebrew, if we need.
        # That way, if we need it for external projects, we're good
        #pkgs.nvm
        pkgs.yarn
        pkgs.postgresql
        pkgs.check-jsonschema
        pkgs.jq
        pkgs.yq
        pkgs.terragrunt
        pkgs.defaultbrowser
      ];
      security.pam.enableSudoTouchIdAuth = true;

      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config = {
        allowUnfree = true;
        packageOverrides = pkgs: {
          nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
            inherit pkgs;
          };
        };
      };

      system.stateVersion = 5;

      system.defaults = {
        dock = {
          expose-group-by-app = true;
          show-recents = false;
        };

        NSGlobalDomain = {
          "com.apple.swipescrolldirection" = false;
        };

        finder = {
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          FXEnableExtensionChangeWarning = false;
          ShowPathbar = true;
          ShowStatusBar = true;
          FXPreferredViewStyle = "icnv";
        };

        trackpad = {
          Clicking = true;
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = true;
        };
      };

      system.activationScripts = {
        postUserActivation = {
          text = "defaultbrowser firefox";
        };
      };

      users.users.aidan = {
        home = "/Users/aidan";
      };

      imports = [
        ./personal.nix
      ];

      homebrew = {
        enable = true;

        onActivation = {
          cleanup = "uninstall";
          upgrade = true;
        };

        casks = [
          "firefox"
          "google-chrome"
          "flux"
          "rectangle"
          "flycut"
          "iterm2"
          "visual-studio-code"
        ];
      };
    };

    home-dot-nix = builtins.fetchGit {
      url = "https://github.com/AidanHilt/PersonalMonorepo.git";
      ref = "feat/nix-darwin";
      rev = "a7ab75c98588602e37ce636a045cd8de68379cae"; #pragma: allowlist secret
    } + "/nix/home-manager/home.nix";
  in
  {
    darwinConfigurations."aidans-Virtual-Machine" = darwin.lib.darwinSystem {

      modules = [
        configuration

        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          #TODO Make this reach out correctly
          home-manager.users.aidan = import ./home.nix;
        }
      ];
    };
  };
}
