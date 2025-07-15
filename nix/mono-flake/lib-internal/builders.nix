{ nixpkgs, darwin, inputs }:

let
  values = import ./values.nix { inherit nixpkgs darwin inputs; };

  # Create a system configuration
  mkSystem = { name, system, pkgsFor, machinesDir, inputs, globals ? {} }:
    let
      systemFunction = if system == "aarch64-darwin" then darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
      moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";

      # Platform-specific modules
      platformModules = if moduleType == "nixosModules" then [
        inputs.wsl.nixosModules.wsl
        inputs.disko.nixosModules.disko
      ] else [];

      machine-config = values.getMachineConfig name system;
    in
    {
      "${name}" = systemFunction {
        inherit system;
        specialArgs = {
          inherit machine-config inputs globals;
          # This is only used in _home-manager.nix, to allow it to correctly import the right home.nix. This means our home-manager imports are defined in one place, 
          # and it's infinitely flexible. Not 100% on it being worth it, but as long as its just me using it, we should be good
          machineDir = machinesDir + "/${system}/${name}/"
        };
        modules = [
          (machinesDir + "/${system}/${name}/configuration.nix")
          inputs.home-manager.${moduleType}.home-manager
          inputs.agenix.${moduleType}.default
          {nixpkgs.pkgs = pkgsFor.${system};}
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