{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../scripts/argocd/default.nix
    ../../scripts/context/default.nix
    ../../scripts/mono-flake/default.nix
    ../../scripts/nixos/default.nix
    ../../scripts/system-tasks/default.nix
    ../../scripts/vault/default.nix
    ../../scripts/terragrunt/default.nix
  ];

  environment.systemPackages = with pkgs; [
    act
    agenix
    syncthing
    vault
  ];
}