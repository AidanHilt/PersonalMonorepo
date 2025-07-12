{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./hosts.nix
    ./locale-and-time.nix

    ../universal/universal-base.nix
  ];

  users.groups."${machine-config.username}" = {};

  users.users."${machine-config.username}" = {
    group = "${machine-config.username}";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    hashedPassword = pkgs.lib.mkIf (machine-config ? hashedPassword) machine-config.hashedPassword;
  };

  system.stateVersion = "25.05";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  services.openssh.enable = true;
}