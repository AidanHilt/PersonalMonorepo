{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../roles/nixos/server/adguard.nix
    ../roles/nixos/server/keepalived.nix
    ../roles/nixos/server/rke.nix
    ../roles/nixos/server/gitops-updater.nix

    ../roles/nixos/fixed-ip-machine.nix
  ];

  services.openssh = {
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    htop
  ];

  users.groups.sensitive-file-readers = {
    members = ["${machine-config.username}"];
  };

}