{ nixpkgs, darwin, inputs }:

let
  values = import ./values.nix { inherit nixpkgs darwin inputs; };

  # Create a system configuration
  mkSystem = { name, system, pkgsFor, machinesDir, inputs, globals ? {} }:
    let
      systemFunction = if system == "aarch64-darwin" then darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
      moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";
      user-base = if system == "aarch64-darwin" then "/Users" else "/home";

      # Platform-specific modules
      platformModules = if moduleType == "nixosModules" then [
        inputs.wsl.nixosModules.wsl
        inputs.disko.nixosModules.disko
      ] else [];

      # Load machine-specific values
      # machineValuesPath = machinesDir + "/${system}/${name}/values.nix";
      # machineValues = if builtins.pathExists machineValuesPath
      #   then import machineValuesPath { pkgs = pkgsFor.${system}; }
      #   else {};

      # machine-config = machineValues // {
      #   inherit user-base;
      #   hostname = name;
      # };

      machine-config = values.getMachineConfig name system;
    in
    {
      "${name}" = systemFunction {
        inherit system;
        specialArgs = {
          inherit machine-config inputs globals;
          pkgs = pkgsFor.${system};
        };
        modules = [
          (machinesDir + "/${system}/${name}/configuration.nix")
          inputs.home-manager.${moduleType}.home-manager
          inputs.agenix.${moduleType}.default
        ] ++ platformModules;
      };
    };

  # Build all systems for a given architecture
  mkSystemsForArch = { system, hosts, pkgsFor, machinesDir, inputs, globals ? {} }:
    builtins.foldl' (acc: name:
      acc // (mkSystem {
        inherit name system pkgsFor machinesDir inputs globals;
      })
    ) {} hosts;
in

{
  mkSystem = mkSystem;
  mkSystemsForArch = mkSystemsForArch;
}