{ inputs, globals, pkgs, system, machine-config, ...}:

{
  imports = [
    # ../../../modules/disko-configs/vda-single-disk.nix
  ];

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
