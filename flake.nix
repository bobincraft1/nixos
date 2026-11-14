{
  description = "My Nix Config";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, noctalia, ... }@inputs:

  let
   home-manager-config = home-manager.lib.homeManagerConfiguration;
   android = nixpkgs.legacyPackages.aarch64-linux;
   desktop = nixpkgs.legacyPackages.x86_64-linux;
  in

  {
    homeConfigurations = {
     termux = home-manager-config {
      pkgs = android;
      modules = [
       ./hosts/termux/home.nix
       ./modules/home-manager/shared.nix
       #./modules/custom/noctalia.nix
      ];
     };

     laptop = home-manager-config {
      pkgs = desktop;
      modules = [
       ./modules/home-manager/shared.nix
       #laptop modules go here.
      ];
     };  
     #more homeConfigs should start here.
    };
  };
}
