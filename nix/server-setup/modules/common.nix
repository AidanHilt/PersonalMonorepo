{ inputs, globals, pkgs, ...}:

{
  users.groups.aidan = {};

  users.users.aidan = {
    home = "/home/aidan";
    group = "aidan";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos"
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
  ];

  system.stateVersion = "24.11";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
}