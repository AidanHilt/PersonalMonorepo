{ inputs, globals, pkgs, machine-config, ...}:

let
  # Platform-specific logic or setup
  platform-apps = if pkgs.system == "aarch64-darwin" then with pkgs; [] else with pkgs; [];

  rebuild-app = if pkgs.system == "aarch64-darwin" then "darwin-rebuild" else "nixos-rebuild";

  # Shortcut scripts
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

#   update = pkgs.writeShellScriptBin "update" ''
#   cd $PERSONAL_MONOREPO_LOCATION
#   git pull -q
#   ${rebuild-app} switch --flake $PERSONAL_MONOREPO_LOCATION/nix/mono-flake
# '';
in

{
  imports = [
    ./_kubernetes-admin.nix
  ];

  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    PERSONAL_MONOREPO_LOCATION = "${machine-config.user-base}/${machine-config.username}/PersonalMonorepo";
  };

  environment.systemPackages = with pkgs; [
    act
    agenix
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
   # update
  ] ++ platform-apps;

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