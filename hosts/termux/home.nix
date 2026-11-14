#termux setup
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.stateVersion = "26.05";
  time.timeZone = "Africa/Lusaka";
}

