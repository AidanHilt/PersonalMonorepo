{ inputs, globals, pkgs, machine-config, ...}:

let
  argocd-commit = pkgs.writeShellScriptBin "argocd-commit" ''
  cd $PERSONAL_MONOREPO_LOCATION
  git add kubernetes/
  git commit -m "Argocd commit"
  git push
'';

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

  mac-apps = if pkgs.system == "aarch64-darwin" then with pkgs; [ defaultbrowser ] else [];
in

{
  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    PERSONAL_MONOREPO_LOCATION = "${machine-config.user-base}/${machine-config.username}/PersonalMonorepo";
  };

  environment.systemPackages = with pkgs; [
    act
    cargo
    check-jsonschema
    detect-secrets
    eza
    gettext
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
    yarn
    yq

    argocd-commit
    nix-commit
    reset-docker
  ] ++ mac-apps;

  system.userActivationScripts = {
    getPersonalMonorepo = {
      text = ''
        if [ ! -d "$PERSONAL_MONOREPO_LOCATION" ]; then
          git clone https://github.com/AidanHilt/PersonalMonorepo.git "$PERSONAL_MONOREPO_LOCATION"
        fi
      '';
    };
  };
}