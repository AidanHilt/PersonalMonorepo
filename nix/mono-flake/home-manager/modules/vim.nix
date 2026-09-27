{ inputs, globals, pkgs, ...}:

{
  programs.vim = {
    enable = true;
    defaultEditor = true;

    extraConfig = ''
      set backspace=indent,eol,start
    '';

    settings = {
      expandtab = true;
      tabstop = 2;
      shiftwidth = 2;

      number = true;

      smartcase = true;
    };
  };
}