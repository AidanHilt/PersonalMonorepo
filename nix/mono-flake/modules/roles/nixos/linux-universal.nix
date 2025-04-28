{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ../universal/universal-base.nix
  ];

  users.groups."${machine-config.username}" = {};

  users.users."${machine-config.username}" = {
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.lib.mkForce pkgs.zsh;

  services.openssh.enable = true;
}