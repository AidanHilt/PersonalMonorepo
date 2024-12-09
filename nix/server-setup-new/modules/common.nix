{ inputs, globals, pkgs, ...}:

let
  upload-host-key = pkgs.writeShellScriptBin "upload-host-key" ''
    curl -F "file=@/etc/ssh/ssh_host_ed25519_key.pub https://x0.at"
  '';
in

{
  users.groups.aidan = {};

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.aidan = {
    home = "/home/aidan";
    group = "aidan";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"];
  };

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
   # upload-host-key
  ];

  system.stateVersion = "24.11";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
}