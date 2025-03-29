{ inputs, globals, pkgs, machine-config, ...}:

let
  update = pkgs.writeShellScriptBin "update" ''
    cd $PERSONAL_MONOREPO_LOCATION
    git pull -q
    sudo nixos-rebuild switch --flake $PERSONAL_MONOREPO_LOCATION/nix/wsl-setup
'';

  nix-commit = pkgs.writeShellScriptBin "nix-commit" ''
  cd $PERSONAL_MONOREPO_LOCATION
  git add nix/*
  git commit -m "Nix commit"
'';

  argocd-commit = pkgs.writeShellScriptBin "argocd-commit" ''
  cd $PERSONAL_MONOREPO_LOCATION
  git add kubernetes/
  git commit -m "Argocd commit"
  git push
'';

in

{
  environment.variables = {
    PERSONAL_MONOREPO_LOCATION = "/home/nixos/PersonalMonorepo";
  };

  users.groups."${machine-config.username}" = {};

  users.users."${machine-config.username}" = {
    home = "/home/${machine-config.username}";
    group = "${machine-config.username}";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"];
  };

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.wget
    inputs.agenix.packages.${pkgs.system}.agenix
    pkgs.eza
    update
    argocd-commit
    nix-commit
  ];

  system.stateVersion = "24.11";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  services.openssh.enable = true;

  programs.nix-ld.enable = true;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
