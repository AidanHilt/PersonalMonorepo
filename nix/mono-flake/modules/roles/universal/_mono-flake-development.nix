{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../../scripts/mono-flake-new-machine.nix
    ../../scripts/mono-flake-new-script.nix
    ../../scripts/mono-flake-copy-machine.nix
  ];
}