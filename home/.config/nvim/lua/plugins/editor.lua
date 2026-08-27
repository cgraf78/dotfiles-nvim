return {
  -- LazyVim's core distribution includes development services even when no
  -- language extras are selected. Keep the editor capability network- and
  -- toolchain-independent; dotfiles-dev re-enables these specs additively.
  { "neovim/nvim-lspconfig", enabled = false },
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "stevearc/conform.nvim", enabled = false },
  { "mfussenegger/nvim-lint", enabled = false },
  { "folke/lazydev.nvim", enabled = false },

  -- Disable snacks features that conflict with terminal rendering or feel laggy
  -- over SSH (smooth scroll, animations, startup dashboard).
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
      scroll = { enabled = false },
      animate = { enabled = false },
    },
  },

  {
    "mbbill/undotree",
    keys = {
      { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle undo tree" },
    },
  },
}
