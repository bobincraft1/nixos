#termux setup
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.stateVersion = "26.05";
  home.packages = with pkgs [ 
   tree
   git
   hello
  ];
}

