{ inputs, globals, pkgs, machine-config, ...}:

let
  update-script = pkgs.writeShellScriptBin "update" ''
    #!/bin/bash

    # 1. Source the environment file if it exists
    if [ -f ~/.atils/update-config.env ]; then
        source ~/.atils/update-config.env
    else
        echo "Warning: ~/.atils/update-config.env not found"
        exit 1
    fi

    # 2. Determine the rebuild executable based on the OS
    if [[ "$(uname)" == "Darwin" ]]; then
        rebuildExecutable="darwin-rebuild"
    else
        rebuildExecutable="nixos-rebuild"
    fi

    echo "Using rebuild executable: $rebuildExecutable"

    # 3. Run the rebuild command with sudo
    if [ -z "$UPDATE_FLAKE_LOCATION" ] || [ -z "$UPDATE_MACHINE_NAME" ]; then
        echo "Error: UPDATE_FLAKE_LOCATION or UPDATE_MACHINE_NAME not set in config file"
        exit 1
    fi

    echo "Rebuilding system with flake: $UPDATE_FLAKE_LOCATION#$UPDATE_MACHINE_NAME"
    sudo $rebuildExecutable switch --flake "$UPDATE_FLAKE_LOCATION#$UPDATE_MACHINE_NAME"
  '';
in

{

  environment.systemPackages = [
    update-script
  ];

}