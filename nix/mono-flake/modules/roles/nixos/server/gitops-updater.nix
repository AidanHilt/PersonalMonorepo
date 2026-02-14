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
in

{
  services.comin = {
    enable = true;
    repositorySubdir = "nix/mono-flake";
    remotes = [
      {
        name = "origin";
        url = "https://github.com/AidanHilt/PersonalMonorepo";
        branches.main.name = "${globals.personalMonorepoBranch}";
      }
      {
        name = "local";
        url = "file:///tmp/PersonalMonorepo";
        branches.main.name = "HEAD";
        poller.period = 5;
      }
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