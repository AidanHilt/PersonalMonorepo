{ inputs, globals, pkgs, ...}:

{
  users.groups.nixos = {};

  users.users.nixos = {
    home = "/home/nixos";
    group = "nixos";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"];
  };

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    inputs.agenix.packages.${pkgs.system}.agenix
  ];

  system.stateVersion = "24.11";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
 # environment.pathsToLink = [ "/share/zsh" ];

  services.openssh.enable = true;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}