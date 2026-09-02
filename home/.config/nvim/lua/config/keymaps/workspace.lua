local M = {}

local function follow_item()
  require("nvim_workspace.navigation").goto_mouse()
end

function M.setup()
  -- Terminals default Ctrl-click to tag lookup, which bypasses LSP. Route it
  -- through nvim-workspace so local and remote sessions share the same
  -- definition/root policy.
  vim.keymap.set("n", "<C-LeftMouse>", follow_item, { desc = "Follow Item" })
end

return M
