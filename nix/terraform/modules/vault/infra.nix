{ libFunctions, lib, ... }:

let
  standalone = true;

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};
  kubernetesProvider = import ../../lib/kubernetes-provider.nix {inherit lib;};

  secretSet = libFunctions.loadMergedValues "vault-config";

  vaultSecrets = libFunctions.mkVaultSecrets secretSet;
in

lib.mkMerge [
  vaultProvider
  kubernetesProvider
  vaultSecrets
]

