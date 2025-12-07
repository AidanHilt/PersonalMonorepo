{ inputs, globals, pkgs, machine-config, lib, ...}:

let

in

{
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "smbnix";
        "netbios name" = "smbnix";
        "security" = "user";
        "hosts allow" = "192.168.0. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      # In order to enable this, must set user password w/ smbpasswd utility
      # smbpasswd -a aidan
      "storagepool" = {
        "path" = "/storagePool";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "valid users" = "aidan";
        "directory mask" = "0755";
        "force user" = "aidan";
        "force group" = "aidan";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}