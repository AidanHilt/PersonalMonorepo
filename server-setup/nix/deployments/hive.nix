{
  meta = {
    # Override to pin the Nixpkgs version (recommended). This option
    # accepts one of the following:
    # - A path to a Nixpkgs checkout
    # - The Nixpkgs lambda (e.g., import <nixpkgs>)
    # - An initialized Nixpkgs attribute set
    nixpkgs = <nixpkgs>;
  };

  defaults = { pkgs, ... }: {
    # This module will be imported by all hosts
    environment.systemPackages = with pkgs; [
      vim wget curl
    ];
  };

  test = { name, nodes, ... }: {
    # The name and nodes parameters are supported in Colmena,
    # allowing you to reference configurations in other nodes.
    #time.timeZone = "America/New_York";
    deployment.targetHost = "";

    # boot.loader.grub.device = "/dev/sda";
    # fileSystems."/" = {
    #   device = "/dev/sda1";
    #   fsType = "ext4";
    # };
  };
}