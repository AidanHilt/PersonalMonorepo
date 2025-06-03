{ inputs, globals, pkgs, ...}:

let
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  networking.hostName = nixos-bootstrap;

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
  ];
  documentation.enable = false;
  documentation.nixos.enable = false;

  boot.kernelParams = [ "boot.shell_on_fail" ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };

  users.users.root = {
    password = "";
  };

  security.pam.services.login.allowNullPassword = true;
  security.pam.services.sshd.allowNullPassword = true;

  security.sudo.wheelNeedsPassword = false;

  services.getty.autologinUser = "root";
}