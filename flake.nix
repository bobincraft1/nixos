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
   #arm64 = nixpkgs.legacyPackages.aarch64-linux;
   #x86_64 = nixpkgs.legacyPackages.x86_64-linux;
  in

  {
    homeConfigurations = {
     termux = home-manager-config {
      pkgs = import nixpkgs {
        system = "aarch64-linux";
	config.allowUnfree = true;
      };
      modules = [
       ./hosts/termux/home.nix
       ./modules/home-manager/shared.nix
       ./modules/custom/neovim.nix
      ];
     };

     laptop = home-manager-config {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
	config.allowUnfree = true;
      };
      modules = [
       ./hosts/laptop/configuration.nix
       ./modules/home-manager/shared.nix
       #./modules/custom/noctalia.nix
       #laptop modules go here.
      ];
     };  
     #more homeConfigs should start here.
    };
  };
}
