# The Nix language from zero

This guide assumes you have never written code. The goal is that after reading it you can open a `flake.nix` or a `home.nix` and understand what each piece means and where new things go.

Contents

0. The big idea, and how to try things
1. Values: numbers, text, lists, sets
2. Naming things with `let`
3. Functions
4. Making decisions
5. Shortcuts: `with` and `inherit`
6. Built-in helpers
7. Files and `import`
8. Laziness
9. Reading real files
10. Symbol cheat sheet and "what goes where"
11. Common mistakes and what the errors mean
12. Practice

---

## 0. The big idea, and how to try things

Most programming languages give the computer a list of steps: do this, then that. Nix doesn't. A Nix file **describes** something, and Nix works out the result.

Think of a spreadsheet cell. You type `=1+2` and the cell shows `3`. You never tell it how to add. Nix works the same way:

- A Nix file holds exactly **one expression**. An expression is a piece of text that boils down to one **value**: a number, some text, a list, and so on.
- Working out that value is called **evaluating**.
- Everything is an expression. There are no "do this, then do that" instructions.
- Nix is **lazy**. It only works out a value when something actually needs it.

### Try it yourself

Everything in this guide can be tried live. Start the interactive prompt (called the repl):

```sh
nix repl
```

Type an expression, press Enter, and Nix prints its value:

```text
nix-repl> 1 + 2
3
nix-repl> "hello"
"hello"
nix-repl> :q
```

`:q` quits. You can also give a name to a value in the repl and use it later:

```text
nix-repl> x = 5
nix-repl> x * 2
10
```

For one-off checks without opening the repl:

```sh
nix eval --expr '1 + 2'
nix-instantiate --eval -E '1 + 2'
```

For longer snippets, save them in a file called `test.nix` and run:

```sh
nix eval --file test.nix
```

### Words you'll see

| Word | Plain meaning |
| --- | --- |
| Expression | A piece of Nix text that has a value |
| Value | The result: a number, text, list, set, function... |
| Evaluate | Work out the value of an expression |
| Attribute | One labelled field inside a set |
| Set | A group of labelled values, like a form with fields |
| Function | A machine that takes something in and gives something back |
| Argument | The thing you hand to a function |
| Scope | Which names are visible at a given spot in the file |

---

## 1. Values

Values are the building blocks. Everything in a Nix file is made of these.

### 1.1 Numbers

| You write | You get |
| --- | --- |
| `1 + 2` | `3` |
| `10 - 4` | `6` |
| `3 * 4` | `12` |
| `1.5 + 1` | `2.5` |

Put spaces around the minus sign. In Nix, `a-b` with no spaces is a single name, not a subtraction.

### 1.2 Strings (text)

Text goes in double quotes:

```nix
"hello"
```

Join two pieces of text with `+`:

| You write | You get |
| --- | --- |
| `"foo" + "bar"` | `"foobar"` |

**Fill in the blank with `${ }`.** Inside quotes, `${...}` is replaced by the value of whatever is inside it:

```text
nix-repl> name = "Alex"
nix-repl> "Hello, ${name}!"
"Hello, Alex!"
```

Only text can go into `${ }`. A number must be converted with `toString` first:

```nix
"I am ${toString 30} years old"
```

Without `toString`, Nix stops with an error about not being able to coerce an integer to a string.

**Multi-line text** uses two single quotes (not double quotes) at each end:

```nix
''
  first line
  second line
''
```

Nix strips the shared indentation, so you can indent the text to match your code. You'll see this form constantly, for config files and shell scripts inside Nix files.

One catch: `${` inside a multi-line string is read as a blank to fill in. To write a literal `${`, put two single quotes in front: `''${HOME}`. A plain `$HOME` with no braces needs no escape.

### 1.3 True, false, null and comparisons

- `true` and `false` are the yes/no values.
- `null` means "nothing here".

| You write | You get |
| --- | --- |
| `1 == 1` | `true` |
| `1 != 2` | `true` |
| `3 > 2` | `true` |
| `!true` | `false` |

Combine yes/no values with `&&` (and), `||` (or), and `!` (not). `true && false` is `false`, and `true || false` is `true`.

Note `==` asks "are these equal?" and gives true or false. A single `=` is not a comparison. It gives something a name, as you'll see below.

### 1.4 Paths

A path points to a file or folder. It has **no quotes** and always contains a slash:

```nix
./kitty.conf
./modules/git.nix
```

A path starting with `./` is relative to the file you wrote it in. Nix turns it into a full path when evaluating.

`"./kitty.conf"` with quotes is just text that happens to look like a path. It won't work where Nix expects a real path.

When a path is used where a file is needed (for instance as a file's `source` in Home Manager), Nix copies that file into the Nix store.

### 1.5 Lists

A list is an ordered collection in square brackets. **Items are separated by spaces, not commas**:

```nix
[ 1 2 3 ]
[ "red" "green" "blue" ]
```

Join two lists with `++`:

| You write | You get |
| --- | --- |
| `[ 1 2 ] ++ [ 3 ]` | `[ 1 2 3 ]` |

The classic beginner trap: inside a list, each space starts a **new item**. So this is a list of two things, the function `f` and the value `x`, not the result of calling `f` on `x`:

```nix
[ f x ]
```

To call a function inside a list, wrap the call in parentheses:

```nix
[ (f x) ]
```

Dotted names like `pkgs.git` are fine without parentheses, because the dot ties them into one item:

```nix
[ pkgs.git pkgs.tree ]
```

### 1.6 Attribute sets (the most important one)

An attribute set, or just **set**, is a group of labelled values. Think of a form with named fields:

```nix
{
  name = "Alex";
  age = 30;
  tools = [ "git" "tree" ];
}
```

Each field is `label = value;`. **Every field ends with a semicolon.** Forgetting one is the number one cause of syntax errors.

Read a field with a dot:

| You write | You get |
| --- | --- |
| `{ x = 1; y = 2; }.x` | `1` |

Sets can sit inside sets:

```nix
{
  person = {
    name = "Alex";
  };
}
```

**The dotted shortcut.** This is the same thing, written flat:

```nix
{
  person.name = "Alex";
}
```

`person.name = "Alex";` means "inside `person`, set `name`". Home Manager configs use this all the time: `home.username = "root";` is the same as `home = { username = "root"; };`.

**Missing fields.** Reading a field that doesn't exist is an error. Give a fallback with `or`:

| You write | You get |
| --- | --- |
| `{ x = 1; }.z or 3` | `3` |

Test whether a field exists with `?`:

| You write | You get |
| --- | --- |
| `{ x = 1; } ? x` | `true` |

**Merging with `//`.** The right side wins when both have the same field:

| You write | You get |
| --- | --- |
| `{ x = 1; y = 2; } // { z = 3; }` | `{ x = 1; y = 2; z = 3; }` |

Careful: this is a shallow merge. If both sides have a field that is itself a set, the right side replaces the whole thing instead of combining:

```nix
{ a = { x = 1; }; } // { a = { y = 2; }; }
```

gives `{ a = { y = 2; }; }`, and the `x` is gone. Home Manager's module system merges deeply instead, which is one reason it's so convenient.

**`rec` sets.** Normally a field can't see its neighbours. Writing `rec` in front allows it:

```nix
rec {
  a = 10;
  b = a * 2;
}
```

gives `{ a = 10; b = 20; }`. Most people prefer `let` (next section) instead.

---

## 2. Naming things with let

`let ... in ...` gives names to values so you can reuse them:

```nix
let
  name = "Alex";
  greeting = "Hello";
in
"${greeting}, ${name}!"
```

Result: `"Hello, Alex!"`.

How to read it:

1. Between `let` and `in` you list names, each written `name = value;` with a semicolon.
2. After `in` comes the expression that gets the final result, and it can use those names.
3. The names exist only inside this `let`. Outside it, they're invisible.

Names can use each other, and order doesn't matter:

```nix
let
  b = a + 1;
  a = 1;
in
b
```

gives `2`.

The result after `in` has no semicolon. A semicolon appears only after fields inside `{ }` and after names inside `let`.

### Comments

Everything after `#` on a line is ignored by Nix. Use it for notes to yourself. Longer notes go between `/*` and `*/`:

```nix
# this is a note
/* this is a
   longer note */
```

---

## 3. Functions

A function is a small machine: you hand it something, and it gives something back.

### 3.1 One argument

```nix
x: x + 1
```

Read it as: "a function that takes `x` and gives back `x + 1`". The colon is the key symbol. **Whatever is to the left of the colon is the input; whatever is to the right is the output.**

To use a function, write it, then a space, then the thing you give it:

| You write | You get |
| --- | --- |
| `(x: x + 1) 100` | `101` |

With a name:

```nix
let
  double = x: x * 2;
in
double 4
```

gives `8`. There are no parentheses and no commas for calling. `double 4` is the whole call.

A call binds tighter than anything else, so `double 4 + 1` means `(double 4) + 1`, which is `9`.

Use parentheses when you need to group, like nesting one call in another: `double (double 4)` gives `16`.

### 3.2 More than one argument

Write the arguments one after another, each with its own colon:

```nix
let
  add = a: b: a + b;
in
add 1 2
```

gives `3`. Technically this is a function that takes `a` and returns another function that takes `b`, but you can ignore that and read `a: b: a + b` as "takes a and b".

### 3.3 A set as the argument (the form you'll see most)

Instead of separate arguments, a function can take **one set** and pick out fields by name:

```nix
{ name, greeting }: "${greeting}, ${name}!"
```

Read it as: "a function that takes a set with fields `name` and `greeting`, and uses them".

To call it, hand it a set:

```nix
let
  greet = { name, greeting }: "${greeting}, ${name}!";
in
greet { name = "Alex"; greeting = "Hi"; }
```

gives `"Hi, Alex!"`.

Three extras:

- **Defaults** use `?`. `{ name, greeting ? "Hello" }:` makes `greeting` optional.
- **`...`** means "the set may contain other fields too; ignore them". Without it, handing in an extra field is an error.
- **`@`** gives a name to the whole set as well: `args@{ name, ... }:` lets you use both `name` and `args`.

```nix
let
  greet = { name, greeting ? "Hello", ... }: "${greeting}, ${name}!";
in
greet { name = "Alex"; extra = 1; }
```

gives `"Hello, Alex!"`.

In the header, the names are separated by **commas**. There's no comma after the last one (and none after `...`). This is different from lists, which use spaces, and sets, which use semicolons.

### 3.4 Why every config file starts with `{ pkgs, ... }:`

Now you can read the first line of almost every Home Manager and NixOS file:

```nix
{ config, lib, pkgs, ... }: {
  home.packages = [ pkgs.git ];
}
```

This whole file is **one function**. The header `{ config, lib, pkgs, ... }:` says: "I take a set, and I want the fields called `config`, `lib` and `pkgs` out of it. Ignore the rest." After the colon comes the output, which is a set of settings.

Home Manager calls your function for you and hands in a set containing `config`, `lib`, `pkgs` and more. You list in the header only what you plan to use. If you use `pkgs` in the body but forget it in the header, Nix says `undefined variable 'pkgs'`.

---

## 4. Making decisions

`if ... then ... else ...` picks between two values:

| You write | You get |
| --- | --- |
| `if 1 + 1 == 2 then "yes" else "no"` | `"yes"` |

The `else` is required. Every `if` must give back a value, so both sides need one.

A common use is choosing something based on a name:

```nix
{ host, pkgs, ... }: {
  home.packages =
    if host == "termux"
    then [ pkgs.tree ]
    else [ ];
}
```

`[ ]` is an empty list, a good "nothing" value for a list.

---

## 5. Shortcuts: with and inherit

### 5.1 inherit

`inherit` copies a name from the surrounding scope into a set (or `let`) with the same name, saving typing:

```nix
let
  name = "Alex";
  age = 30;
in {
  inherit name age;
}
```

This is the same as `name = name; age = age;`. The result is `{ name = "Alex"; age = 30; }`.

Copy fields out of another set by putting that set in parentheses:

```nix
inherit (pkgs) git tree;
```

That means `git = pkgs.git; tree = pkgs.tree;`.

### 5.2 with

`with` makes every field of a set available without the prefix:

```nix
with pkgs; [ git tree ripgrep ]
```

is the same as `[ pkgs.git pkgs.tree pkgs.ripgrep ]`. It reads nicely for long package lists. The downside is that when you see a bare name like `git`, it's not obvious where it came from. For short lists, writing `pkgs.git` is clearer.

---

## 6. Built-in helpers

Nix comes with a toolbox of ready-made functions. Most live under the name `builtins`, so you write `builtins.length`. A few are also available without the prefix: `map`, `import` and `toString`.

| You write | You get |
| --- | --- |
| `map (x: x * 2) [ 1 2 3 ]` | `[ 2 4 6 ]` |
| `builtins.filter (x: x > 1) [ 1 2 3 ]` | `[ 2 3 ]` |
| `builtins.length [ 1 2 3 ]` | `3` |
| `builtins.elem 2 [ 1 2 3 ]` | `true` |
| `builtins.attrNames { b = 1; a = 2; }` | `[ "a" "b" ]` |
| `builtins.concatStringsSep ", " [ "a" "b" ]` | `"a, b"` |
| `toString 5` | `"5"` |

How to read `map (x: x * 2) [ 1 2 3 ]`: `map` is a function that takes two things, first a function and then a list. It runs the function on every item and gives back the new list. Here the function is `x: x * 2`, "take x, give back x times 2".

### The lib toolbox

Nixpkgs ships a second, larger toolbox called `lib`. In Home Manager and NixOS files you get it by listing `lib` in the header, then writing `lib.something`. Four you'll meet constantly:

| Helper | What it does |
| --- | --- |
| `lib.mkIf cond { ... }` | Use these settings only when `cond` is true |
| `lib.mkDefault value` | A weak value that other settings can override |
| `lib.mkForce value` | A strong value that wins over others |
| `lib.optionals cond list` | The list if `cond` is true, otherwise `[ ]` |

For example:

```nix
{ lib, pkgs, host, ... }: {
  home.packages = [ pkgs.git ] ++ lib.optionals (host == "termux") [ pkgs.tree ];
}
```

On the machine called `termux`, the list becomes `git` and `tree`. On any other machine it's just `git`.

---

## 7. Files and import

Each `.nix` file holds exactly one expression. To use the value of another file, load it with `import`.

If `double.nix` contains:

```nix
x: x * 2
```

then:

| You write | You get |
| --- | --- |
| `import ./double.nix 21` | `42` |

`import ./double.nix` gives back the function, and `21` is handed to it.

If `settings.nix` contains a set:

```nix
{ editor = "nvim"; }
```

then to read a field from it, wrap the import in parentheses:

```nix
(import ./settings.nix).editor
```

which gives `"nvim"`.

### import versus imports

These look alike but are different things:

| | What it is | Where you see it |
| --- | --- | --- |
| `import` | A language function that loads one file and gives you its value | Anywhere in Nix code |
| `imports` | A list of module files that Home Manager or NixOS merges into your config | A field inside a module |

```nix
{
  imports = [ ./git.nix ./shell.nix ];
}
```

Here `imports` is just a normal field with a list of paths. Home Manager itself reads that field and loads those files for you. You rarely need `import` yourself in a Home Manager config.

---

## 8. Laziness

Nix only works out a value when something needs it. This is a big difference from most languages:

```nix
let
  broken = abort "this would stop everything";
  fine = 5;
in
fine
```

The result is `5`. `broken` would cause an error if it were ever used, but nothing uses it, so Nix never evaluates it.

What this means for you:

- An error can hide in a part of your config until something actually uses it.
- Code you've written but never connected to anything won't produce errors.
- Nix can describe huge things, like all of nixpkgs, and only work out the few pieces you ask for.

---

## 9. Reading real files

### A Home Manager file

```nix
{ config, lib, pkgs, ... }:
let
  user = "root";
in {
  home.username = user;
  home.homeDirectory = "/${user}";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    tree
    ripgrep
  ];

  programs.git = {
    enable = true;
    settings.user.name = "Alex";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    PROJECTS = "${config.home.homeDirectory}/projects";
  };
}
```

Going through it piece by piece:

- `{ config, lib, pkgs, ... }:` is the function header. The whole file is a function that takes a set and picks out `config`, `lib` and `pkgs`.
- `let user = "root"; in` gives the name `user` the value `"root"`, for use below.
- `in {` starts the output. Everything from this brace to the final `}` is one set of settings.
- `home.username = user;` uses the dotted shortcut. The value is the name `user`, which Nix replaces with `"root"`.
- `home.homeDirectory = "/${user}";` is text with a blank filled in, giving `"/root"`.
- `home.packages = with pkgs; [ ... ];` is a list. `with pkgs;` lets you write `tree` instead of `pkgs.tree`. Items are separated by spaces, one per line here.
- `programs.git = { ... };` is a nested set. It ends in `};` because it's a field, and fields end with semicolons.
- `home.sessionVariables = { ... };` is another nested set. `${config.home.homeDirectory}` reads another setting from the finished config.
- The last `}` closes the output set. There's no semicolon after it.

### Where do names like home.packages come from?

You don't invent them. They're **options** that Home Manager defines, a bit like labelled boxes on a form. Your job is to fill in the boxes with the right kind of value:

| Option | Kind of value | Example |
| --- | --- | --- |
| `home.packages` | A list | `[ pkgs.tree ]` |
| `home.username` | Text | `"root"` |
| `programs.git.enable` | true or false | `true` |
| `programs.git.settings` | A set | `{ user.name = "Alex"; }` |
| `home.sessionVariables` | A set of text | `{ EDITOR = "nvim"; }` |

If you give a box the wrong kind of value, Nix reports an error naming the option and the kind of value it expected.

### A flake

```nix
{
  description = "My config";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
    in {
      packages.aarch64-linux.default = pkgs.hello;
    };
}
```

- The whole file is one set with three fields: `description`, `inputs` and `outputs`.
- `inputs.nixpkgs.url = "...";` is the dotted shortcut for `inputs = { nixpkgs = { url = "..."; }; };`.
- `outputs` is a **function**. Its header `{ self, nixpkgs, ... }:` says "give me a set, I'll take `self` and `nixpkgs` out of it". Nix calls this function for you, handing in the resolved inputs.
- After the colon, `let ... in { ... }` names `pkgs`, then produces the output set.
- `packages.aarch64-linux.default` is a three-level dotted path. `aarch64-linux` is a valid name even though it contains a hyphen.
- The field `outputs = ...;` ends with a semicolon, because it's a field of the outer set.

---

## 10. Symbol cheat sheet and "what goes where"

### What each symbol means

| Symbol | Meaning | Example |
| --- | --- | --- |
| `=` | Give a field or name a value | `x = 5;` |
| `;` | Ends a field in a set, or a name in a `let` | `x = 5;` |
| `:` | Function: input on the left, output on the right | `x: x + 1` |
| `,` | Separates names in a function's `{ }` header only | `{ a, b }:` |
| `{ }` | A set, or a function's input pattern before a colon | `{ a = 1; }` |
| `[ ]` | A list, items separated by spaces | `[ 1 2 3 ]` |
| `( )` | Group things together | `[ (f x) ]` |
| `" "` | Text | `"hello"` |
| `'' ''` | Multi-line text | |
| `${ }` | Fill in a value inside text | `"Hi ${name}"` |
| `.` | Open a field, or a dotted path | `a.b.c` |
| `//` | Merge two sets, right side wins, shallow | `a // b` |
| `++` | Join two lists | `[ 1 ] ++ [ 2 ]` |
| `+` | Add numbers or join text | `1 + 2` |
| `==` | Are these equal? | `a == b` |
| `?` | Default for a function field, or a "has field" test | `{ a ? 1 }:` |
| `...` | Accept extra fields | `{ a, ... }:` |
| `@` | Name the whole set | `args@{ a, ... }:` |
| `#` | Comment | `# note` |

### The rules in one place

1. **A file is one expression.** In practice, usually a function header, then maybe a `let` block, then a set of settings.
2. **Order matters at the top.** The header `{ ... }:` comes first, `let ... in` comes next, and the final `{ ... }` set comes last.
3. **Every field in a set ends with `;`.** This includes fields whose value is another set, which end in `};`.
4. **Lists use spaces, not commas.** Wrap function calls inside lists in parentheses.
5. **Function headers use commas** between names, and no comma after the last one.
6. **Setting a Home Manager option** is: dotted path, `=`, value, `;`. Like `programs.git.enable = true;`.
7. **A name must be in scope to be used.** Names come from the function header, a `let` block, or a `with`.
8. **Paths have no quotes. Text always does.**
9. **To use a value inside text**, write `${...}`.
10. **The last expression has no semicolon.** After `in` and at the very end of a file, nothing follows the closing brace.

---

## 11. Common mistakes and what the errors mean

| What you see | Usual cause | Fix |
| --- | --- | --- |
| `syntax error, unexpected ...` | A missing `;` on the line before, or a bracket that never closed | Check the previous field's semicolon and match every `{`, `[` and `(` |
| `undefined variable 'pkgs'` | The name isn't in scope | Add it to the function header or a `let` |
| `attribute 'x' missing` | That field doesn't exist in the set | Check spelling, or give a fallback with `or` |
| `cannot coerce an integer to a string` | A number inside `${ }` | Wrap it: `${toString n}` |
| A list does the wrong thing | `[ f x ]` is two items | Write `[ (f x) ]` |
| `called with unexpected argument 'x'` | A set with an extra field went into a function with no `...` | Add `...` to the header |
| `called without required argument 'x'` | A needed field is missing | Provide it, or give it a default with `?` |
| `infinite recursion encountered` | A value is defined in terms of itself | Check `rec` sets and names that depend on each other |
| An error naming an option and a type | You gave an option the wrong kind of value | Check the options reference for its type |
| `a-b` acts like one name | No spaces around the minus | Write `a - b` |

Two habits that help:

- Nix reports the file and line where it got confused. For a missing semicolon, the actual mistake is often on the line above.
- For deep errors, add `--show-trace` to the command to see where the problem came from.

---

## 12. Practice

Try these in `nix repl` before looking at the answers.

1. Write a function that takes `name` and returns `"Hello, <name>!"`.
2. Using `let`, make a set with `a = 1`, `b = 2`, and `c` equal to `a + b`.
3. What's wrong with these two snippets?

```nix
[ pkgs.git, pkgs.tree ]
```

```nix
{ name = "x" age = 3; }
```

4. Double every number in `[ 1 2 3 ]`.
5. Write a Home Manager style file that installs `tree` and sets `EDITOR` to `"nvim"`.

### Answers

1. `name: "Hello, ${name}!"`. To test it: `(name: "Hello, ${name}!") "Alex"`.
2. `let a = 1; b = 2; in { inherit a b; c = a + b; }`, which gives `{ a = 1; b = 2; c = 3; }`.
3. The list has a comma, and lists use spaces only: `[ pkgs.git pkgs.tree ]`. The set is missing the semicolon after `"x"`: `{ name = "x"; age = 3; }`.
4. `map (x: x * 2) [ 1 2 3 ]`, which gives `[ 2 4 6 ]`.
5. This one:

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.tree ];
  home.sessionVariables.EDITOR = "nvim";
}
```

---

## Where to go next

You now have the whole language in miniature. Next, `flakes-home-manager-explained.md` and `flakes-home-manager-in-depth.md` show how these pieces fit into real flake and Home Manager setups. Whenever a snippet there looks unfamiliar, come back to section 10 to decode it.
