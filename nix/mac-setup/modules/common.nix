{ inputs, lib, pkgs, globals, ...}:
let
  nix-commit = pkgs.writeShellScriptBin "nix-commit" ''
  cd ~/PersonalMonorepo
  git add nix/*
  git commit -m "Nix commit"
  git push
'';

  reset-docker = pkgs.writeShellScriptBin "reset-docker" ''
  docker container prune --force
  docker image prune -a --force
  docker builder prune --force
'';

  update = pkgs.writeShellScriptBin "update" ''
    cd ~/PersonalMonorepo
    git pull -q
    darwin-rebuild switch --flake ~/PersonalMonorepo/nix/mac-setup
'';

  kubernetes-config = globals.nixConfig + "/shared-modules/kubernetes.nix";

in

{
  imports = [
    kubernetes-config
  ];

  programs.zsh.enable = true;

  environment.systemPackages = [
    pkgs.act
    pkgs.cargo
    pkgs.check-jsonschema
    pkgs.defaultbrowser
    pkgs.detect-secrets
    pkgs.eza
    pkgs.gettext
    pkgs.git
    pkgs.inetutils
    pkgs.jq
    pkgs.p7zip
    pkgs.pipx
    pkgs.postgresql
    pkgs.pre-commit
    pkgs.rustc
    pkgs.syncthing
    pkgs.terraform
    pkgs.terragrunt
    pkgs.vim
    pkgs.wget
    pkgs.yarn
    pkgs.yq

    inputs.agenix.packages.${pkgs.system}.agenix

    nix-commit
    reset-docker
    update
  ];
  security.pam.enableSudoTouchIdAuth = true;

  nixpkgs = {
    hostPlatform = "aarch64-darwin";

    config = {
      allowUnfree = true;
    };
  };

  system.stateVersion = 5;

  system.defaults = {
    dock = {
      expose-group-apps = true;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "icnv";
    };

    NSGlobalDomain = {
      "com.apple.swipescrolldirection" = false;
    };

    screencapture = {
      location = "/Users/aidan/Desktop/screenshots";
      show-thumbnail = false;
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

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
