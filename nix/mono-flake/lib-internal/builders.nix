{
  nixpkgs,
  darwin,
  inputs,
}:

let
  inherit (nixpkgs) lib;

  values = import ./values.nix { inherit nixpkgs darwin inputs; };

  # Create a system configuration
  mkSystem =
    {
      name,
      system,
      pkgsFor,
      extraPkgsFor ? { },
      machinesDir,
      inputs,
      globals ? { },
    }:
    let
      systemFunction =
        if system == "aarch64-darwin" then darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
      moduleType = if system == "aarch64-darwin" then "darwinModules" else "nixosModules";

      # Platform-specific modules
      platformModules =
        if moduleType == "nixosModules" then
          [
            inputs.wsl.nixosModules.wsl
            inputs.disko.nixosModules.disko
            inputs.nixos-lima.nixosModules.lima
          ]
        else
          [ ];

      machine-config = values.getMachineConfig name system;

      # Any extra package sets declared in flake.nix's extraPkgsInputs (e.g.
      # `unstable`), built for this system, renamed `pkgs-<name>` so they can
      # be threaded into both the host's specialArgs and home-manager's
      # extraSpecialArgs below.
      extraPkgs = extraPkgsFor.${system} or { };
      extraSpecialArgs = lib.mapAttrs' (
        pkgsName: pkgs: lib.nameValuePair "pkgs-${pkgsName}" pkgs
      ) extraPkgs;
    in
    {
      "${name}" = systemFunction {
        inherit system;
        specialArgs = {
          inherit machine-config inputs globals;
          # This is only used in _home-manager.nix, to allow it to correctly import the right home.nix. This means our home-manager imports are defined in one place,
          # and it's infinitely flexible. Not 100% on it being worth it, but as long as its just me using it, we should be good
          machineDir = "${system}/${name}";
        }
        // extraSpecialArgs;
        modules = [
          (machinesDir + "/${system}/${name}/configuration.nix")
          inputs.home-manager.${moduleType}.home-manager
          inputs.agenix.${moduleType}.default
          { nixpkgs.pkgs = pkgsFor.${system}; }
          inputs.comin.${moduleType}.comin
          # home-manager modules get their special args from
          # `home-manager.extraSpecialArgs`, not from the host's own
          # specialArgs above, so the pkgs-<name> extra package sets have to be
          # threaded in here too. This is a third place `extraSpecialArgs` gets
          # assembled (the other two are `_home-manager.nix` and the
          # duplicated inline home-manager blocks in the staging-cluster
          # machine configs -- see IMPLEMENTERS.md/IMPROVEMENTS.md); it's kept
          # inline and separate rather than threaded through those because all
          # three are plain attrsets that NixOS merges harmlessly by key, and
          # this is the one place a new extraPkgsInputs entry needs to be wired
          # up without touching every host's module.
          { home-manager.extraSpecialArgs = extraSpecialArgs; }
        ]
        ++ platformModules;
      };
    };

  # Build all systems for a given architecture
  mkSystemsForArch =
    {
      system,
      hosts,
      pkgsFor,
      extraPkgsFor ? { },
      machinesDir,
      inputs,
      globals ? { },
    }:
    builtins.foldl' (
      acc: name:
      acc
      // (mkSystem {
        inherit
          name
          system
          pkgsFor
          extraPkgsFor
          machinesDir
          inputs
          globals
          ;
      })
    ) { } hosts;
in

{
  inherit mkSystem mkSystemsForArch;
}
