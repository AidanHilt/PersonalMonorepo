{ inputs, globals, pkgs, machine-config, lib, config, ...}:

{
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