# `homeConfigurations` and Modules: Complete Guide

This guide covers the two architectural pillars of a scalable Home Manager flake:
1. **`homeConfigurations`:** How you assemble complete device setups inside `flake.nix`.
2. **Modules:** Every type of module, how Home Manager merges them, and how to write your own reusable feature switches.

---

# Part 1: `homeConfigurations`

## 1. What is a `homeConfiguration`?

Think of your flake as a wardrobe. Each entry inside `homeConfigurations` is one complete outfit with a name tag (`termux`, `arch`, `work`). When you run `home-manager switch --flake .#termux`, you are telling Home Manager: *"Grab the outfit tagged `termux` and put it on."*

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    # "termux" is the name tag you choose
    homeConfigurations.termux = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
      modules = [ ./home.nix ];
    };
  };
}
```

---

## 2. The Arguments Inside `homeManagerConfiguration`

When you call `home-manager.lib.homeManagerConfiguration { ... }`, you hand it a set of instructions:

| Argument | Required? | Purpose |
| :--- | :--- | :--- |
| `pkgs` | **Yes** | The software catalog (`nixpkgs`), which also determines the target CPU architecture (`aarch64-linux`, `x86_64-linux`). |
| `modules` | No | A list (`[ ]`) of module files or inline settings that make up the setup. |
| `extraSpecialArgs` | No | Extra values (like `inputs` or `host`) handed to every module's `{ ... }:` header. |
| `check` | No | Defaults to `true`. Verifies that every option you set actually exists so typos fail loudly. Leave this on. |

### Three Ways to Pass `pkgs`
```nix
# 1. Standard catalog (fastest and simplest)
pkgs = nixpkgs.legacyPackages.aarch64-linux;

# 2. Custom catalog (needed if you want unfree software like VS Code or Discord)
pkgs = import nixpkgs {
  system = "aarch64-linux";
  config.allowUnfree = true;
};

# 3. Custom catalog + Overlays (patches that add or modify packages)
pkgs = import nixpkgs {
  system = "aarch64-linux";
  config.allowUnfree = true;
  overlays = [ self.overlays.default ];
};
```
*(Tip: If you only want to add an overlay to `legacyPackages` without re-importing `nixpkgs`, use `pkgs = nixpkgs.legacyPackages.aarch64-linux.extend self.overlays.default;`.)*

### Passing Data With `extraSpecialArgs`
Normally, every module only receives `config`, `lib`, and `pkgs`. If you want your modules to know the machine's `host` name or access your flake `inputs` (like a non-flake dotfiles repo), pass them in `extraSpecialArgs`:

```nix
extraSpecialArgs = {
  inherit inputs;
  host = "termux";
};
```
Any module can then ask for `host` or `inputs` in its top header: `{ pkgs, host, inputs, ... }:`.

*(Note: Ignore older tutorials that put `username`, `homeDirectory`, `stateVersion`, or `system` directly inside `homeManagerConfiguration`. Those arguments were removed—put them inside your `home.nix` module instead.)*

---

## 3. Scaling to Many Devices Without Copy-Pasting

When you manage multiple machines, create a helper function (`mkHome`) in a `let` block, or generate configurations automatically from a set of hosts using `mapAttrs`:

```nix
  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      # 1. Define your machines in one clean table
      hosts = {
        termux = { system = "aarch64-linux"; user = "root"; };
        arch   = { system = "x86_64-linux";  user = "robert"; };
        laptop = { system = "x86_64-linux";  user = "robert"; };
      };

      # 2. Helper function that builds a complete setup from one host entry
      mkHome = host: cfg:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = cfg.system;
            config.allowUnfree = true;
          };
          modules = [
            ./modules/shared.nix
            ./hosts/${host}/home.nix
            {
              home.username = cfg.user;
              home.homeDirectory =
                if cfg.user == "root" then "/root" else "/home/${cfg.user}";
            }
          ];
          extraSpecialArgs = { inherit inputs host; };
        };
    in {
      # 3. Automatically creates homeConfigurations.termux, .arch, and .laptop!
      homeConfigurations = nixpkgs.lib.mapAttrs mkHome hosts;
    };
```
* **Oh! So this is what happens:** `nixpkgs.lib.mapAttrs` loops over every item in `hosts`, passes the name (`host`) and its settings (`cfg`) into `mkHome`, and builds a complete `homeConfigurations` entry for each one automatically.

---

# Part 2: Types of Modules & How to Write Them

Everything in Home Manager is a **module**. Home Manager takes all your modules and stacks them together like transparent sheets into one finished configuration.

## 4. The Four Types of Modules

Depending on what you need a file to do, you will write it in one of four shapes:

### Type 1: Plain Attribute Set (Static Settings)
A plain `{ ... }` set with no function header at the top.
* **When to use it:** When you only need to set simple switches or text and don't need `pkgs`, `lib`, or `config`.
* **How it looks:**
  ```nix
  {
    programs.git.enable = true;
    home.sessionVariables.EDITOR = "nvim";
  }
  ```

### Type 2: Standard Function Module (Most Common)
A function that receives `{ config, lib, pkgs, ... }:` and returns a set of settings.
* **When to use it:** 90% of your modules—anytime you need to install packages (`pkgs`), read existing config (`config`), or use helpers (`lib`).
* **How it looks:**
  ```nix
  { pkgs, ... }: {
    home.packages = with pkgs; [ tree ripgrep fd ];
  }
  ```

### Type 3: Aggregator / Directory Module (`imports` Only)
A module whose only job is to pull together a folder of smaller modules.
* **When to use it:** When you split a big setup into `git.nix`, `shell.nix`, and `editor.nix` and want to import all of them with a single line.
* **Tip:** If you name this file `default.nix` inside a `modules/` folder, importing `./modules` automatically loads `modules/default.nix`!
* **How it looks (`modules/default.nix`):**
  ```nix
  { ... }: {
    imports = [
      ./git.nix
      ./shell.nix
      ./editor.nix
    ];
  }
  ```

### Type 4: Custom Feature Module (`imports` + `options` + `config`)
A full module that declares **new** custom switches (`options`) and defines what happens when those switches are turned on (`config`).
* **When to use it:** When you want reusable toggles like `my.devtools.enable = true;` that you can turn on or off per machine.
* **Golden Rule:** The moment a file declares `options`, **all normal settings must go inside `config = { ... };`**. Mixing top-level settings with `options` causes an `unsupported attribute` error.

---

## 5. How to Write a Custom Feature Module (Step-by-Step)

Here is the complete pattern for creating a reusable feature module with its own options, safety checks, and conditional settings.

### Step 1: Write the Module (`modules/devtools.nix`)
```nix
{ config, lib, pkgs, ... }:
let
  # Shortcut so we don't have to type 'config.my.devtools' repeatedly
  cfg = config.my.devtools;
in {
  # 1. OPTIONS: Declare the custom boxes other files can fill in
  options.my.devtools = {
    enable = lib.mkEnableOption "my developer tools";

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      example = "hx";
      description = "Default text editor for EDITOR.";
    };

    gitName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Git user name.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to install.";
    };
  };

  # 2. CONFIG: What happens ONLY when 'my.devtools.enable = true'
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Block A: Always applied when my.devtools.enable = true
    {
      # Safety check: fail with a clear message if editor is left blank
      assertions = [
        {
          assertion = cfg.editor != "";
          message = "my.devtools.editor cannot be empty!";
        }
      ];

      home.packages = [ pkgs.ripgrep pkgs.fd ] ++ cfg.extraPackages;
      home.sessionVariables.EDITOR = cfg.editor;
    }

    # Block B: Applied ONLY if gitName was also provided
    (lib.mkIf (cfg.gitName != null) {
      programs.git = {
        enable = true;
        settings.user.name = cfg.gitName;
      };
    })
  ]);
}
```

### Step 2: Use Your New Feature in a Host File (`hosts/termux/home.nix`)
```nix
{ pkgs, ... }: {
  imports = [ ../../modules/devtools.nix ];

  my.devtools = {
    enable = true;
    editor = "hx";
    gitName = "Alex";
    extraPackages = [ pkgs.jq ];
  };
}
```

### Essential Option Types Reference
When declaring `lib.mkOption`, pick the matching type so Nix catches typos automatically:

| Type | What it accepts | Example |
| :--- | :--- | :--- |
| `lib.types.bool` | `true` or `false` | `true` |
| `lib.types.str` | Text | `"nvim"` |
| `lib.types.int` | Whole numbers | `8080` |
| `lib.types.path` | Unquoted file/folder paths | `./kitty.conf` |
| `lib.types.package` | A package from `pkgs` | `pkgs.ripgrep` |
| `lib.types.listOf T` | A list of type `T` | `lib.types.listOf lib.types.str` |
| `lib.types.attrsOf T` | A set whose values are type `T` | `lib.types.attrsOf lib.types.str` |
| `lib.types.nullOr T` | Either type `T` or `null` | `lib.types.nullOr lib.types.str` |
| `lib.types.enum [ ... ]` | Only one of the listed choices | `lib.types.enum [ "dark" "light" ]` |

*(Tip: Always put custom options under your own personal namespace like `my.*` so they never collide with official Home Manager options.)*

---

## 6. How Modules Merge & Resolving Conflicts

When multiple modules set the same option, Home Manager combines them automatically based on the option's type:

* **Lists (`home.packages`) get glued together:** If `shared.nix` installs `pkgs.tree` and `termux/home.nix` installs `pkgs.htop`, you get **both**.
* **Sets (`home.sessionVariables`) merge key-by-key:** If one module sets `EDITOR = "nvim"` and another sets `PAGER = "less"`, you get **both**.
* **Single values (text, numbers, booleans) must agree:** If two modules set `programs.git.settings.init.defaultBranch` to different strings, Nix stops with a **`conflicting definition values`** error.

### Priorities (`mkDefault` vs. Normal vs. `mkForce`)
Every value has a numeric priority (lower numbers win):
1. **`lib.mkForce value` (Priority 50):** Wins over everything. Use sparingly to override stubborn third-party modules.
2. **Normal value (Priority 100):** The standard priority when you write `option = value;`.
3. **`lib.mkDefault value` (Priority 1000):** A weak fallback. Any normal setting in a host file overrides it cleanly without errors.

```nix
# In modules/shared.nix (weak fallback)
home.sessionVariables.EDITOR = lib.mkDefault "nvim";

# In hosts/arch/home.nix (normal setting — wins cleanly!)
home.sessionVariables.EDITOR = "hx";
```

### Controlling Order in Scripts (`mkBefore` and `mkAfter`)
When multiple modules add lines to shell startup scripts (like `programs.fish.interactiveShellInit`), use `lib.mkBefore` to put critical setup at the very top, or `lib.mkAfter` to put commands at the very bottom.

---

## 7. Tips & Tricks for Debugging Modules

* **Why `lib.mkIf` instead of `if ... then`?** Inside `config`, never write `config = if cfg.enable then { ... } else { };`. That causes an **`infinite recursion encountered`** crash because Nix tries to check `cfg.enable` inside `config` before `config` finishes evaluating. Always use `lib.mkIf`.
* **See the full error trail:** If an error message is vague, re-run your command with `--show-trace` to see the exact file and line number that triggered it.
* **Inspect your merged config live:** Run `nix repl`, type `:lf .`, and type `homeConfigurations.termux.config.programs.git` (use Tab to auto-complete!) to see the exact final values after all modules have merged.
* **Find out which file set a value:** Inside `nix repl`, run:
  ```text
  homeConfigurations.termux.options.home.packages.definitionsWithLocations
  ```
  Nix will print every single file that contributed to `home.packages` and what it added.