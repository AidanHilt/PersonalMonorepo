{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [
    ./_adguard.nix
    ./_fixed-ip-machine.nix
    ./_keepalived.nix
    ./_rke.nix
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