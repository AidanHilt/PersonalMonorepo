{ inputs, globals, pkgs, machine-config, lib, ...}:
let
  yaml = pkgs.formats.yaml;

  cominConfig = {
    hostname = machine-config.hostname;
    flake_subdirectory = "nix/mono-flake";
    # remotes = [
    #   {
    #     name = "origin";
    #     url = "https://github.com/AidanHilt/PersonalMonorepo";
    #     branches.main.name = "${globals.personalMonorepoBranch}";
    #   }
    # ];
  };

  cominConfigYaml = yaml.generate "comin.yaml" cominConfig;

  branchUpdateScript = pkgs.writeShellScriptBin "gitops-branch-update" ''
    if [ -z "$1" ]; then
      echo "Usage: gitops-branch-update <branch-name>"
      exit 1
    fi

    BRANCH="$1"
    CONFIG_FILE="/etc/comin/active-config.yaml"

    # Use yq to update the branch
    ${pkgs.yq-go}/bin/yq eval ".remotes[0].branches.main = \"$BRANCH\"" -i "$CONFIG_FILE"

    echo "Updated comin config to use branch: $BRANCH"
    echo "Restart comin-runner service to apply: systemctl restart comin-runner"
  '';
in
{
  environment.systemPackages = with pkgs; [
    branchUpdateScript
    pkgs.comin
  ];

  # Ensure /etc/comin directory exists
  system.activationScripts.comin-config-dir = ''
    mkdir -p /etc/comin
  '';

  # Service to reset config to template every 4 hours
  systemd.services.comin-config-reset = {
    description = "Reset Comin config to template";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/cp ${cominConfig} /etc/comin/active-config.yaml";
    };
  };

  # Timer to run the reset service every 4 hours
  systemd.timers.comin-config-reset = {
    description = "Reset Comin config every 4 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "4h";
      Persistent = true;
    };
  };

  # Service that runs comin with the active config
  systemd.services.comin-runner = {
    description = "Comin GitOps Runner";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "comin-config-reset.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.comin}/bin/comin --config /etc/comin/active-config.yaml";
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };
}