{ inputs, pkgs, globals, ... }:

{
  age.secrets.smb-mount-config = {
    file = globals.nixConfig + secrets/smb-mount-config.age;
    path = "/etc/smb_mount";
    symlink = false;
  };

  environment.etc = {
    auto_master = {
      text = ''
#
# Automounter master map
#
+auto_master    # Use directory service
#/net     -hosts    -nobrowse,hidefromfinder,nosuid
/home     auto_home -nobrowse,hidefromfinder
/Network/Servers  -fstab
/-      -static
/-      smb_mount
      '';
    };
  };
}