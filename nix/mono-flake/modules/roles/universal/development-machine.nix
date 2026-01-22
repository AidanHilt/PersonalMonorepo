{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  terragruntPkgs = import inputs.nixpkgs-terragrunt {system = pkgs.system;};

  terragrunt = if ! machine-config ? configSwitches.work then pkgs.terragrunt else terragruntPkgs.terragrunt;
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
  if [[  $1 != "--no-push" ]]; then
    git push
  fi
'';

  reset-docker = pkgs.writeShellScriptBin "reset-docker" ''
  docker container prune --force
  docker image prune -a --force
  docker builder prune --force
'';

  personalMonorepoLocation = "${machine-config.userBase}/${machine-config.username}/PersonalMonorepo";

in

{
  imports = [
    ./kubernetes-admin.nix
  ];

  environment.variables = {
    PERSONAL_MONOREPO_LOCATION = "${personalMonorepoLocation}";
  };

  environment.systemPackages = with pkgs; [
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
    terraform
    terragrunt
    yarn
    yq-go

    argocd-commit
    nix-commit
    reset-docker
  ] ++ platform-apps;


  #TODO If this breaks on Linux, you need to figure out what the NixOS equivalent of this is, and then implement platform-specific logic
  system.activationScripts = {
    postActivation = {
      text = ''
        if [ ! -d "${personalMonorepoLocation}" ]; then
          su aidan -c "${pkgs.git}/bin/git clone https://github.com/AidanHilt/PersonalMonorepo.git ${personalMonorepoLocation}"
        fi
      '';
    };
  };
}