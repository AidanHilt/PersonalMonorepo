{ inputs, globals, pkgs, machine-config, ...}:

{
  programs.keepassxc = {
    settings = {
      Browser.Enabled = true
    };
  };

}