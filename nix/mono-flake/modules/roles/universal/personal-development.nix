{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../scripts/app-creator/default.nix
    ../../scripts/argocd/default.nix
    ../../scripts/context/default.nix
    ../../scripts/helm/default.nix
    ../../scripts/kubernetes/default.nix
    ../../scripts/mono-flake/default.nix
    ../../scripts/nixos/default.nix
    ../../scripts/system-tasks/default.nix
    ../../scripts/vault/default.nix
    ../../scripts/terragrunt/default.nix
  ];

  environment.systemPackages = with pkgs; [
    act
    agenix
    hcl2json
    hcledit
    syncthing
    vault
  ];
}