# Flakes and Home Manager in depth

A guided tour of what you can put in a flake and in Home Manager, how each piece works, where it goes, and how to use it. It builds on `flakes-home-manager-explained.md`, so skim that first if the basics are fuzzy.

Contents

1. Flakes: anatomy, inputs, lock file, outputs, commands, gotchas
2. Home Manager: modules, core options, programs, files, environment, activation, custom options, passing data, nixpkgs config, repo layout
3. Reference: commands, finding options, Termux proot notes, troubleshooting, which tool for what

---

# Part 1: Flakes

## 1.1 Anatomy of a flake.nix

A flake is a directory with a `flake.nix` at its root. That file has four top-level attributes:

```nix
{
  description = "My config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }: {
  };

  nixConfig = {
  };
}
```

- `description`: a human-readable string.
- `inputs`: the dependencies, as an attribute set.
- `outputs`: a function that receives all resolved inputs and returns an attribute set of what the flake provides.
- `nixConfig`: Nix settings (like extra binary caches) that apply when this flake is used.

`flake.nix` is ordinary Nix with one big restriction: `inputs` must be written out literally. You can't compute them with `let` bindings or functions, because Nix has to read them before it evaluates anything else.

## 1.2 Inputs

An input is another flake (or plain source tree) your flake depends on.

### URL forms

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  mytool.url = "git+https://example.com/me/mytool.git?ref=main";
  local.url = "path:/root/projects/mytool";
};
```

| Form | Meaning |
| --- | --- |
| `github:owner/repo` | Default branch of a GitHub repo |
| `github:owner/repo/ref` | A branch, tag, or commit hash |
| `github:owner/repo?ref=branch` | Same, with the ref as a query parameter |
| `git+https://host/repo.git?ref=main` | Any git repo over HTTPS |
| `path:/abs/path` | A directory on disk |

To pin to an exact commit, put the commit hash where the ref goes.

### Attribute form

The same input can be written as separate attributes:

```nix
inputs.nixpkgs = {
  type = "github";
  owner = "nixos";
  repo = "nixpkgs";
  ref = "nixos-26.05";
};
```

### Inputs that are not flakes

Set `flake = false` for a repo that has no `flake.nix`, like a dotfiles repo. The input then arrives in `outputs` as a plain path to the source:

```nix
inputs.dotfiles = {
  url = "github:you/dotfiles";
  flake = false;
};
```

Inside a module you can use it like `"${dotfiles}/kitty"`. Section 2.12 shows how to pass it in.

### follows: one nixpkgs for everything

Every flake input that depends on nixpkgs brings its own copy unless you tell it otherwise. `follows` makes it reuse yours:

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  home-manager = {
    url = "github:nix-community/home-manager/release-26.05";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Match the branch names: a Home Manager `release-XX.XX` branch goes with the nixpkgs `nixos-XX.XX` branch. For `unstable`, use Home Manager's default branch with `nixos-unstable`.

`follows` can also point deeper, at an input of an input:

```nix
inputs.nixpkgs.follows = "nixops/nixpkgs";
```

### How inputs reach outputs

Nix resolves every input, then calls your `outputs` function with them by name, plus `self`:

```nix
outputs = { self, nixpkgs, home-manager, ... }@inputs: {
}
```

- Each name before the colon matches an input name.
- `...` swallows the inputs you don't list.
- `@inputs` also keeps the whole set under one name, handy for passing everything along.
- `self` is the flake itself, as a directory in the Nix store. Use it to refer to your own outputs, like `self.packages.${system}.default`.

## 1.3 The lock file

The first time Nix evaluates your flake it writes `flake.lock`. That file pins every input to an exact commit and hash, including inputs of inputs. This is why the same flake builds the same way later. Commit it to git.

Updating:

```sh
nix flake update
nix flake update nixpkgs
nix flake metadata
```

- The first form bumps every input to the newest revision of its branch.
- The second bumps one input only.
- `metadata` shows what is currently locked, with revisions and dates.

Older guides use `nix flake lock --update-input nixpkgs` for the one-input case. It does the same job.

Switching Home Manager never bumps the lock by itself. Only `update` does.

## 1.4 Outputs

`outputs` returns an attribute set. Tools look for specific, conventional names inside it:

| Output | Used by | What it is |
| --- | --- | --- |
| `packages.<system>.<name>` | `nix build .#name` | A package you build |
| `packages.<system>.default` | `nix build` | The package when you name none |
| `apps.<system>.<name>` | `nix run .#name` | A runnable program |
| `devShells.<system>.<name>` | `nix develop .#name` | A development shell |
| `checks.<system>.<name>` | `nix flake check` | A test that must build |
| `formatter.<system>` | `nix fmt` | The formatter for the repo |
| `overlays.<name>` | other flakes, your `pkgs` | A patch to nixpkgs |
| `templates.<name>` | `nix flake init -t` | A starter project |
| `nixosConfigurations.<host>` | `nixos-rebuild` | A whole NixOS machine |
| `homeConfigurations.<name>` | `home-manager` | A Home Manager setup |

You can add any other attribute names you like. Nix only acts on the ones it knows. `homeConfigurations` is read by the `home-manager` tool, not by Nix itself.

### The per-system pattern

Most outputs are keyed by system (`aarch64-linux`, `x86_64-linux`). A small helper avoids repeating yourself:

```nix
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.hello;
      });
    };
}
```

`genAttrs` turns the list of systems into an attribute set where each system maps to whatever your function returns. `nixpkgs.legacyPackages.${system}` is nixpkgs already instantiated for that system.

After this, `nix build` builds `hello` for whichever system you're on.

### packages

```nix
packages = forAllSystems (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in {
    default = pkgs.writeShellScriptBin "greet" ''
      echo "hello from my flake"
    '';
  });
```

```sh
nix build
nix build .#default
```

`nix build` also looks in `legacyPackages`.

### apps

```nix
apps = forAllSystems (system: {
  default = {
    type = "app";
    program = "${nixpkgs.legacyPackages.${system}.hello}/bin/hello";
  };
});
```

```sh
nix run
nix run .#default
```

### devShells

```nix
devShells = forAllSystems (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in {
    default = pkgs.mkShell {
      packages = [ pkgs.python3 pkgs.git ];
      shellHook = ''
        echo "dev shell ready"
      '';
    };
  });
```

```sh
nix develop
```

You land in a shell with those packages on PATH. `shellHook` runs on entry.

### checks and formatter

```nix
checks = forAllSystems (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in {
    hello-runs = pkgs.runCommand "hello-runs" { } ''
      ${pkgs.hello}/bin/hello > $out
    '';
  });

formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
```

```sh
nix flake check
nix fmt
```

A check passes if its derivation builds. `nix fmt` runs whatever formatter package you named.

### overlays

An overlay adds or changes packages in nixpkgs. `final` is the finished package set and `prev` is the one before your change:

```nix
overlays.default = final: prev: {
  greet = final.writeShellScriptBin "greet" ''
    echo hello
  '';
};
```

Use it by building your own `pkgs` with it. Section 2.13 shows where.

### templates

```nix
templates.default = {
  path = ./template;
  description = "Starter project";
};
```

```sh
nix flake init -t .
```

## 1.5 nixConfig

`nixConfig` carries Nix settings with the flake, most often extra binary caches:

```nix
nixConfig = {
  extra-substituters = [ "https://example-cache.cachix.org" ];
  extra-trusted-public-keys = [ "example-cache.cachix.org-1:<key from the cache's page>" ];
};
```

For safety, Nix doesn't apply these silently. With `accept-flake-config = false`, which is what your `nix config show` reports, Nix asks before applying them, or you can pass `--accept-flake-config`. Settings you want everywhere belong in `nix.conf` instead.

## 1.6 Command cheat sheet

| Command | What it does |
| --- | --- |
| `nix flake show` | Lists every output of the flake |
| `nix flake metadata` | Shows inputs and their locked revisions |
| `nix flake check` | Evaluates outputs and builds the `checks` |
| `nix flake update` | Updates the lock file |
| `nix flake init` | Creates a starter `flake.nix` |
| `nix build .#x` | Builds `packages.<system>.x` |
| `nix run .#x` | Runs `apps.<system>.x` |
| `nix develop` | Enters `devShells.<system>.default` |
| `nix fmt` | Runs the `formatter` |
| `nix repl` then `:lf .` | Loads the flake into an interactive prompt |

## 1.7 Gotchas

- **Git-tracked files only.** In a git repo, flakes only see files git knows about. If you create a new `.nix` file, run `git add` on it before building, or Nix reports it as missing.
- **Pure evaluation.** Flakes can't read things outside themselves: no `<nixpkgs>` channel imports, no environment variables, no `builtins.currentSystem`. Take everything from inputs instead. `--impure` lifts the restriction when you really need it.
- **Dirty tree warning.** "Git tree is dirty" means you have uncommitted changes. It's only a warning.
- **inputs can't be computed.** See 1.1.

---

# Part 2: Home Manager

## 2.1 How Home Manager reads your config

Everything you write for Home Manager is a **module**: a file containing a function that returns settings.

```nix
{ config, lib, pkgs, ... }: {
  home.packages = [ pkgs.tree ];
}
```

The arguments:

- `config`: the final, merged result of all your modules. You read values from it, like `config.home.homeDirectory`.
- `lib`: helper functions from nixpkgs (`lib.mkIf`, `lib.mkDefault`, and so on).
- `pkgs`: the package set.
- `...`: swallows any arguments you don't list. Keep it, or the module breaks when more arguments are passed.

Any extra arguments you pass through `extraSpecialArgs` (section 2.12) also arrive here.

Modules pull in other modules with `imports`, and Home Manager merges them all into one config. Lists from different modules are joined, attribute sets are merged, and two modules setting the same single value is an error unless you give one priority (section 2.10).

### What happens on `switch`

1. Nix evaluates all your modules into one config.
2. It builds a directory of all your managed files, a package environment with your packages, and an activation script.
3. The activation script first checks that none of the links it's about to create would overwrite a file Home Manager doesn't own.
4. It links the new files into your home, pointing at the store.
5. It removes links from the previous generation that are no longer in the new one.
6. It runs your own activation entries (section 2.9).

Because files are links into the store, they're read-only. You change them by editing the config and switching again.

## 2.2 Core identity options

```nix
{ pkgs, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
```

- `home.username` and `home.homeDirectory` tell Home Manager whose home this is. In your Termux proot you're root.
- `home.stateVersion` is the Home Manager release your config was first written for. It keeps defaults from changing under you. Set it once and don't bump it just because you updated.
- `programs.home-manager.enable` puts the `home-manager` command on your PATH after the first switch.

## 2.3 Packages

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    tree
    ripgrep
    fd
  ];
}
```

`with pkgs;` saves you typing `pkgs.` in front of every name.

`home.extraOutputsToInstall` also installs extra outputs of those packages, like docs:

```nix
home.extraOutputsToInstall = [ "doc" "info" "devdoc" ];
```

Use `home.packages` for plain tools. Use `programs.<name>` (next section) when the tool also needs config.

## 2.4 Programs

`programs.<name>.enable` is the main pattern. It installs the program and generates its config files. Most programs have the same few knobs:

- `enable`: turn it on.
- `package`: pick a different package, like `pkgs.gitFull`.
- A settings or extra-config option for the program's own config.
- `enableFishIntegration`, `enableZshIntegration`, `enableBashIntegration` for programs that hook into your shell.

### git

```nix
programs.git = {
  enable = true;
  settings = {
    user.name = "Your Name";
    user.email = "you@example.com";
    init.defaultBranch = "main";
    alias.co = "checkout";
  };
};
```

`settings` maps straight onto sections of your git config. Older guides use `userName` and `userEmail`, which are deprecated in favor of `settings.user.name` and `settings.user.email`.

### Shells

```nix
programs.fish = {
  enable = true;
  shellAliases = {
    ll = "ls -la";
  };
  interactiveShellInit = ''
    set -g fish_greeting
  '';
};

programs.zsh = {
  enable = true;
  enableCompletion = true;
  shellAliases.gs = "git status";
};

programs.bash = {
  enable = true;
  shellAliases.gs = "git status";
};
```

Enabling a shell here installs it and writes its startup files. It does not change your login shell. You start `fish` or `zsh` yourself.

### More examples

```nix
programs.tmux = {
  enable = true;
  keyMode = "vi";
  extraConfig = ''
    set -g mouse on
  '';
};

programs.direnv = {
  enable = true;
  nix-direnv.enable = true;
};

programs.starship.enable = true;
```

To see what a program offers, check the options reference or run `home-manager option programs.<name>` (section 3.2).

## 2.5 Files and dotfiles

For programs without their own module, place files directly.

### home.file

`home.file` places files relative to your home directory:

```nix
home.file.".hushlogin".text = "";

home.file.".local/bin/hello" = {
  executable = true;
  text = ''
    #!/bin/sh
    echo hello
  '';
};
```

Options per file:

| Option | Meaning |
| --- | --- |
| `text` | Write this string as the file contents |
| `source` | Use an existing file or directory as the contents |
| `executable` | Mark the file executable |
| `target` | Path relative to your home, if different from the attribute name |
| `recursive` | If `source` is a directory, link its files individually instead of linking the directory |
| `onChange` | Shell commands to run after the file changed between generations |
| `enable` | Turn a single file on or off |

### xdg.configFile

The same, but relative to `~/.config`:

```nix
xdg.configFile."kitty/kitty.conf".source = ./kitty.conf;

xdg.configFile."nvim" = {
  source = ./nvim;
  recursive = true;
};
```

`./kitty.conf` is a path in your repo. Nix copies it into the store when building. `xdg.dataFile` does the same for `~/.local/share`.

### Editable links

A normal `source` is a read-only copy, so every edit needs a `switch`. To link to a live directory that you can edit freely:

```nix
{ config, ... }: {
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/root/dotfiles/nvim";
}
```

Edits in `/root/dotfiles/nvim` take effect immediately. The tradeoff is that this path is outside the repo's reproducibility, since the target has to exist on the machine.

## 2.6 Environment variables, PATH and aliases

```nix
{ config, ... }: {
  home.sessionVariables = {
    EDITOR = "nvim";
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
  };

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  home.shellAliases = {
    ll = "ls -la";
  };
}
```

- `home.sessionVariables` sets environment variables for your login sessions.
- `home.sessionPath` adds directories to PATH.
- `home.shellAliases` defines aliases for every shell Home Manager manages.
- Per-shell aliases go under `programs.<shell>.shellAliases`.

Important: these variables live in a file called `hm-session-vars.sh`. Shells that Home Manager manages (`programs.bash.enable` and similar) source it for you. If a shell isn't managed, you must source it yourself:

```sh
. ~/.nix-profile/etc/profile.d/hm-session-vars.sh
```

For your proot, the easiest path is `programs.bash.enable = true;`, so Home Manager wires this up in bash's startup files.

## 2.7 XDG directories

```nix
{ config, ... }: {
  xdg.enable = true;
}
```

This turns on XDG integration. After that, `config.xdg.configHome`, `config.xdg.dataHome` and `config.xdg.cacheHome` give you the directory paths, which is what the examples above use. `xdg.userDirs` and `xdg.mimeApps` exist for desktop folders and default apps, but they only matter on a graphical desktop.

## 2.8 Services

`services.<name>` options set up background programs. On a normal Linux desktop they become systemd user units. Your Termux proot has no systemd, so skip `services.*` there. Packages, programs and files all work normally.

## 2.9 Activation scripts

When you need to run a command during `switch`, such as creating a directory, use `home.activation`:

```nix
{ lib, ... }: {
  home.activation.makeProjectsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $VERBOSE_ARG "$HOME/projects"
  '';
}
```

- Entries form an ordered graph (a DAG). `entryAfter [ "writeBoundary" ]` means run after the files have been linked.
- `entryBefore [ "writeBoundary" ]` runs earlier, which is how Home Manager's own safety checks work.
- Entries can depend on each other: `entryAfter [ "makeProjectsDir" ]`.
- Entries must be idempotent, meaning running them twice gives the same result as once.
- `$DRY_RUN_CMD` makes the command a no-op during `home-manager switch -n`.

For simple "run this when a file changes", the per-file `onChange` option (2.5) is lighter.

## 2.10 Custom options, conditions and priorities

You can write your own options, so a module becomes a switch you can flip:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.my.devtools;
in {
  options.my.devtools = {
    enable = lib.mkEnableOption "my dev tools";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.git pkgs.ripgrep ] ++ cfg.extraPackages;
  };
}
```

Then, in another module:

```nix
{ pkgs, ... }: {
  imports = [ ./modules/devtools.nix ];

  my.devtools = {
    enable = true;
    extraPackages = [ pkgs.tree ];
  };
}
```

The helpers:

| Helper | Use |
| --- | --- |
| `lib.mkEnableOption "x"` | A boolean `enable` option, default false |
| `lib.mkOption { ... }` | Declare an option with a type, default and description |
| `lib.mkIf cond { ... }` | Apply this config only when `cond` is true |
| `lib.mkMerge [ a b ]` | Combine several config chunks, often with `mkIf` in them |
| `lib.mkDefault v` | A weak value that any plain definition overrides |
| `lib.mkForce v` | A strong value that beats plain definitions |

Priority in short: a plain value has priority 100, `mkDefault` is weaker at 1000, and `mkForce` is stronger at 50. Lower numbers win. So a shared module can say:

```nix
programs.git.settings.init.defaultBranch = lib.mkDefault "main";
```

and a host-specific module can override it with a plain `= "trunk";` without any error.

A conditional example, combined with a host name passed in (section 2.12):

```nix
{ lib, pkgs, host, ... }: {
  config = lib.mkMerge [
    { home.packages = [ pkgs.git ]; }
    (lib.mkIf (host == "termux") { home.packages = [ pkgs.tree ]; })
  ];
}
```

## 2.11 Splitting into modules

```nix
{
  imports = [
    ./git.nix
    ./shell.nix
    ./packages.nix
  ];
}
```

Each of those files is its own module and can have its own `{ config, lib, pkgs, ... }:` header. A good rule: one file per topic, and a small host file that imports what that machine wants.

## 2.12 Passing data into modules

`extraSpecialArgs` hands extra arguments to every module:

```nix
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.aarch64-linux;
  modules = [ ./hosts/termux/home.nix ];
  extraSpecialArgs = {
    inherit inputs;
    host = "termux";
  };
}
```

Any module can then take them:

```nix
{ pkgs, inputs, host, ... }: {
  xdg.configFile."kitty".source = "${inputs.dotfiles}/kitty";
}
```

Use `extraSpecialArgs`, not `specialArgs`. The latter belongs to NixOS configs.

## 2.13 nixpkgs config, unfree packages and overlays

With `legacyPackages`, you get plain nixpkgs with no custom settings. To allow unfree packages or apply overlays, build your own `pkgs`:

```nix
pkgs = import nixpkgs {
  system = "aarch64-linux";
  config.allowUnfree = true;
  overlays = [ self.overlays.default ];
};
```

and pass it as the `pkgs` argument of `homeManagerConfiguration`. A shorter way for overlays alone is `nixpkgs.legacyPackages.${system}.extend overlay`.

## 2.14 Reusable pieces and multiple setups

A helper function removes the repetition between configs:

```nix
outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    mkHome = { system, host, modules }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        inherit modules;
        extraSpecialArgs = { inherit inputs host; };
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
```

You can also publish modules as flake outputs so other flakes can import them. Output names beyond Nix's known ones are free-form, and `homeModules` is a common choice:

```nix
homeModules.devtools = ./modules/devtools.nix;
```

A layout that fits what you're building:

```
.
|-- flake.nix
|-- flake.lock
|-- hosts
|   |-- termux
|   |   `-- home.nix
|   `-- arch
|       `-- home.nix
`-- modules
    |-- shared.nix
    |-- shell.nix
    `-- devtools.nix
```

Hosts hold what is specific to one machine. Modules hold what several machines share.

---

# Part 3: Reference

## 3.1 Home Manager commands

| Command | What it does |
| --- | --- |
| `home-manager switch` | Build and activate the configuration |
| `home-manager build` | Build without activating |
| `home-manager generations` | List all generations |
| `home-manager packages` | List packages installed by Home Manager |
| `home-manager expire-generations "-30 days"` | Remove generations older than that |
| `home-manager remove-generations ID` | Remove specific generations |
| `home-manager news` | Show news entries |
| `home-manager option NAME` | Inspect an option in your config |
| `home-manager edit` | Open the config in your editor |
| `home-manager init` | Generate a starter configuration |
| `home-manager uninstall` | Remove Home Manager, its managed files, packages and generations |

Useful flags:

| Flag | Meaning |
| --- | --- |
| `--flake .#name` | Use the flake config called `name` |
| `-b ext` | Rename colliding files by appending `.ext` instead of failing |
| `-n`, `--dry-run` | Show what would happen without doing it |
| `--show-trace` | Full error location for evaluation errors |
| `-L` | Print build logs |
| `--impure` | Allow impure evaluation |
| `-v` | Verbose output |

Typical use:

```sh
home-manager switch -b backup --flake .#termux
home-manager generations
home-manager expire-generations "-30 days"
nix-collect-garbage
```

Old generations stay on disk until you expire them and then collect garbage. To roll back, run the `activate` script inside an older generation's path, which `home-manager generations` prints.

The first time, before the `home-manager` command exists, bootstrap through the flake and match the branch you pinned:

```sh
nix run home-manager/release-26.05 -- switch --flake .#termux
```

## 3.2 Finding options

There are thousands of options. You don't memorize them, you look them up:

- The Home Manager options reference at `nix-community.github.io/home-manager/options.xhtml` lists them all with descriptions and examples.
- `home-manager option programs.git.enable` shows an option's value in your config.
- The repl lets you browse your config interactively:

```sh
nix repl
```

Then inside the repl:

```text
:lf .
homeConfigurations.termux.config.programs.git
```

`:lf .` loads the flake in the current directory. After that you can tab-complete through the config.

Options get renamed and deprecated over time. When a switch prints a deprecation warning, it names the replacement, so follow that.

## 3.3 Termux proot notes

- You're the `root` user with home `/root`, so set `home.username` and `home.homeDirectory` to match.
- There's no systemd, so skip `services.*`. Everything else in this guide applies.
- Set `programs.bash.enable = true` so your session variables get sourced, or source `hm-session-vars.sh` yourself.
- Files that already exist in your home block a switch. Use `-b backup`.
- Packages are `aarch64-linux`. Preview what would be fetched versus built with `nix build --dry-run .#homeConfigurations.termux.activationPackage`.
- If the first switch fails with a profile-related error, send me the exact message.

## 3.4 Troubleshooting

| What you see | Likely cause | What to do |
| --- | --- | --- |
| Nix says a file doesn't exist, but it does | New file not tracked by git | `git add` the file |
| Switch refuses because a file already exists | A real file sits where Home Manager wants a link | Move it, or use `-b backup` |
| "The option ... does not exist" | Typo, or the option was renamed or removed | Check the options reference or `home-manager option` |
| A long, unreadable evaluation error | Error is deep inside module evaluation | Re-run with `--show-trace` |
| Deprecation warning for an option | The option was renamed | Switch to the name the warning gives |
| Two modules set the same value | Conflicting definitions | Make one `lib.mkDefault` or `lib.mkForce` |
| Config changed but nothing differs | Inputs didn't change and your edit isn't tracked | `git add`, then switch again |
| You want to preview a switch | | `home-manager switch -n --flake .#name` |
| Disk usage keeps growing | Old generations are kept | `home-manager expire-generations`, then `nix-collect-garbage` |

## 3.5 Which tool for what

| You want to | Use |
| --- | --- |
| Install a tool with no config | `home.packages` |
| Install a tool and generate its config and shell hooks | `programs.<name>.enable` |
| Write a config file for a program with no module | `xdg.configFile` or `home.file` |
| Keep a dotfile live-editable | `config.lib.file.mkOutOfStoreSymlink` |
| Set an environment variable | `home.sessionVariables` |
| Add a directory to PATH | `home.sessionPath` |
| Define a shell alias | `home.shellAliases` or `programs.<shell>.shellAliases` |
| Run a command during a switch | `home.activation` |
| Run a command when one file changes | that file's `onChange` |
| Share config between machines | modules plus `imports` |
| Differ per machine | `hosts/<name>` files, `mkIf`, `mkDefault`, `extraSpecialArgs` |
| Use a repo that isn't a flake | an input with `flake = false` |
| Allow unfree packages or apply overlays | a custom `pkgs` built with `import nixpkgs { ... }` |
| Use one nixpkgs everywhere | `inputs.<name>.inputs.nixpkgs.follows` |
| Prefer pre-built binaries | a release channel branch input, then check with `--dry-run` |
| Ship a starter project | `templates` output |
| Add a binary cache for one flake | `nixConfig` |
