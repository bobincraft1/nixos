#------NixosGamingConfiguration------
{pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true; #Globally Enabling Unfree Software

  #------GraphicsSettings--------------
  
  #------GamingApplications------------
    environment.systemPackages = with pkgs; [
      
    ];
  #------ProgramsAndServices-----------
  #------PerformanceOptimizations------
  #------AdditionalTweaks--------------
}