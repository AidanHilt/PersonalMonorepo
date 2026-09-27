{ libFunctions, lib, ... }:

let
  standalone = false;

  vaultProvider = import ../../lib/vault-provider.nix {inherit lib; inherit standalone;};

  hostSet = libFunctions.loadMergedValues "istio-ingress-config";

  vaultPki = libFunctions.mkPkiStackForEnv hostSet;
in

lib.mkMerge [
  vaultProvider
  vaultPki
]

