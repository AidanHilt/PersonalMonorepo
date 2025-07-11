{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./server/_adguard.nix
    ./server/_keepalived.nix
    ./server/_rke.nix

    ./_fixed-ip-machine.nix
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