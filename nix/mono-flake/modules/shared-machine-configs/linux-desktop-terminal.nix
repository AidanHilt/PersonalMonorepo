{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../roles/nixos/linux-universal.nix
    ../roles/nixos/rclone.nix

    ../roles/universal/development-machine.nix
    ../roles/universal/personal-development.nix
  ];

  programs.nix-ld.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
