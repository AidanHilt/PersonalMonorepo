{ inputs, globals, pkgs, machine-config, ...}:

let
  nix-commit = pkgs.writeShellScriptBin "nix-commit" ''
  cd $PERSONAL_MONOREPO_LOCATION
  git add nix/*
  git commit -m "Nix commit"
  git push
'';

  reset-docker = pkgs.writeShellScriptBin "reset-docker" ''
  docker container prune --force
  docker image prune -a --force
  docker builder prune --force
'';

  mac-apps = if pkgs.system == "aarch64-darwin" then [ defaultbrowser ] else [];
in

{
  environment.systemPackages = with pkgs; [
    act
    cargo
    check-jsonschema
    detect-secrets
    eza
    gettext
    git
    inetutils
    jq
    p7zip
    pipx
    postgresql
    pre-commit
    rustc
    syncthing
    terraform
    terragrunt
    vim
    wget
    yarn
    yq
  ] ++ mac-apps;
}