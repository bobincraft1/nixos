{
  description = "My Nix Config";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    home-manager = {
     url = "github:nix-community/home-manager";
     inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:

  let

  in

  {
    homeConfigurations = {
     termux = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
      modules = [
       ./hosts/termux/home.nix
       ./modules/shared.nix
      ];
     };

     #more homeConfigs should start here.
    };

    
  };
}
