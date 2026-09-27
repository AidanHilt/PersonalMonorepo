{ inputs, globals, pkgs, system, machine-config, ...}:

{
  imports = [$DISKO_COMMON_CONFIG_OPTIONS];

  # disko.devices = {
  #   disk = {
  #     main = {
  #       device = "";
  #       type = "disk";
  #       content = {
  #         type = "";
  #         partitions = {
  #           ESP = {
  #             size = "";
  #             type = "";
  #             content = {
  #               type = "filesystem";
  #               format = "";
  #               mountpoint = "";
  #               mountOptions = [ "umask=0077" ];
  #             };
  #           };
  #         };
  #       };
  #     };
  #   };
  # };
}