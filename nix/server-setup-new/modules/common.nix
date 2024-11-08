{ inputs, globals, nixpkgs, ...}:

{
  users.groups.aidan = {};

  users.users.aidan = {
    home = "/Users/aidan";
    group = "aidan";
    isNormalUser = true;

    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"];

    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;
    environment.pathsToLink = [ "/share/zsh" ];
  };

  services.openssh.enable = true;
}