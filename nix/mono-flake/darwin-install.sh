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

hostnames_raw=$(/usr/bin/curl -s "https://api.github.com/repos/$repo_owner/$repo_name/contents/$path?ref=$branch" |
                /usr/bin/jq -r '.[] | select(.type=="dir") | .name')

hostnames=("${(f)$(echo "$hostnames_raw")}")

if [ ${#hostnames[@]} -eq 0 ] && [ $? -ne 0 ]; then
    echo "Error fetching repository contents" >&2
    return 1
fi

echo "Available hostnames:"
i=1
for hostname in "$hostnames[@]"; do
  echo "${i}) ${hostname}"
  i=$((i+1))
done


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

/usr/bin/sudo /bin/mv /etc/auto_master /etc/auto_master.before-nix-darwin
/usr/bin/mkdir ~/Library/Application\ Support/Firefox
/usr/bin/touch ~/Library/Application\ Support/Firefox/profiles.ini


echo "darwin-rebuild switch --flake 'github:AidanHilt/PersonalMonorepo/staging-cluster-k8s-work?dir=nix/mono-flake#$selected_hostname" | pbcopy

echo "This script has finished running. Please open a new terminal, and then CMD+V to run the nix command that will run the initial nix setup"
echo "Once the nix installation has been completed, you can open a new terminal and run 'finish-setup' to finalize the setup"