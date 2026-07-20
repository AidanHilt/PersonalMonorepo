{ libFunctions, lib, ... }:

let
  standalone = false;

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};

  secretSet = libFunctions.loadMergedValues "istio-ingress-config";

  vaultSecrets = libFunctions.mkVaultSecrets secretSet;
in

lib.mkMerge [
  vaultProvider
  kubernetesProvider
  vaultSecrets
]

