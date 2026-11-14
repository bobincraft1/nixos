# Flakes and Home Manager: Complete Guide & Reference

This guide covers everything you need to know about **Flakes** and **Home Manager**—from how `flake.nix` is structured and wired up, to configuring programs, dotfiles, and custom services that have no built-in Home Manager module.

---

# Part 1: Flakes

## 1. Anatomy of a `flake.nix`

Think of a flake as a **self-contained project folder** with a strict bill of materials. Any folder containing a `flake.nix` file at its root is a flake.

A `flake.nix` file has up to four top-level sections:

```nix
{
  # 1. A short note describing what this flake is for
  description = "My personal Nix setups";

  # 2. INPUTS: External repositories your setup depends on
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  # 3. OUTPUTS: A function that receives those inputs and builds your setups
  outputs = { self, nixpkgs, ... }@inputs: {
    # Your homeConfigurations, packages, devShells, etc. go here
  };

  # 4. NIXCONFIG: Optional Nix settings (like extra binary caches)
  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };
}
```

### Key Rules & Tips for `flake.nix`:
* **`inputs` cannot be computed:** You must write out `inputs` plainly. You cannot use `let` variables or functions inside `inputs`, because Nix reads `inputs` first before evaluating any code.
* **What is `self`?** Nix automatically passes `self` into `outputs`. `self` refers to your own flake folder (for example, `self.overlays.default` lets you use an overlay defined right inside the same `flake.nix`).
* **What is `@inputs`?** Writing `{ self, nixpkgs, ... }@inputs:` lets you unpack `nixpkgs` directly while also keeping the entire inputs set under the name `inputs` so you can pass all of them to your modules at once.
* **Git Tracking Gotcha:** If your flake folder is a Git repository, Nix **completely ignores** any new file until you run `git add <filename>`. If Nix reports `path ... does not exist` when you can clearly see the file, run `git add`!

---

## 2. Inputs and `flake.lock`

### Input URL Formats
| Format | What it grabs | Example |
| :--- | :--- | :--- |
| `github:owner/repo` | Default branch of a GitHub repo | `"github:nix-community/home-manager"` |
| `github:owner/repo/ref` | Specific branch, tag, or commit hash | `"github:nixos/nixpkgs/nixos-26.05"` |
| `git+https://...` | Any Git repository URL | `"git+https://example.com/me/repo.git?ref=main"` |
| `path:/abs/path` | A local folder on your device | `"path:/root/projects/mytool"` |

### Non-Flake Repositories (`flake = false`)
If you want to pull in a GitHub repo that does **not** have its own `flake.nix` (such as a plain dotfiles repo or a Neovim plugin), add `flake = false;`:

```nix
inputs.dotfiles = {
  url = "github:you/dotfiles";
  flake = false;
};
```
* **As a result:** Nix downloads that repository and passes it into `outputs` as a plain folder path you can use like `"${inputs.dotfiles}/kitty"`.

### Sharing One `nixpkgs` (`follows`)
Every flake input that uses `nixpkgs` will download its own separate copy unless you tell it not to. Always add `inputs.nixpkgs.follows = "nixpkgs";` and match your release branches:

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  home-manager = {
    url = "github:nix-community/home-manager/release-26.05";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```
*(Tip: If you use `nixpkgs-unstable`, pair it with Home Manager's default branch `"github:nix-community/home-manager"`.)*

### How `flake.lock` Works
The first time you run a flake command, Nix creates `flake.lock`. This file freezes the exact commit hash and date of every input.
* **Switching does NOT update software:** Running `home-manager switch` uses the exact locked versions in `flake.lock`.
* **Updating all inputs:** Run `nix flake update` to bump everything in `flake.lock` to the latest versions.
* **Updating just one input:** Run `nix flake update home-manager` to update only Home Manager while keeping `nixpkgs` untouched.

---

## 3. Standard Flake Outputs

Tools look for specific conventional names inside the set returned by `outputs`:

| Output Name | Command that uses it | Purpose |
| :--- | :--- | :--- |
| `homeConfigurations.<name>` | `home-manager switch --flake .#name` | A Home Manager user setup |
| `nixosConfigurations.<host>` | `nixos-rebuild switch --flake .#host` | A full NixOS operating system setup |
| `packages.<system>.default` | `nix build` | Builds a package (`nix build .#name` for named ones) |
| `apps.<system>.default` | `nix run` | Runs a program directly (`nix run .#name` for named ones) |
| `devShells.<system>.default` | `nix develop` | Enters a temporary shell with dev tools on `PATH` |
| `formatter.<system>` | `nix fmt` | Formats your `.nix` files (e.g., `nixpkgs.legacyPackages.${system}.alejandra`) |
| `overlays.<name>` | Used inside `pkgs` | Modifies or adds packages to `nixpkgs` |
| `homeModules.<name>` | Imported by other flakes | Exposes your Home Manager modules for reuse |

### Quick Example: Adding a Dev Shell (`devShells`)
You can include a development environment right inside your config flake so running `nix develop` drops you into a shell with extra tools:

```nix
devShells.aarch64-linux.default =
  let pkgs = nixpkgs.legacyPackages.aarch64-linux; in
  pkgs.mkShell {
    packages = [ pkgs.nil pkgs.alejandra ]; # Nix language server & formatter
    shellHook = ''echo "Nix config dev shell ready!"'';
  };
```

---

## 4. Wiring Home Manager into `flake.nix`

Here is a complete, well-wired `flake.nix` supporting multiple devices, unfree software, and passing `inputs` and `host` into every module:

```nix
{
  description = "Home Manager setups";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      # Helper function to avoid repeating boilerplate for each device
      mkHome = { system, host, modules }:
        home-manager.lib.homeManagerConfiguration {
          # Instantiate nixpkgs with unfree packages allowed
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # List of modules to combine for this setup
          inherit modules;

          # Extra values handed to every module's { ... }: header
          extraSpecialArgs = {
            inherit inputs host;
          };
        };
    in {
      homeConfigurations = {
        termux = mkHome {
          system = "aarch64-linux";
          host = "termux";
          modules = [ ./hosts/termux/home.nix ./modules/shared.nix ];
        };

        arch = mkHome {
          system = "x86_64-linux";
          host = "arch";
          modules = [ ./hosts/arch/home.nix ./modules/shared.nix ];
        };
      };
    };
}
```

### How to Run & Switch:
1. **First time ever** (before `home-manager` is installed on your PATH):
   ```sh
   nix run home-manager/release-26.05 -- switch -b backup --flake .#termux
   ```
2. **Every time after that:**
   ```sh
   home-manager switch -b backup --flake .#termux
   ```
   *(Adding `-b backup` tells Home Manager to safely rename any existing unmanaged config files to `.backup` instead of failing).*

---

# Part 2: Configuring Software & Services in Home Manager

## 5. Core Identity & Packages

Every Home Manager configuration needs your identity and `stateVersion`:

```nix
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";

  # Set this once to the release you started on, and NEVER change it later
  home.stateVersion = "26.05";

  # Ensures the 'home-manager' CLI tool stays installed on your PATH
  programs.home-manager.enable = true;

  # Plain CLI tools that don't need generated config files
  home.packages = with pkgs; [
    tree
    ripgrep
    fd
  ];
}
```

---

## 6. Programs With Built-in Modules (`programs.<name>`)

When Home Manager has a module for a program, enabling it installs the package **and** writes its configuration files into `/nix/store`, symlinking them into your home folder:

```nix
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Your Name";
      user.email = "you@example.com";
      init.defaultBranch = "main";
      alias.co = "checkout";
    };
  };

  programs.fish = {
    enable = true;
    shellAliases.ll = "ls -la";
    interactiveShellInit = ''
      set -g fish_greeting
    '';
  };

  programs.bash = {
    enable = true;
    shellAliases.gs = "git status";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
```
* **Tip (Environment Variables & Shells):** `home.sessionVariables` and `home.sessionPath` are written to `~/.nix-profile/etc/profile.d/hm-session-vars.sh`. Enabling `programs.bash.enable = true` (or `fish`/`zsh`) ensures Home Manager automatically loads that file whenever you open a terminal.

---

## 7. Configuring Packages That Have NO Home Manager Module

Thousands of packages in `nixpkgs` do not have a `programs.<name>` option in Home Manager. Here is how you install and configure them cleanly:

### Method A: Install in `home.packages` + Write Config via `xdg.configFile` or `home.file`
1. Put the package in `home.packages` so the binary is installed.
2. Place its configuration file using `xdg.configFile` (for `~/.config/...`) or `home.file` (for `~/...`).

```nix
{ config, pkgs, ... }: {
  # 1. Install the package
  home.packages = [ pkgs.fastfetch pkgs.helix ];

  # 2a. Copy a config file from your flake folder into ~/.config/fastfetch/config.jsonc
  xdg.configFile."fastfetch/config.jsonc".source = ./fastfetch.jsonc;

  # 2b. Or write the config inline using .text
  xdg.configFile."helix/config.toml".text = ''
    theme = "gruvbox"
    [editor]
    line-number = "relative"
  '';

  # 2c. Copy an entire directory of config files recursively
  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}
```

### Method B: Generate JSON, TOML, or YAML Configs Safely (`pkgs.formats`)
Instead of writing raw text strings and risking syntax typos, you can use `pkgs.formats` to write Nix sets that automatically compile into valid JSON, TOML, or YAML files:

```nix
{ pkgs, ... }:
let
  tomlFormat = pkgs.formats.toml { };
  jsonFormat = pkgs.formats.json { };
in {
  home.packages = [ pkgs.starship pkgs.fastfetch ];

  # Converts a Nix set directly into a valid TOML file
  xdg.configFile."starship.toml".source = tomlFormat.generate "starship-config" {
    add_newline = false;
    character = {
      success_symbol = "[➜](bold green)";
      error_symbol = "[✗](bold red)";
    };
  };

  # Converts a Nix set directly into a valid JSON file
  xdg.configFile."fastfetch/config.jsonc".source = jsonFormat.generate "fastfetch-config" {
    modules = [ "title" "os" "kernel" "uptime" "memory" ];
  };
}
```

### Method C: Keep a Dotfile Live-Editable (`mkOutOfStoreSymlink`)
Files placed with `.source = ./file` are copied into `/nix/store` and become **read-only**, meaning you must run `home-manager switch` after every edit. If you are actively tweaking a config (like Neovim or a window manager) and want edits to apply immediately:

```nix
{ config, ... }: {
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/root/my-flake/dotfiles/nvim";
}
```
*(Note: You must pass an absolute path string like `"/root/..."`, not a relative `./path`.)*

### Method D: Wrap a Program With Command-Line Flags (`symlinkJoin` + `makeWrapper`)
If a CLI tool has no config file and only accepts command-line flags (e.g., `mytool --color=always --config /path/to/cfg`), you can create a tiny wrapper package in `home.packages` so those flags are always passed automatically:

```nix
{ pkgs, ... }:
let
  myWrappedTool = pkgs.symlinkJoin {
    name = "bat-wrapped";
    paths = [ pkgs.bat ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/bat \
        --add-flags "--theme=TwoDark --style=numbers"
    '';
  };
in {
  home.packages = [ myWrappedTool ];
}
```

---

## 8. Running Background Services With NO Home Manager Module

Sometimes you want a program to run in the background (like `syncthing`, a custom sync script, or a local server) when Home Manager has no `services.<name>` module for it. How you do this depends on whether your system uses **systemd** or **Termux/proot**.

### Case 1: Standard Linux Desktop/Server (With `systemd`)
Use `systemd.user.services.<name>` to define your own background daemon. Home Manager will generate the `.service` unit file and start it automatically when you run `switch`:

```nix
{ pkgs, ... }: {
  systemd.user.services.my-background-sync = {
    Unit = {
      Description = "My custom background sync daemon";
      After = [ "network-online.target" ];
    };

    Service = {
      # Always use the full path to the binary in /nix/store
      ExecStart = "${pkgs.rclone}/bin/rclone mount gdrive: /home/user/gdrive";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
```
* **Managing it:** Check its status anytime with `systemctl --user status my-background-sync`.
* **Running on a timer (`systemd.user.timers`):** To run a script every hour instead of continuously, pair a `oneshot` service with a timer:
  ```nix
  systemd.user.services.hourly-backup = {
    Unit.Description = "Run backup script";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /home/user/scripts/backup.sh";
    };
  };

  systemd.user.timers.hourly-backup = {
    Unit.Description = "Trigger backup every hour";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
  ```

### Case 2: Termux Proot / Containers (No `systemd`)
Because Termux proot does not run `systemd`, `systemd.user.services` will not start there. Instead, you have two clean options:

1. **Start lightweight daemons via Shell Startup (`programs.bash.initExtra`):**
   Check if the process is already running (`pgrep`), and start it in the background if not:
   ```nix
   { pkgs, ... }: {
     programs.bash.initExtra = ''
       if ! pgrep -x "syncthing" > /dev/null; then
         nohup ${pkgs.syncthing}/bin/syncthing serve --no-browser > /tmp/syncthing.log 2>&1 &
       fi
     '';
   }
   ```
2. **Run one-off setup commands during `home-manager switch` (`home.activation`):**
   If you just need folders created or permissions fixed every time you switch:
   ```nix
   { lib, ... }: {
     home.activation.ensureDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       $DRY_RUN_CMD mkdir -p $VERBOSE_ARG "$HOME/projects" "$HOME/.local/bin"
     '';
   }
   ```

---

# Part 3: Commands & Troubleshooting

## 9. Essential Command Cheat Sheet

| Command | What it does |
| :--- | :--- |
| `home-manager switch -b backup --flake .#name` | Builds, backs up colliding files, and activates your setup |
| `home-manager switch -n --flake .#name` | Dry run: previews what would change without touching files |
| `home-manager build --flake .#name` | Tests building your setup without activating it |
| `home-manager generations` | Lists all previous builds so you can roll back if needed |
| `home-manager expire-generations "-30 days"` | Deletes saved builds older than 30 days |
| `nix-collect-garbage -d` | Frees disk space by deleting old unreferenced store paths |
| `home-manager option programs.git.enable` | Inspects the current value of an option in your config |
| `nix flake update` | Updates all inputs in `flake.lock` to latest versions |
| `nix flake show` | Lists all outputs exposed by your `flake.nix` |

## 10. Quick Decision Guide: Which Tool Should I Use?

| If you want to... | Use this |
| :--- | :--- |
| Install a CLI tool that needs no config | `home.packages = [ pkgs.tree ];` |
| Install a tool AND generate its config automatically | `programs.<name>.enable = true;` |
| Configure a tool that has NO Home Manager module | `home.packages` + `xdg.configFile` (or `pkgs.formats`) |
| Edit a dotfile live without rebuilding every time | `config.lib.file.mkOutOfStoreSymlink` |
| Always pass specific CLI flags to a program | Wrap it with `pkgs.symlinkJoin` + `pkgs.makeWrapper` |
| Run a custom background daemon (with systemd) | `systemd.user.services.<name>` |
| Run a custom background daemon (in Termux/proot) | `pgrep` + `nohup` check in `programs.bash.initExtra` |
| Run a setup command during `switch` | `home.activation.<name>` |
| Share settings across multiple devices | Separate files + `imports = [ ... ];` |
| Set a fallback value that one machine can override | `lib.mkDefault` |