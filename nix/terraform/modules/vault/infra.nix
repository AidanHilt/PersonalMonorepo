{ libFunctions, lib, ... }:

let
  standalone = true;

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};
  kubernetesProvider = import ../../lib/kubernetes-provider.nix {inherit lib;};

  secretsSet = lib.importJSON ./secrets.json;

  vaultSecrets = libFunctions.mkVaultSecrets secretsSet;
in

lib.mkMerge [
  vaultProvider
  kubernetesProvider
  vaultSecrets
]

