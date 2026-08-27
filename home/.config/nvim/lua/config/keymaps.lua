-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- The dev overlay contributes VSCode-style development mappings. Editor-only
-- machines deliberately omit that module, so load it only when present.
pcall(require, "config.keymaps.vscode")

local map = vim.keymap.set

-- Exit insert/terminal mode
map("i", "kj", "<Esc>", { desc = "Exit insert mode" })
map("t", "kj", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Yank history. tmux forwards Ctrl-Shift-v as Esc[778899~ so it does not
-- fall through to tmux's plain Ctrl-v paste binding.
local function open_yank_history()
  -- LazyVim.pick.picker can be nil (no picker resolved yet / minimal session);
  -- guard so <C-S-v> falls through to the YankyRingHistory command instead of
  -- erroring on a nil index.
  local picker = LazyVim.pick.picker and LazyVim.pick.picker.name
  if picker == "telescope" then
    require("telescope").extensions.yank_history.yank_history({})
  elseif picker == "snacks" then
    Snacks.picker.yanky() ---@diagnostic disable-line: undefined-field
  else
    vim.cmd([[YankyRingHistory]])
  end
end
map({ "n", "x", "i" }, "<C-S-v>", open_yank_history, { desc = "Open Yank History" })
map(
  { "n", "x", "i" },
  vim.keycode("<Esc>") .. "[778899~",
  open_yank_history,
  { desc = "Open Yank History" }
)

-- Join lines without cursor jump
map("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)" })

-- Termnav installed its mappings during the earlier autocmd phase. LazyVim's
-- VeryLazy defaults load this file later, so refresh only the mappings here;
-- navigation policy and all outer-scope routing remain in Termnav.
require("config.termnav").refresh_mappings()
