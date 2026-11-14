{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hello                                                         tree
  ];

  #Programs
   programs = {
    home-manager = {
     enable = true;
    };

    neovim = {
     enable = true;
    };

    starship = {
     enable = true;
     presets = [ "gruvbox-rainbow" ];
    };

    bash = {
     enable = true;
    };

    # next program here
  };
}
