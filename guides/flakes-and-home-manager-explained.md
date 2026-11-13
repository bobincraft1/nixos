# Flakes and Home Manager, explained

## What a flake is

A flake is a directory with a `flake.nix` that declares two things:

- **Inputs**: what it depends on (nixpkgs, Home Manager, other flakes).
- **Outputs**: what it provides (packages, dev shells, system or home configurations).

The exact versions of the inputs are pinned in `flake.lock`, so the same config builds the same way every time. Run `nix flake update` when you want newer versions.

```nix
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }: {
    packages.aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.hello;
  };
}
```

`outputs` is a function. Nix fetches the inputs and passes them in, and the function returns an attribute set. Tools look for conventional names inside it: `packages`, `devShells`, `nixosConfigurations`, `homeConfigurations`.

With the flake above, `nix run .` runs `hello`.

Gotcha: in a git repo, flakes only see files that are git-tracked. Run `git add` on new files before building.

## Wiring in Home Manager

Add Home Manager as a second input and expose a `homeConfigurations` output.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    homeConfigurations.termux = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
      modules = [ ./hosts/termux/home.nix ];
    };
  };
}
```

- `follows` makes Home Manager use your nixpkgs instead of pulling its own copy.
- `pkgs` decides the architecture the config is built for.
- `modules` is a list of Nix files that describe your home.

A minimal `home.nix`:

```nix
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.stateVersion = "26.05";
  home.packages = [ pkgs.tree pkgs.git ];
}
```

Set `stateVersion` to the Home Manager release you start on and don't change it afterwards.

## Multiple setups

`homeConfigurations` is a set, and each name in it is an independent setup. You pick one with `#name`. A flake reference like `.#termux` expands to `.#homeConfigurations.termux.activationPackage`.

```nix
homeConfigurations = {
  termux = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
    modules = [ ./hosts/termux/home.nix ./modules/shared.nix ];
  };
  arch = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [ ./hosts/arch/home.nix ./modules/shared.nix ];
  };
};
```

Switch between them by name:

```sh
home-manager switch --flake .#termux
home-manager switch --flake .#arch
```

Each config has its own architecture and module list. Shared files like `modules/shared.nix` are reused across configs.

Switching does not upgrade flake inputs. Run `nix flake update` for that.

## First run

The first time, Home Manager isn't installed yet, so bootstrap it through the flake:

```sh
nix run home-manager/master -- switch --flake .#termux
```

After that, `home-manager` is on your PATH and a rebuild is:

```sh
home-manager switch --flake .#termux
```

Useful related commands:

```sh
home-manager build --flake .#termux
home-manager generations
```

`build` produces the generation without activating it. `generations` lists previous ones so you can go back if a change breaks something.

## How Home Manager works

Home Manager turns the Nix options you write into real files and packages in your home. You edit `home.nix`, run `home-manager switch`, and it builds a new generation and symlinks the results into place. Those symlinks point into `/nix/store`, so the files are read-only and you always change them through the config. Old generations are kept, so you can roll back.

### Packages, programs, shell and variables

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.tree pkgs.ripgrep ];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Your Name";
      email = "you@example.com";
    };
  };

  programs.fish = {
    enable = true;
    shellAliases.ll = "ls -la";
  };

  home.sessionVariables.EDITOR = "nvim";
}
```

- `home.packages` installs tools into your profile.
- `programs.<name>.enable` installs the program and generates its config. For git, that creates the `.config/git/config` file for you.
- Older guides use `userName` and `userEmail` for git. Those are deprecated in favor of `settings.user.name` and `settings.user.email`.
- `programs.bash.enable` and `programs.zsh.enable` work the same way, so you can manage all your shells here.

### Any dotfile

This works even for programs Home Manager has no options for:

```nix
xdg.configFile."kitty/kitty.conf".source = ./kitty.conf;
home.file.".hushlogin".text = "";
```

- `xdg.configFile` lands under `~/.config`.
- `home.file` lands relative to `~`.
- `.source` points at a file in your repo and `.text` writes inline content.

### Splitting into modules

```nix
{
  imports = [ ./git.nix ./shell.nix ];
}
```

Each file is its own `{ pkgs, ... }: { ... }` module, and Home Manager merges them all. This is also how the `modules` list in the flake works.

### Practical notes

- If a file already exists in your home, `switch` refuses to overwrite it. Move it, or let Home Manager rename it automatically:

```sh
home-manager switch -b backup --flake .#termux
```

- `services.*` options use systemd user units. A proot has no systemd, so those won't run. Packages, programs and dotfiles work normally.
- The full list of options is in the Home Manager options reference at `nix-community.github.io/home-manager/options.xhtml`.
