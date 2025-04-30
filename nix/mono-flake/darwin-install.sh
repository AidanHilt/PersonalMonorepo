set -e

# Install Nix
if [ ! -d /nix ]; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
fi

if [ ! -d /opt/homebrew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

repo_owner="AidanHilt"
repo_name="PersonalMonorepo"
path="nix/mono-flake/machines/aarch64-darwin"  # Optional path within the repository
branch="${1:-master}"  # Default branch is main

# Temporary file for response
temp_file=$(/usr/bin/mktemp)

# Use GitHub API to get contents
/usr/bin/curl -s "https://api.github.com/repos/$repo_owner/$repo_name/contents/$path?ref=$branch" > "$temp_file"

# Check if the request was successful
if [ $? -ne 0 ]; then
  echo "Error fetching repository contents" >&2
  rm -f "$temp_file"
  return 1
fi

hostnames=()

# Parse JSON response to extract directories
# Using grep and cut for basic parsing (more robust would be jq if available)
while read -r line; do
  # Extract type and name
  type=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
  name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

  # Add to array if it's a directory
  if [ "$type" = "dir" ]; then
      hostnames+=("$name")
  fi
done < <(grep -o '"type":"[^"]*","name":"[^"]*"' "$temp_file")

# Clean up
rm -f "$temp_file"

# Get user selection with input validation
while true; do
  echo -n "\nSelect hostname (1-${#hostnames[@]}): "
  read selection
  index=$((selection-1))

  # Check if input is a number and within valid range
  if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#hostnames[@]} ]; then
    selected_hostname=${hostnames[@]:0:1}
    echo "\nYou selected: $selected_hostname"
    break
  else
    echo "Invalid selection. Please enter a number between 1 and ${#hostnames[@]}"
  fi
done

sudo mv /etc/auto_master /etc/auto_master.before-nix-darwin
mkdir ~/Library/Application\ Support/Firefox
touch ~/Library/Application\ Support/Firefox/profiles.ini


echo "darwin-rebuild switch --flake 'github:AidanHilt/PersonalMonorepo/staging-cluster-k8s-work?dir=nix/mono-flake#$selected_hostname" | pbcopy

echo "This script has finished running. Please open a new terminal, and then CMD+V to run the nix command that will run the initial nix setup"
echo "Once the nix installation has been completed, you can open a new terminal and run 'finish-setup' to finalize the setup"