{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./mono-flake-copy-machine.nix
    ./mono-flake-new-machine.nix
    ./mono-flake-new-script.nix
    ./mono-flake-template-machine-file-options.nix
    ./mono-flake-new-module.nix
  ];
}