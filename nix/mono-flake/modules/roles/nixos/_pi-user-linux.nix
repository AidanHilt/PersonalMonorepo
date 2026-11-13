# NixOS-only half of the `pi` user (see
# ../universal/_pi-user.nix for the platform-agnostic part, and why the
# split exists). Imported only by ./linux-universal.nix.
{ machine-config, ... }:

{
  users.users.pi = {
    group = "pi";
    isSystemUser = true;
  };

  # /var/lib/pi: pi's home directory and all per-run sandbox state.
  systemd.tmpfiles.rules = [
    "d /var/lib/pi 0750 pi pi - -"
  ];

  # Let machine-config.username launch the agent as `pi` without a
  # password, and without sudo stripping the PI_SANDBOX__SECRET__* env
  # vars the launcher passes through: the SETENV tag permits env vars
  # supplied on the sudo command line (or via `sudo -E`) through this
  # rule regardless of the usual `env_reset`/`env_keep` sudoers
  # defaults. No polkit path is added alongside this -- see
  # nix/agentic-ai-stack-nono/PLAN.md.
  security.sudo.extraRules = [
    {
      users = [ machine-config.username ];
      runAs = "pi";
      commands = [
        {
          command = "ALL";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];
}
