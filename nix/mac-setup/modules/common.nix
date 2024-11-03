{ inputs, lib, pkgs, ...}:
let

  update = pkgs.writeShellScriptBin "update" ''
    cd ~/PersonalMonorepo
    git pull -q
    darwin-rebuild switch --flake ~/PersonalMonorepo/nix/mac-setup
'';

  nix-commit = pkgs.writeShellScriptBin "nix-commit" ''
  cd ~/PersonalMonorepo
  git add nix/*
  git commit -m "Nix commit"
'';

  argocd-commit = pkgs.writeShellScriptBin "argocd-commit" ''
  cd ~/PersonalMonorepo
  git add kubernetes/argocd/*
  git commit -m "Argocd commit"
  git push
'';

  update-kubeconfig = pkgs.writeShellScriptBin "update-kubeconfig" ''
  cd ~/PersonalMonorepo/nix/mac-setup/secrets
  cat ~/.kube/config | pbcopy
  agenix -e kubeconfig.age
'';


in

{
  services.nix-daemon.enable = true;

  programs.zsh.enable = true;

  environment.systemPackages = [
    update
    nix-commit
    update-kubeconfig
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
    pkgs.yarn
    pkgs.postgresql
    pkgs.check-jsonschema
    pkgs.jq
    pkgs.yq
    pkgs.terragrunt
    pkgs.defaultbrowser
    pkgs.rustc
    pkgs.cargo
    inputs.agenix.packages.${pkgs.system}.agenix
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
      expose-group-by-app = true;
      show-recents = false;
    };

    NSGlobalDomain = {
      "com.apple.swipescrolldirection" = false;
    };

    screencapture = {
      location = "/Users/aidan/Desktop/screenshots";
      show-thumbnail = false;
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
