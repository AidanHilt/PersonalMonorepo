{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./system-tasks-add-trust-certs.nix
    ./system-tasks-darwin-docker-networking.nix
    ./system-tasks-generate-hashed-password.nix
  ];
}
