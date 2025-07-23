{ config, pkgs, machine-config, inputs, globals, ... }:

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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGiYYw10HWq2v6e3vMiZJ8ua5xDhLvR3wc5s3Nm1CTcW aidan@big-boi-desktop"
    ];
  };

  security.pam.services.login.allowNullPassword = true;

  security.sudo.wheelNeedsPassword = false;

  services.getty.autologinUser = pkgs.lib.mkForce "root";
}