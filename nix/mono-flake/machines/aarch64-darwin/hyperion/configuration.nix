{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ../../../modules/roles/darwin/darwin-universal.nix
    ../../../modules/roles/darwin/personal.nix

    ../../../modules/roles/universal/development-machine.nix
    ../../../modules/roles/universal/personal-development.nix
  ];

  nix = {
    buildMachines = [{
      hostName = "big-boi-desktop.lan";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      sshUser = "aidan";
      sshKey = "/Users/aidan/.ssh/id_ed25519";
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = [ "kvm" "big-parallel" ];
      mandatoryFeatures = [ ];
    }
  ];

    distributedBuilds = true;

    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}