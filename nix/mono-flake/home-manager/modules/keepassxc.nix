{ inputs, globals, pkgs, machine-config, ...}:

{
  programs.keepassxc = {
    enable = true;
    package = null;

    settings = {
      Browser.Enabled = true;
    };
  };

}