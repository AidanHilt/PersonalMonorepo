{ inputs, globals, pkgs, machine-config, ...}:

let
  update-script = pkgs.writeShellScriptBin "update" ''
  #!/bin/bash
  # Helper functions

  # Main script

  # 1. Source the environment file if it exists
  if [ -f ~/.atils/update-config.env ]; then
    source ~/.atils/update-config.env
  else
    echo "~/.atils/update-config.env not found. Your choices will be saved in that file."
    echo "If you want to be prompted for choices every time, abort and run 'echo UPDATE__NO_SAVE="true" > ~/.atils/update-config.env'"
  fi

  # 2. Determine the rebuild executable based on the OS
  if [[ "$(uname)" == "Darwin" ]]; then
    rebuildExecutable="darwin-rebuild"
  else
    rebuildExecutable="nixos-rebuild"
  fi

  # 3. If we're doing a remote (i.e. GitHub) update, we need to build out the full reference (URL + branch)
  if [ ! -z "$UPDATE__FROM_REMOTE" ]; then
    # Because you're going to forget, the double single quote is an escape character for nix
    if [[ ''${UPDATE__REMOTE_URL: -1} != "/" ]]; then
    UPDATE__REMOTE_URL="$UPDATE__REMOTE_URL/"
    fi

    if [ -z "$UPDATE__REMOTE_BRANCH" ]; then 
    UPDATE__REMOTE_BRANCH="master"
    fi

    question_mark_pos=$(expr index "$UPDATE__REMOTE_URL" "?")

    if [ $question_mark_pos -gt 0 ]; then
      # Extract parts before and after the "?"
      before_question=''${UPDATE__REMOTE_URL:0:$question_mark_pos-1}
      after_question=''${UPDATE__REMOTE_URL:$question_mark_pos-1}
      
      # Construct new string with branch inserted before "?"
      UPDATE__FLAKE_LOCATION="''${before_question}''${UPDATE__REMOTE_BRANCH}''${after_question}"
    else
      # No "?" found, append branch to the end
      UPDATE__FLAKE_LOCATION="''${UPDATE__REMOTE_URL}/''${UPDATE__REMOTE_BRANCH}"
    fi
  fi

  # Ideally, we could do this with a function, but subshells suck.
  # 3. Run the rebuild command with sudo
  if [ -z "$UPDATE__FLAKE_LOCATION" ]; then
    echo -n "The location of the flake you want to use to update (github:AidanHilt/PersonalMonorepo/master?dir=nix/mono-flake): "
    
    read user_input

    if [ -z "$user_input" ]; then
      UPDATE__FLAKE_LOCATION="github:AidanHilt/PersonalMonorepo/master?dir=nix/mono-flake"
    else
      UPDATE__FLAKE_LOCATION="$user_input"
    fi
  fi
  
  if [ -z "$UPDATE__MACHINE_NAME" ]; then
    hostname=$(hostname)
    echo -n "The name of the machine you want to use to update ($hostname): "
    
    read user_input

    if [ -z "$user_input" ]; then
      UPDATE__MACHINE_NAME="$hostname"
    else
      UPDATE__MACHINE_NAME="$user_input"
    fi
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