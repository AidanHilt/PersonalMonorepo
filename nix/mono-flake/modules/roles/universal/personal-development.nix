{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  # imports = [
  #   ../../scripts/app-creator/default.nix
  #   ../../scripts/argocd/default.nix
  #   ../../scripts/context/default.nix
  #   ../../scripts/custom-images/default.nix
  #   ../../scripts/helm/default.nix
  #   ../../scripts/keepass/default.nix
  #   ../../scripts/kubernetes/default.nix
  #   ../../scripts/mono-flake/default.nix
  #   ../../scripts/nixos/default.nix
  #   ../../scripts/system-tasks/default.nix
  #   ../../scripts/vault/default.nix
  #   ../../scripts/terragrunt/default.nix
  # ];

  environment.interactiveShellInit = inputs.scripts.interactiveShellInit;

  environment.systemPackages = with pkgs; [
    inputs.scripts.packages.${pkgs.system}.all
    act
    agenix
    cocogitto
    nss
    syncthing
    vault
    weechat
  ];
}