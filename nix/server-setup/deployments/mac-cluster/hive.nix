let
  vim-config = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nixos";
    rev = "25a69ca0818b9abd82175a1f7a918225745c6898"; #pragma: allowlist secret
  } + "/nix/modules/vim.nix";

  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  };

  home-dot-nix = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nixos";
    rev = "a7ab75c98588602e37ce636a045cd8de68379cae"; #pragma: allowlist secret
  } + "/nix/home-manager/home.nix";
in
{
  meta = {
    nixpkgs = <nixpkgs>;
  };

  defaults = { pkgs, ... }: {
    # This module will be imported by all hosts
    environment.systemPackages = with pkgs; [
      vim
      git
      yq
      jq
      zsh
      pkgs.rke2
    ];

    imports = [
      vim-config
      (import "${home-manager}/nixos")
      home-dot-nix
    ];

    services.openssh.enable = true;

    users.users.aidan = {
      isNormalUser = true;
      description = "Aidan";
      extraGroups = [ "networkmanager" "wheel" ];

      openssh.authorizedKeys.keys = ["ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC1fOZ3HBZAi3l5BtE5nvccMTDvKkZLzaVoiVfU9P6QsDObcfoKgeMoQlxeJfMxluJOi4hy+FJgmB9Acly9dScMh3sgJv0TaSXiydMEmsR4giwrSfAP23tvLpKiyfTMNGptMYmrUgyvuau2nVbG39DPVdGMv6b5DUEDieu694HwtDIUF+UJsMl8zxVe0ATpzmZnCxd1WOHN0jYaIGa18pW73reIYkiGfrbsjmNSl/W3n0v3mAUhQHrPBS/Tp8zGB2LJ5rIs14hC87gaHL9XIozWpzFK2g0Lde/iaJaulvWYnvZbqxOLEHSi94YrNu8Qlj1gT/TRW9cQwzlkbZdncfCqmSY7rQ8jVTddQcypRAizkczBYeqYvQxEc21x48EVlWZokOrG3f0jZhhgo7T+TsSOaWc5UeYTMtsBCcQSyK7bvaXXLLYN0psmzvaF2w/yH4krPpKHl+3qhEw1IAW8s251gZ1Fu0MtFX+qpMzmJkJU/k2dTRjoCrqqA8MG5ZcFsBM= ahilt@hyperion.lan"];
    };

    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;
    environment.pathsToLink = [ "/share/zsh" ];

    networking.firewall = {
     # See https://docs.rke2.io/install/requirements#inbound-network-rules for details
     allowedTCPPorts = [ 53 3000 6443 6444 9345 10250 2379 2380 2381 ];
     allowedUDPPorts = [ 53 ];
     allowedTCPPortRanges = [
       {
         from = 30000;
         to = 32767;
       }
     ];
   };
  };

  mac-cluster-server-1 = { name, nodes, ... }: {
    networking.hostName = "mac-cluster-server-1";
    time.timeZone = "America/New_York";
    deployment.buildOnTarget = true;
    system.stateVersion = "24.11";
    nixpkgs.hostPlatform = "aarch64-linux";

    fileSystems."/" =  {
      device = "/dev/disk/by-uuid/4890fa5e-4588-44da-b13a-d78118797fc9";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/B40C-F74F";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    services.rke2 = {
      enable = true;
      nodeName = "mac-cluster-server-1";

      cni = "calico";
    };
  };

  mac-cluster-server-2 = { name, nodes, ... }: {
    networking.hostName = "mac-cluster-server-2";
    time.timeZone = "America/New_York";
    deployment.buildOnTarget = true;
    system.stateVersion = "24.11";
    nixpkgs.hostPlatform = "aarch64-linux";

    boot.loader.grub.device = "/dev/disk/by-uuid/6643-CB00";
    fileSystems."/" = {
      device = "/dev/disk/by-uuid/31edbc5c-8188-4257-9a03-3cba0de6d2b5";
      fsType = "ext4";
    };

    fileSystems."/boot" ={
      device = "/dev/disk/by-uuid/6643-CB00";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    services.rke2 = {
      enable = true;
      nodeName = "mac-cluster-server-2";

      tokenFile = "/var/lib/rancher/rke2/server/token";
      serverAddr = "https://192.168.86.192:9345";

      cni = "calico";
    };
  };
}