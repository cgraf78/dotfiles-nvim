-- The VSCode-style keymaps in config/keymaps/vscode.lua are set on VeryLazy,
-- over the stub mappings lazy.nvim installs for each plugin spec key. When a
-- plugin later loads, lazy.nvim replaces every one of its spec keys with the
-- real mapping, which silently reverted the VSCode binding on first use.
-- Dropping the conflicting spec keys (lazy.nvim's `{ lhs, false, mode = ... }`
-- form) lets the VSCode bindings win; each plugin's other keys are untouched.
--
-- `optional = true` keeps these fragments from adding a plugin whose LazyVim
-- extra is not enabled. A later spec that re-adds one of these keys would win
-- again; nvim-test's plugin-load check reports that.
return {
  -- Ctrl-A selects all and Ctrl-X cuts a selection. Dial keeps normal-mode
  -- Ctrl-X and its g-prefixed Ctrl-A/Ctrl-X increments.
  {
    "monaqa/dial.nvim",
    optional = true,
    keys = {
      { "<C-a>", false, mode = { "n", "v" } },
      { "<C-x>", false, mode = "v" },
    },
  },

  -- <leader>sr replaces in the current file; workspace replace is <leader>sR.
  {
    "MagicDuck/grug-far.nvim",
    optional = true,
    keys = {
      { "<leader>sr", false, mode = { "n", "x" } },
    },
  },

  -- <leader>sR is workspace replace, so Telescope's resume key is dropped.
  {
    "nvim-telescope/telescope.nvim",
    optional = true,
    keys = {
      { "<leader>sR", false },
    },
  },

  -- p pastes at the cursor (before it), as VS Code does. Yanky's P already
  -- puts before the cursor, so only p conflicts.
  {
    "gbprod/yanky.nvim",
    optional = true,
    keys = {
      { "p", false, mode = { "n", "x" } },
    },
  },
}
