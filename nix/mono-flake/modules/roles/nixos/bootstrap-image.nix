{ inputs, globals, pkgs, ...}:

{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  networking.hostName = "nixos-bootstrap";

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos"
    ];
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  security.pam.services.login.allowNullPassword = true;

  security.sudo.wheelNeedsPassword = false;

  services.getty.autologinUser = pkgs.lib.mkForce "root";
}