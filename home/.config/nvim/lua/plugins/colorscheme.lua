-- NVIM_COLORSCHEME lets shell profiles switch themes without editing this file.
-- Only the active colorscheme is eager-loaded; the rest are lazy to avoid startup cost.
local colorscheme = vim.env.NVIM_COLORSCHEME or "night-owl"

return {
  { "LazyVim/LazyVim", opts = { colorscheme = colorscheme } },

  {
    "folke/tokyonight.nvim",
    opts = {
      style = "storm",
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        sidebars = "normal",
        floats = "dark",
      },
    },
  },

  {
    "ellisonleao/gruvbox.nvim",
    lazy = colorscheme ~= "gruvbox",
    priority = 1000,
    opts = { contrast = "hard" },
    config = function(_, opts)
      require("gruvbox").setup(opts)
      if colorscheme == "gruvbox" then
        vim.cmd("colorscheme gruvbox")
      end
    end,
  },

  {
    "oxfist/night-owl.nvim",
    lazy = colorscheme ~= "night-owl",
    priority = 1000,
    config = function()
      if colorscheme == "night-owl" then
        -- night-owl ships without good defaults for indent guides, whitespace,
        -- render-markdown headings, and diff backgrounds. Override them and
        -- re-apply on ColorScheme events so :colorscheme reloads don't lose the
        -- fixes.
        local dim = "#384050"
        local overrides = {
          CursorLine = { bg = "#0b2942" },
          DiffAdd = { bg = "#304531" },
          DiffChange = { bg = "#1c403d" },
          DiffDelete = { bg = "#3f1624" },
          DiffText = { bg = "#2d594b" },
          SnacksIndent = { fg = dim },
          SnacksIndentScope = { fg = dim },
          Whitespace = { fg = dim },
          RenderMarkdownH1Bg = { bg = "#1d3b53" },
          RenderMarkdownH2Bg = { bg = "#112630" },
          RenderMarkdownH3Bg = { bg = "#0e293f" },
          RenderMarkdownH4Bg = { bg = "#0b253a" },
          RenderMarkdownH5Bg = { bg = "#092135" },
          RenderMarkdownH6Bg = { bg = "#071d30" },
        }
        local function apply()
          for group, hl in pairs(overrides) do
            vim.api.nvim_set_hl(0, group, hl)
          end
        end
        vim.cmd("colorscheme night-owl")
        apply()
        vim.api.nvim_create_autocmd("ColorScheme", {
          pattern = "night-owl",
          callback = apply,
        })
      end
    end,
  },

  {
    "rebelot/kanagawa.nvim",
    lazy = colorscheme ~= "kanagawa",
    priority = 1000,
    opts = {
      theme = "wave",
      background = { dark = "wave", light = "lotus" },
    },
    config = function(_, opts)
      require("kanagawa").setup(opts)
      if colorscheme == "kanagawa" then
        vim.cmd("colorscheme kanagawa-wave")
      end
    end,
  },

  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = colorscheme ~= "oxocarbon",
    priority = 1000,
    config = function()
      if colorscheme == "oxocarbon" then
        vim.cmd("colorscheme oxocarbon")
      end
    end,
  },

  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = colorscheme ~= "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = { gitsigns = true, treesitter = true },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      if colorscheme == "catppuccin" then
        vim.cmd("colorscheme catppuccin")
      end
    end,
  },
}
