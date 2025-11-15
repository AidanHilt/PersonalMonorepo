{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./system-tasks-darwin-docker-networking.nix
    ./system-tasks-generate-hashed-password.nix
  ];
}
