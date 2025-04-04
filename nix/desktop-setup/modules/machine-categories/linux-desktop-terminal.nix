{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../roles/nixos/linux-universal.nix
  ];
}
