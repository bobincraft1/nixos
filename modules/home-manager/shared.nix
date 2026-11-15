{ pkgs, ... }:
{
 #### PACKAGES ####
  home.packages = with pkgs; [
    tree
    hello
  ];

  #### PROGRAMS ####
   programs = {
    home-manager = {
      enable = true;
    };

    neovim = {
      enable = true;
      plugins = with pkgs.vimPlugins; [ 
        telescope-nvim 
        plenary-nvim 
      ];
    };

    starship = {
      enable = true;
      presets = [ "gruvbox-rainbow" ];
    };

    bash = {
      enable = true;
    };

    fish = {
      enable = true;
    };

    lazygit ={ 
      enable = true;
    };

    gh = {
      enable = true;
    };

    # next program here
  };
}
