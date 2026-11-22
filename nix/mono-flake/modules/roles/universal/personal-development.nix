{
  inputs,
  globals,
  pkgs,
  machine-config,
  lib,
  config,
  ...
}:

let
  platformPackages = if pkgs.stdenv.hostPlatform.isDarwin then [] else [ pkgs.ghostty.terminfo ];
in

{
  environment.interactiveShellInit = inputs.scripts.interactiveShellInit;

  environment.systemPackages = with pkgs; [
    inputs.scripts.packages.${pkgs.system}.all

    act
    agenix
    cocogitto
    coreutils
    dotenvx
    go
    kubebuilder
    nodejs_24
    nss
    openbao
    python3
    syncthing
    vault
    watchexec
    weechat
  ] ++ platformPackages;

  age.secrets.github-token = {
    file = ../../../secrets/github-config.age;
    path = "/run/agenix/github-token";
    owner = "root";
    mode = "0400";
  };

  nix.extraOptions = ''
    !include ${config.age.secrets.github-token.path}
  '';
}
