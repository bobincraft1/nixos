{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;

    plugins = with pkgs.vimPlugins; [
      # Gruvbox theme (Lua port)
      {
        plugin = gruvbox-nvim;
        type = "lua";
        config = ''
          require("gruvbox").setup({
            contrast = "", -- options: "hard", "soft", or "" (medium)
            transparent_mode = false,
          })
          vim.o.background = "dark" -- or "light"
          vim.cmd([[colorscheme gruvbox]])
        '';
      }

      # Indent guides (indent-blankline v3)
      {
        plugin = indent-blankline-nvim;
        type = "lua";
        config = ''
          require("ibl").setup({
            indent = { char = "│" },
            scope = { enabled = true },
          })
        '';
      }
    ];
  };
}
