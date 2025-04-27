{ inputs, globals, pkgs, machine-config, ...}:

let
  update-script = pkgs.writeShellScriptBin "update" ''
  #!/bin/bash
  # Helper functions
  prompt_with_default() {
    local arg_name="$1"
    local default_value="$2"
    
    # Prompt user with the argument name and default value
    echo -n "$arg_name [$default_value]: "
    
    # Read user input
    local user_input
    read user_input
    
    # If user input is empty, use the default value
    if [ -z "$user_input" ]; then
        echo "$default_value"
    else
        echo "$user_input"
    fi
  }


  # Main script

  # 1. Source the environment file if it exists
  if [ -f ~/.atils/update-config.env ]; then
    source ~/.atils/update-config.env
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
    echo -n "The location of the flake you want to use [github:AidanHilt/PersonalMonorepo/master?dir=nix/mono-flake]: "
    
    read user_input

    if [ -z "$user_input" ]; then
        UPDATE__FLAKE_LOCATION="$user_input"
    else
        UPDATE__FLAKE_LOCATION="github:AidanHilt/PersonalMonorepo/master?dir=nix/mono-flake"
    fi
  fi
  
  if [ -z "$UPDATE__MACHINE_NAME" ]; then
    default_machine_name=$(hostname)
    UPDATE__MACHINE_NAME=$(prompt_with_default "The name of the machine to use for the update" "$default_machine_name")
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