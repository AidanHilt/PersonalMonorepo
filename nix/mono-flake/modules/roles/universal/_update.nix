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

    # 3. If we're doing a remote (i.e. GitHub) update, we need to build out the full reference (URL + branch)
    if [ ! -z "$UPDATE__FROM_REMOTE" ]; then
      if [[ $\{UPDATE__REMOTE_URL: -1 \} != "/" ]]; then
        UPDATE__REMOTE_URL="$UPDATE__REMOTE_URL/"
      fi

      if [ -z "$UPDATE__REMOTE_BRANCH" ]; then 
        UPDATE__REMOTE_BRANCH="master"
      fi

      UPDATE__FLAKE_LOCATION="$UPDATE__REMOTE_URL$UPDATE__REMOTE_BRANCH"
    fi

    # 3. Run the rebuild command with sudo
    if [ -z "$UPDATE__FLAKE_LOCATION" ] || [ -z "$UPDATE__MACHINE_NAME" ]; then
        echo "Error: UPDATE__FLAKE_LOCATION or UPDATE__MACHINE_NAME not set in config file"
        exit 1
    fi

    echo "Rebuilding system with flake: $UPDATE__FLAKE_LOCATION#$UPDATE__MACHINE_NAME"
    sudo $rebuildExecutable switch --flake "$UPDATE__FLAKE_LOCATION#$UPDATE__MACHINE_NAME"
  '';
in

{

  environment.systemPackages = [
    update-script
  ];

}