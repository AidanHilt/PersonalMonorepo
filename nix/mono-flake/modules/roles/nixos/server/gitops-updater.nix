{ inputs, globals, pkgs, machine-config, lib, ... }:

with lib;

let
  repoPath = "/etc/system-gitops/PersonalMonorepo";
  repoUrl = "https://github.com/AidanHilt/PersonalMonorepo";

  # Script to ensure repo is in correct state (master branch, owned by root)
  ensureRepoScript = pkgs.writeShellScript "ensure-repo-state" ''
    set -e
    REPO_PATH="${repoPath}"
    REPO_URL="${repoUrl}"

    # Check if repo exists
    if [ ! -d "$REPO_PATH" ]; then
      echo "Repository does not exist, cloning..."
      mkdir -p "$(dirname "$REPO_PATH")"
      ${pkgs.git}/bin/git clone "$REPO_URL" "$REPO_PATH"
    fi

    # Ensure ownership is root:root
    OWNER=$(stat -c '%U' "$REPO_PATH")
    if [ "$OWNER" != "root" ]; then
      echo "Fixing ownership to root..."
      chown -R root:root "$REPO_PATH"
    fi

    # Check current branch
    cd "$REPO_PATH"
    CURRENT_BRANCH=$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)

    if [ "$CURRENT_BRANCH" != "master" ]; then
      echo "Not on master branch, switching..."
      ${pkgs.git}/bin/git fetch origin
      ${pkgs.git}/bin/git checkout master
      ${pkgs.git}/bin/git reset --hard origin/master
    else
      echo "Already on master branch, pulling latest..."
      ${pkgs.git}/bin/git pull origin master
    fi

    echo "Repository state verified and corrected"
  '';

  # Script to pull changes if on non-master branch
  pullNonMasterScript = pkgs.writeShellScript "pull-non-master" ''
    REPO_PATH="${repoPath}"

    # Exit if repo doesn't exist
    if [ ! -d "$REPO_PATH" ]; then
      exit 0
    fi

    cd "$REPO_PATH"

    # Check current branch
    CURRENT_BRANCH=$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)

    if [ "$CURRENT_BRANCH" != "master" ]; then
      echo "On branch $CURRENT_BRANCH, pulling latest changes..."
      ${pkgs.git}/bin/git pull origin "$CURRENT_BRANCH" || echo "Pull failed, continuing..."
    fi
  '';

  switchBranchScript = pkgs.writeShellScriptBin "gitops-switch-branch" ''
    #!/usr/bin/env bash
    set -e

    REPO_PATH="${repoPath}"

    # Function to display usage
    usage() {
      echo "Usage: gitops-switch-branch <branch-name>"
      echo ""
      echo "Examples:"
      echo "  gitops-switch-branch feature-branch"
      echo "  gitops-switch-branch master"
      exit 1
    }

    # Check if branch name is provided
    if [ -z "$1" ]; then
      echo "Error: Branch name required"
      usage
    fi

    BRANCH="$1"

    # Re-execute with sudo if not running as root
    if [ "$(id -u)" -ne 0 ]; then
      echo "Escalating to sudo..."
      exec sudo "$0" "$@"
    fi

    # Check if repo exists
    if [ ! -d "$REPO_PATH" ]; then
      echo "Error: Repository does not exist at $REPO_PATH"
      echo "Run 'sudo systemctl start gitops-repo-ensure.service' to initialize"
      exit 1
    fi

    cd "$REPO_PATH"

    echo "Fetching latest changes from all remotes..."
    ${pkgs.git}/bin/git fetch --all

    # Check if branch exists remotely
    if ! ${pkgs.git}/bin/git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
      echo "Error: Branch '$BRANCH' does not exist on remote 'origin'"
      echo ""
      echo "Available remote branches:"
      ${pkgs.git}/bin/git branch -r | grep "origin/" | sed 's/origin\//  /'
      exit 1
    fi

    # Get current branch
    CURRENT_BRANCH=$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)

    if [ "$CURRENT_BRANCH" = "$BRANCH" ]; then
      echo "Already on branch '$BRANCH', pulling latest changes..."
      ${pkgs.git}/bin/git pull origin "$BRANCH"
    else
      echo "Switching from '$CURRENT_BRANCH' to '$BRANCH'..."

      # Check for uncommitted changes
      if ! ${pkgs.git}/bin/git diff-index --quiet HEAD --; then
        echo "Warning: You have uncommitted changes. Stashing them..."
        ${pkgs.git}/bin/git stash
      fi

      # Switch to branch
      ${pkgs.git}/bin/git checkout "$BRANCH"
      ${pkgs.git}/bin/git reset --hard "origin/$BRANCH"
    fi

    echo ""
    echo "✓ Successfully switched to branch: $BRANCH"
    echo "✓ Repository is now at: $(${pkgs.git}/bin/git rev-parse --short HEAD)"
    echo ""
    echo "The gitops-repo-pull-nonmaster timer will now pull updates every 10 seconds."
    echo "To switch back to master, run: gitops-switch-branch master"
  '';
in

{
  environment.systemPackages = [ switchBranchScript pkgs.neo-cowsay ];

  services.comin = {
    enable = true;
    hostname = machine-config.hostname;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      {
        name = "local";
        url = "file://${repoPath}";
        branches.main.name = "HEAD";
        poller.period = 5;
      }
      # {
      #   name = "origin";
      #   url = "https://github.com/AidanHilt/PersonalMonorepo";
      #   branches.main.name = "master";
      # }
    ];
  };

  # Service to ensure repo is in correct state
  systemd.services.gitops-repo-ensure = {
    description = "Ensure GitOps repository is in correct state";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ensureRepoScript}";
      User = "root";
    };
  };

  # Timer to run daily at 12:30 AM
  systemd.timers.gitops-repo-ensure = {
    description = "Daily check of GitOps repository state";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "00:30";
      Persistent = true;
    };
  };

  # Service to pull non-master branches
  systemd.services.gitops-repo-pull-nonmaster = {
    description = "Pull changes for non-master branches";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pullNonMasterScript}";
      User = "root";
    };
  };

  # Timer to run every 10 seconds
  systemd.timers.gitops-repo-pull-nonmaster = {
    description = "Pull non-master branch changes every 10 seconds";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "10s";
    };
  };

  # Ensure the parent directory exists
  system.activationScripts.gitops-repo-dir = ''
    mkdir -p $(dirname "${repoPath}")
  '';
}