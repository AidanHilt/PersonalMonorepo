{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  constants = import ../../roles/universal/_personal-monorepo-constants.nix {inherit machine-config;};
in

{
  imports = [
    ./job-create-job.nix
  ];

  environment.variables = constants.variables;
}