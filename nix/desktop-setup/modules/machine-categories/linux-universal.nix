{ inputs, globals, pkgs, machine-config, ...}:
{
  imports = [
    ./universal.nix

    ../roles/universal/hosts.nix
    ../roles/universal/locale-and-time.nix
  ];

  users.groups."${machine-config.username}" = {};

  users.users."${machine-config.username}" = {
    home = "/home/${machine-config.username}";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  services.openssh.enable = true;
}