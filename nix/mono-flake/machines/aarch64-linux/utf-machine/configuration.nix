{ config, pkgs, machine-config, inputs, globals, ... }:


{
  imports = [
    ../../../modules/machine-categories/linux-desktop-terminal.nix
  ];

  # home-manager = {
  #   useGlobalPkgs = true;
  #   useUserPackages = true;
  #   backupFileExtension = "bak";
  #   extraSpecialArgs = { inherit inputs globals pkgs; };
  #   users.${machine-config.username} = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = home-manager.lib; };
  # };

  fileSystems = {
  "/" = {
    device = "/dev/disk/by-label/ROOTDIR";
    fsType = "ext4";
  };
  "/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };
};

}