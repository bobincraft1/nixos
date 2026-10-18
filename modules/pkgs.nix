#------- BasicGlobalPackages ----------
{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true; #Globally Enabling Unfree Software.
  
#------- StandardSystemPackages -------
  environment.systemPackages = with pkgs; [
     vim
     wget
     gh
     jujutsu
     vscode-fhs
  ];
  
#------ ProgramsAndServices ----------
  programs.git = { 
    enable = true;                   
  };
  programs.vscode = {
    enable = false;
  };
  
}