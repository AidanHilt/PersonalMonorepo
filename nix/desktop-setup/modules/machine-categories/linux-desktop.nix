{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./linux-universal.nix

    ../roles/nixos/deepin-desktop.nix
  ];

  environment.systemPackages = with pkgs [
    firefox
  ];

  programs.nix-ld.enable = true;
}
