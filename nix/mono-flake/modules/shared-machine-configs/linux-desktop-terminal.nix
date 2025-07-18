{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../roles/nixos/linux-universal.nix

    ../roles/universal/development-machine.nix
  ];

  programs.firefox.enable = true;

  programs.nix-ld.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
