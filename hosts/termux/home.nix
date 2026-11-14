#termux setup
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.stateVersion = "26.05";
  home.packages = with pkgs; [ 
   hello
   tree
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

  # next program here
 };
}

