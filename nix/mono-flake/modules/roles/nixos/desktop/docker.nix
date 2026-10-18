{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  environment.systemPackages = with pkgs; [
    docker
  ];

  virtualisation.docker.enable = true;

  users.users."${machine-config.username}" = {
    extraGroups = ["docker"];
  };
}