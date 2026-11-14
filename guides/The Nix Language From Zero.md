# The Nix Language From Zero

You do not need any coding background to read this guide. By the end, you will be able to open any `flake.nix` or `home.nix` file and instantly understand what each line does, where new settings go, and what happens when you add them.

---

## 1. How Nix Thinks (The Big Idea)

Most computer tools follow a step-by-step recipe: *"First create a folder, then copy this file, then change this setting."* 

Nix does not use steps. Instead, a Nix file is like a **filled-out order form**. You describe the exact end result you want (which programs you want installed, what your Git username should be, what your terminal aliases are), and Nix figures out how to build it behind the scenes.

* **One File = One Expression:** Every `.nix` file boils down to a single final value (usually a set of settings).
* **Nix is Lazy:** Nix only calculates a setting if something actually uses it. If you write a variable in a `let` block and never use it, Nix completely ignores it without errors.

### How to test things yourself
You can test any snippet from this guide live on your machine. Open your terminal and type:

```sh
nix repl
```

Type a piece of Nix, press Enter, and Nix shows you what it turns into. Type `:q` and press Enter to exit.

---

## 2. The Building Blocks (Values)

Everything you write in a Nix file is made of five basic types of information.

### 1. Text (Strings)
Text always goes inside double quotes (`"`).

* **Where it goes:** Usernames, Git emails, environment variables.
* **How it looks:** `"root"` or `"nvim"`

**Filling in the blanks (`${ }`):**
If you want to insert a saved name inside a piece of text, wrap it in `${ }`.
* **You write:**
  ```nix
  user = "root";
  homeDirectory = "/${user}";
  ```
* **As a result:** `homeDirectory` becomes `"/root"`.
* **Tip:** Only text can go inside `${ }`. If you need to insert a number, convert it to text first using `toString`: `"Port: ${toString 8080}"`.

**Multi-line text (`'' ''`):**
When you need to write a whole config file or a multi-line script inside Nix, use two single quotes (`''`) at the start and end instead of double quotes.
* **How it looks:**
  ```nix
  ''
    set -g mouse on
    set -g status off
  ''
  ```
* **As a result:** Nix keeps the line breaks and automatically strips the shared leading spaces on the left so your config file stays neat.
* **Tip (Escaping `${` in scripts):** If you are writing a shell script inside `'' ''` and need a literal `${VAR}` for Bash instead of Nix, put two single quotes in front of it: `''${VAR}`. A plain `$VAR` without curly braces needs no escaping.

### 2. Yes/No Switches (`true` and `false`) and `null`
* **`true` / `false`:** Used for turning features on or off (`programs.git.enable = true;`).
* **`null`:** Represents "nothing" or "unset" (useful when an option is optional).

### 3. File Paths (No Quotes!)
When you want Nix to grab a real file or folder from your repo (like a custom configuration file), write the path **without quotes**. It must always contain a slash (`/`).

* **Where it goes:** Pointing Home Manager to a dotfile in your folder.
* **How it looks:** `./kitty.conf` (The `.` means "right here in the current folder"; `..` means "one folder up").
* **Why no quotes?** If you write `"./kitty.conf"` with quotes, Nix treats it as plain text, not a real file, and will not copy it into `/nix/store`.

### 4. Lists (`[ ]`)
A list is an ordered group of items inside square brackets. **Items are separated by spaces, never commas.**

* **Where it goes:** Installing a list of packages or importing multiple files.
* **How it looks:**
  ```nix
  home.packages = [ pkgs.tree pkgs.git pkgs.ripgrep ];
  ```
* **Joining two lists (`++`):** Use `++` to glue two lists together: `[ pkgs.git ] ++ [ pkgs.tree ]`.
* **Tip (Function calls inside lists):** Because spaces separate list items, `[ f x ]` means a list of two items (`f` and `x`). If you call a helper function inside a list, wrap it in parentheses: `[ (f x) ]`. Dotted names like `pkgs.git` stay together as one item automatically.

### 5. Attribute Sets (`{ }`) — The Most Important One
An attribute set (usually just called a **set**) is a group of labelled settings inside curly braces. Think of it like a form with named boxes.

* **The Golden Rule:** Every single line inside `{ }` **must end with a semicolon (`;`)**. Forgetting a semicolon is the #1 cause of errors in Nix.
* **How it looks:**
  ```nix
  {
    username = "root";
    homeDirectory = "/root";
  }
  ```

**The Dotted Shortcut:**
Instead of putting sets inside of sets, you can use dots to save space. Both of these do the exact same thing:
```nix
# Nested version:
programs = {
  git = {
    enable = true;
  };
};

# Dotted shortcut (much cleaner):
programs.git.enable = true;
```

**Checking and Fallbacks (`?` and `or`):**
* `{ x = 1; } ? x` checks if `x` exists in the set (returns `true`).
* `{ x = 1; }.z or "fallback"` tries to read `z`, and safely returns `"fallback"` if `z` is missing instead of crashing.

**Merging two sets (`//`):**
If you have two sets and want to combine them, use `//`. If both sets have the same label, the one on the right wins:
```nix
{ a = 1; b = 2; } // { b = 99; }
# Result: { a = 1; b = 99; }
```
*(Note: `//` only merges the top level. Home Manager's module system merges nested sets deeply, which is why splitting configs across files works so smoothly.)*

---

## 3. Giving Things Nicknames (`let ... in`)

Sometimes you want to define a value once at the top of your file and reuse it in several places below. You use `let` and `in` for this.

* **Where it goes:** Right before your main `{ }` set of settings.
* **How it looks:**
  ```nix
  let
    myUser = "root";
    myEditor = "nvim";
  in {
    home.username = myUser;
    home.homeDirectory = "/${myUser}";
    home.sessionVariables.EDITOR = myEditor;
  }
  ```
* **How to read it:** *"Let `myUser` mean `"root"` and `myEditor` mean `"nvim"`. Now, use those nicknames in the settings below."*
* **Tips:**
  * Every nickname inside `let` ends with a semicolon (`;`).
  * Nothing goes after `in` except your main `{ }` block.
  * Nicknames inside `let` can reference each other in any order (`b = a + 1; a = 1;` works fine).

---

## 4. Functions (Why Files Start With `{ pkgs, ... }:`)

Almost every Home Manager file starts with a line that looks like `{ pkgs, ... }:`. To someone new to code, this looks intimidating, but it is just a **reception desk**.

A **function** is a machine that takes an input on the left of a colon (`:`), and produces an output on the right of the colon.

* **How it looks:**
  ```nix
  { config, lib, pkgs, ... }: {
    home.packages = [ pkgs.tree ];
  }
  ```
* **Oh! So this is what happens:**
  1. When you run `home-manager switch`, Home Manager hands your file a big box of tools containing `pkgs` (all available software), `lib` (helper tools), and `config` (your finished settings).
  2. The `{ config, lib, pkgs, ... }:` header at the top is you saying: *"Out of that big box you're handing me, I only want to take out `config`, `lib`, and `pkgs`. Ignore everything else (`...`)."*
  3. After the colon (`:`), you write your `{ ... }` set of settings using those tools.
  4. **The Catch:** If you use `pkgs.tree` inside your file, you **must** list `pkgs` in that top `{ pkgs, ... }:` header. If you forget, Nix will say `undefined variable 'pkgs'` because you didn't ask for it at the reception desk.

*(Note: Inside that `{ pkgs, ... }:` header, names are separated by **commas**, not semicolons! You can also give an input a fallback default with `?`, like `{ host ? "termux", pkgs, ... }:`.)*

---

## 5. Making Decisions (`if ... then ... else`)

When you want a setting to change depending on a condition (like which device you are on), use `if ... then ... else`.

* **How it looks:**
  ```nix
  { host, pkgs, ... }: {
    home.packages =
      if host == "termux"
      then [ pkgs.tree ]
      else [ ];
  }
  ```
* **How to read it:** *"If the `host` is `"termux"`, install `tree`. Otherwise (`else`), give an empty list (`[ ]`)."*
* **Important Rules:**
  * You must **always** include `else`.
  * `==` (two equals signs) checks if two things match; `!=` checks if they do *not* match; `=` (one equals sign) sets a value.
  * Combine conditions with `&&` (AND), `||` (OR), and `!` (NOT).

---

## 6. Two Handy Shortcuts (`with` and `inherit`)

You will see these two words constantly in Nix configs. They exist solely to save you from typing the same words over and over.

### `with` (Stop repeating `pkgs.`)
Instead of typing `pkgs.` before every single program in a long list:
```nix
# Without 'with':
home.packages = [ pkgs.tree pkgs.ripgrep pkgs.fd ];

# With 'with':
home.packages = with pkgs; [ tree ripgrep fd ];
```
`with pkgs;` tells Nix: *"For everything inside these brackets, look inside `pkgs` automatically."*
*(Tip: Keep `with` scoped to a single list like `home.packages = with pkgs; [ ... ];` rather than at the top of a whole file, so it stays obvious where names come from.)*

### `inherit` (Stop typing `name = name;`)
When you already have a nickname defined and want to put it into a set with the exact same label:
```nix
let
  system = "aarch64-linux";
in {
  inherit system; # Shortcut for: system = system;
}
```
You can also pull things out of another set using parentheses:
```nix
inherit (pkgs) git tree; # Shortcut for: git = pkgs.git; tree = pkgs.tree;
```

---

## 7. Built-in Helpers You Will Actually Use

Nixpkgs includes a helper library called `lib` (which you ask for in `{ lib, pkgs, ... }:`). These four helpers appear in almost every Home Manager setup:

| Helper | What it does | Practical Example |
| :--- | :--- | :--- |
| `lib.mkIf cond { ... }` | Applies settings only when `cond` is true | `lib.mkIf (host == "termux") { home.packages = [ pkgs.tree ]; }` |
| `lib.optionals cond [ ... ]` | Includes list items only when `cond` is true | `[ pkgs.git ] ++ lib.optionals (host == "termux") [ pkgs.tree ]` |
| `lib.mkDefault val` | Sets a weak fallback that other files can override | `home.sessionVariables.EDITOR = lib.mkDefault "nvim";` |
| `lib.mkForce val` | Forces a value to override everything else | `programs.git.settings.init.defaultBranch = lib.mkForce "trunk";` |

---

## 8. Anatomy of a Real Home Manager File

Now put everything together and read a complete `home.nix` file from top to bottom:

```nix
# 1. Reception desk: ask Home Manager for 'config' and 'pkgs'
{ config, pkgs, ... }:

# 2. Nicknames: define reusable values
let
  user = "root";
in {
  # 3. Settings: fill out the Home Manager order form
  home.username = user;
  home.homeDirectory = "/${user}";
  home.stateVersion = "26.05";

  # Install packages using the 'with' shortcut
  home.packages = with pkgs; [
    tree
    ripgrep
  ];

  # Turn on Git and set your name using the dotted shortcut
  programs.git = {
    enable = true;
    settings.user.name = "Alex";
  };

  # Set environment variables, reusing your homeDirectory setting
  home.sessionVariables = {
    EDITOR = "nvim";
    PROJECTS = "${config.home.homeDirectory}/projects";
  };
}
```

---

## 9. Symbol Cheat Sheet

Keep this table handy whenever a line of Nix looks confusing:

| Symbol | What it means | Example |
| :--- | :--- | :--- |
| `=` | Assign a value to a label | `enable = true;` |
| `;` | Ends a setting inside `{ }` or a nickname inside `let` | `user = "root";` |
| `:` | Separates a function's inputs (left) from its output (right) | `{ pkgs, ... }: { ... }` |
| `,` | Separates input names inside `{ pkgs, ... }:` headers only | `{ config, pkgs }:` |
| `{ }` | A set of labelled settings | `{ a = 1; b = 2; }` |
| `[ ]` | A list of items (separated by spaces) | `[ "a" "b" "c" ]` |
| `${ }` | Inserts a value inside double-quoted text | `"/home/${user}"` |
| `++` | Joins two lists together | `[ 1 ] ++ [ 2 ]` |
| `//` | Merges two sets together | `{ a = 1; } // { b = 2; }` |
| `#` | A comment (Nix ignores everything after `#` on that line) | `# My git settings` |

---

## 10. Common Errors and How to Fix Them

| Error Message | What actually happened | How to fix it |
| :--- | :--- | :--- |
| `syntax error, unexpected ...` | You forgot a semicolon `;` on the line right above, or forgot to close a `}` or `]`. | Check the line above the error and add `;`. |
| `undefined variable 'pkgs'` | You used `pkgs` in your file, but forgot to ask for it at the top. | Add `pkgs` to `{ pkgs, ... }:` on line 1. |
| `cannot coerce an integer to a string` | You put a number inside `${ }` without turning it into text first. | Wrap the number like this: `${toString 30}`. |
| `called with unexpected argument` | A function was handed extra info and didn't have `...` to ignore it. | Add `, ...` inside the `{ ... }:` header. |
| `a-b` acts like a single word | Nix allows hyphens in variable names, so `a-b` is read as one name. | Put spaces around minus signs: `a - b`. |