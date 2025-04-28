{ inputs, globals, pkgs, machine-config, ...}:

let
  update-script = pkgs.writeShellScriptBin "update" ''
  #!/bin/bash
  # Helper functions
  update_config() {
      local key="$1"
      local value="$2"
      local config_file="$HOME/.atils/update-config.env"
      
      # Create directory if it doesn't exist
      mkdir -p "$(dirname "$config_file")"
      
      # Check if file exists
      if [ ! -f "$config_file" ]; then
          # Create new file with the key-value pair
          echo "$key=$value" > "$config_file"
          echo "Created new config file with $key=$value"
          return 0
      fi
      
      # Check if key already exists in the file
      if grep -q "^$key=" "$config_file"; then
          # Update existing key
          sed -i.bak "s|^$key=.*|$key=$value|" "$config_file" && rm -f "''${config_file}.bak"
          echo "Updated $key=$value in config file"
      else
          # Append new key-value pair
          echo "$key=$value" >> "$config_file"
          echo "Added $key=$value to config file"
      fi
  }

  # Main script

  # 1. Source the environment file if it exists
  if [ -f ~/.atils/update-config.env ]; then
    source ~/.atils/update-config.env
  else
    echo "~/.atils/update-config.env not found. The file will be created and used to save your choices on this run"
    echo "If you want to be prompted for choices every time, abort and run 'echo UPDATE__NO_SAVE="true" > ~/.atils/update-config.env'"
  fi

  # 2. Determine the rebuild executable based on the OS
  if [[ "$(uname)" == "Darwin" ]]; then
    rebuildExecutable="darwin-rebuild"
  else
    rebuildExecutable="nixos-rebuild"
  fi

  # Ideally, we could do this with a function, but subshells suck.
  # 3. Run the rebuild command with sudo
  if [ -z "$UPDATE__FLAKE_LOCATION" && -z "$UPDATE__REMOTE_URL" ]; then
    echo -n "Do you want to update from a remote or local source? (remote/local): "
    read source_type
    source_type="''${source_type:-remote}"  # Default to remote if empty
    
    if [[ "$source_type" == "remote" ]]; then
        # For remote source, get repository and branch
        echo -n "Remote repository (default: github:AidanHilt/PersonalMonorepo): "
        read remote_repo
        UPDATE__REMOTE_URL="''${remote_repo:-github:AidanHilt/PersonalMonorepo}"
        
        echo -n "Branch to use (default: master): "
        read branch_name
        UPDATE__REMOTE_BRANCH="''${branch_name:-master}"
        
    elif [[ "$source_type" == "local" ]]; then
        # For local source, check if PERSONAL_MONOREPO_LOCATION exists
        local_default=""
        if [ -n "$PERSONAL_MONOREPO_LOCATION" ] && [ -d "$PERSONAL_MONOREPO_LOCATION" ]; then
            local_default="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake"
            echo -n "Local flake location (default: $local_default): "
        else
            echo -n "Local flake location: "
        fi
        
        read local_path
        if [ -n "$local_default" ] && [ -z "$local_path" ]; then
            UPDATE__FLAKE_LOCATION="$local_default"
        else
            UPDATE__FLAKE_LOCATION="$local_path"
        fi
        
    else
        echo "Invalid option. Defaulting to remote source."
        UPDATE__FLAKE_LOCATION="github:AidanHilt/PersonalMonorepo/master?dir=nix/mono-flake"
    fi
  fi

  # 4. If we're doing a remote (i.e. GitHub) update, we need to build out the full reference (URL + branch)
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

  echo $(env)

  echo "Rebuilding system with flake: $UPDATE__FLAKE_LOCATION#$UPDATE__MACHINE_NAME"
  sudo $rebuildExecutable switch --flake "$UPDATE__FLAKE_LOCATION#$UPDATE__MACHINE_NAME"
  '';
in

{

  environment.systemPackages = [
  update-script
  ];

}