{ lib, modulesPath, ... }:

{
  # imports =
  #   [ (modulesPath + "/profiles/qemu-guest.nix")
  #   ];

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "virtio_pci"
      "usbhid"
      "usb_storage"
      "sr_mod"
    ];
    initrd.kernelModules = [ ];
    kernelModules = [ ];
    extraModulePackages = [ ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
