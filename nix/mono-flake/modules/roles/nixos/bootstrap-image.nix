{ inputs, globals, pkgs, ...}:

let
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
  documentation.enable = false;
  documentation.nixos.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };

  users.users.root = {
    password = "";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos"
    ];
  };

  security.pam.services.login.allowNullPassword = true;

  security.sudo.wheelNeedsPassword = false;

  services.getty.autologinUser = "root";
}