{ pkgs, ... }:
{
  environment.variables = { EDITOR = "vim"; };

  environment.systemPackages = with pkgs; [
    ((vim_configurable.override {  }).customize{
      name = "vim";
      # Install plugins for example for syntax highlighting of nix files
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [];
        opt = [];
      };
      vimrcConfig.customRC = ''
        set tabstop=2
        set shiftwidth=2
        set expandtab

        set number
      '';
    }
  )];
}
