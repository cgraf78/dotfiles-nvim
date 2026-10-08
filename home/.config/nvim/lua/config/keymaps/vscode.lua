-- VSCode-style keymaps: replaces vim's modal selection model with shift-arrow
-- selection, modifier navigation, and CUA clipboard shortcuts (Ctrl-C/X/V).
-- Each block covers normal, visual, and insert modes so the bindings work
-- regardless of what mode you happen to be in.

local selection = require("config.keymaps.vscode.selection")
local find = require("config.keymaps.vscode.find")
local replace = require("config.keymaps.vscode.replace")
local lsp = require("config.keymaps.vscode.lsp")
local paste = require("config.keymaps.vscode.paste")

local map = vim.keymap.set
local selection_modes = selection.modes
local select = selection.select
local map_selection_command = selection.map_command

find.setup()
paste.setup()

local function is_active_context(win, buf)
  return vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_get_current_win() == win
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(win) == buf
end

-- Undo/redo
map({ "n", "i", "x", "s" }, "<C-z>", "<cmd>undo<cr>", { desc = "Undo" })
map({ "n", "i", "x", "s" }, "<C-y>", "<cmd>redo<cr>", { desc = "Redo" })

local function save_buffer(resume_insert)
  local function save_path(path)
    if vim.fn.isabsolutepath(path) == 1 then
      return path
    end
    return vim.fs.joinpath(vim.fn.expand("~"), path)
  end

  local function finish(use_feedkeys)
    if resume_insert then
      if use_feedkeys then
        -- A named save is still inside the key mapping, so feed the same
        -- append command as the original insert-mode mapping.
        vim.api.nvim_feedkeys("a", "n", false)
      else
        -- UI input callbacks return after the mapping has finished.
        vim.cmd("startinsert")
      end
    end
  end

  if vim.api.nvim_buf_get_name(0) == "" then
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    vim.ui.input({ prompt = "Save as: ", completion = "file" }, function(path)
      -- Input callbacks can run after a buffer switch, a split, or a close.
      -- Never write or resume Insert mode in whichever editor is active then.
      if not is_active_context(win, buf) then
        return
      end
      if path and path ~= "" then
        local target = save_path(path)
        vim.cmd({
          cmd = "write",
          args = { target },
          mods = { silent = true },
        })
        vim.api.nvim_buf_set_name(0, target)
      end
      finish(false)
    end)
    return
  end

  vim.cmd("silent write")
  finish(true)
end

-- Save
map("n", "<C-n>", function()
  local current_is_pristine = vim.api.nvim_buf_get_name(0) == ""
    and vim.bo.buftype == ""
    and vim.bo.buflisted
    and not vim.bo.modified
    and vim.api.nvim_buf_line_count(0) == 1
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""

  if current_is_pristine then
    return
  end

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
end, { desc = "New buffer" })
map({ "n", "x", "s" }, "<C-s>", save_buffer, { desc = "Save" })
map("i", "<C-s>", function()
  vim.cmd("stopinsert")
  save_buffer(true)
end, { desc = "Save" })

-- Select all
map("n", "<C-a>", select("ggVG"), { desc = "Select all" })
map("x", "<C-a>", select("gg0oG$"), { desc = "Select all" })
map("s", "<C-a>", "<Esc>" .. select("ggVG"), { desc = "Select all" })
map("i", "<C-a>", select("<Esc>ggVG"), { desc = "Select all" })

-- Shift-arrow selection (character-wise)
map("n", "<S-Left>", select("v<Left>"), { desc = "Select left" })
map("n", "<S-Right>", select("v<Right>"), { desc = "Select right" })
map("n", "<S-Up>", select("v<Up>"), { desc = "Select up" })
map("n", "<S-Down>", select("v<Down>"), { desc = "Select down" })
map(selection_modes, "<S-Left>", "<Left>", { desc = "Extend left" })
map(selection_modes, "<S-Right>", "<Right>", { desc = "Extend right" })
map(selection_modes, "<S-Up>", "<Up>", { desc = "Extend up" })
map(selection_modes, "<S-Down>", "<Down>", { desc = "Extend down" })
map("i", "<S-Left>", select("<Esc>v<Left>"), { desc = "Select left" })
map("i", "<S-Right>", select("<Esc>v<Right>"), { desc = "Select right" })
map("i", "<S-Up>", select("<Esc>v<Up>"), { desc = "Select up" })
map("i", "<S-Down>", select("<Esc>v<Down>"), { desc = "Select down" })

-- Ctrl-arrow word navigation
map("n", "<C-Left>", "b", { desc = "Word left" })
map("n", "<C-Right>", "w", { desc = "Word right" })
map("i", "<C-Left>", "<C-o>b", { desc = "Word left" })
map("i", "<C-Right>", "<C-o>w", { desc = "Word right" })

-- Ctrl-Shift-arrow selection (word-wise)
map("n", "<C-S-Left>", select("vb"), { desc = "Select word left" })
map("n", "<C-S-Right>", select("ve"), { desc = "Select word right" })
map_selection_command("<C-S-Left>", "b", { desc = "Extend word left" })
map_selection_command("<C-S-Right>", "e", { desc = "Extend word right" })
map("i", "<C-S-Left>", select("<Esc>vb"), { desc = "Select word left" })
map("i", "<C-S-Right>", select("<Esc>ve"), { desc = "Select word right" })

-- Shift-Home/End selection
map("n", "<S-Home>", select("v<Home>"), { desc = "Select to line start" })
map("n", "<S-End>", select("v<End>"), { desc = "Select to line end" })
map(selection_modes, "<S-Home>", "<Home>", { desc = "Extend to line start" })
map(selection_modes, "<S-End>", "<End>", { desc = "Extend to line end" })
map("i", "<S-Home>", select("<Esc>v<Home>"), { desc = "Select to line start" })
map("i", "<S-End>", select("<Esc>v<End>"), { desc = "Select to line end" })

-- Shift-PageUp/Down selection
map("n", "<S-PageUp>", select("v<PageUp>"), { desc = "Select page up" })
map("n", "<S-PageDown>", select("v<PageDown>"), { desc = "Select page down" })
map(selection_modes, "<S-PageUp>", "<PageUp>", { desc = "Extend page up" })
map(selection_modes, "<S-PageDown>", "<PageDown>", { desc = "Extend page down" })
map("i", "<S-PageUp>", select("<Esc>v<PageUp>"), { desc = "Select page up" })
map("i", "<S-PageDown>", select("<Esc>v<PageDown>"), { desc = "Select page down" })

-- Unmodified arrows in visual mode: clear selection and move.
-- Vim's default keeps the selection alive, which is confusing for VSCode muscle memory.
map(selection_modes, "<Left>", "<Esc><Left>", { desc = "Clear selection, move left" })
map(selection_modes, "<Right>", "<Esc><Right>", { desc = "Clear selection, move right" })
map(selection_modes, "<Up>", "<Esc><Up>", { desc = "Clear selection, move up" })
map(selection_modes, "<Down>", "<Esc><Down>", { desc = "Clear selection, move down" })
map(selection_modes, "<Home>", "<Esc><Home>", { desc = "Clear selection, move to line start" })
map(selection_modes, "<End>", "<Esc><End>", { desc = "Clear selection, move to line end" })
map(selection_modes, "<PageUp>", "<Esc><PageUp>", { desc = "Clear selection, page up" })
map(selection_modes, "<PageDown>", "<Esc><PageDown>", { desc = "Clear selection, page down" })
map(selection_modes, "<C-Left>", "<Esc>b", { desc = "Clear selection, word left" })
map(selection_modes, "<C-Right>", "<Esc>w", { desc = "Clear selection, word right" })
map(selection_modes, "<C-Up>", "<Esc>[m", { desc = "Clear selection, previous function" })
map(selection_modes, "<C-Down>", "<Esc>]m", { desc = "Clear selection, next function" })

-- Move / duplicate lines (Alt-Up/Down, Alt-Shift-Up/Down)
map("n", "<M-Up>", ":m .-2<cr>==", { desc = "Move line up" })
map("n", "<M-Down>", ":m .+1<cr>==", { desc = "Move line down" })
map_selection_command("<M-Up>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
map_selection_command("<M-Down>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("n", "<M-S-Up>", ":t .-1<cr>", { desc = "Duplicate line up" })
map("n", "<M-S-Down>", ":t .<cr>", { desc = "Duplicate line down" })
map_selection_command("<M-S-Up>", ":t '<-1<cr>gv", { desc = "Duplicate selection up" })
map_selection_command("<M-S-Down>", ":t '><cr>gv", { desc = "Duplicate selection down" })

-- Copy/cut/paste.
-- C-c uses `ygv<Esc>` instead of plain `y` to keep cursor position after copy.
map_selection_command("<C-c>", "ygv<Esc>", { desc = "Copy selection" })
map_selection_command("<C-x>", "d", { desc = "Cut selection" })
map_selection_command("<Del>", "d", { desc = "Delete selection" })
map_selection_command("<BS>", "d", { desc = "Delete selection" })
-- `P` pastes before cursor (VSCode inserts at cursor, not after it).
map("n", "<C-v>", "P", { desc = "Paste at cursor" })
map_selection_command("<C-v>", "P", { desc = "Paste at cursor" })
map({ "n", "x" }, "p", "<Plug>(YankyPutBefore)", { desc = "Paste at cursor" })
-- Preserve Vim's visual-block entry point now that Ctrl-V is clipboard paste.
map("n", "<C-q>", "<C-v>", { desc = "Visual block" })

-- Jump by function with Ctrl-Up/Down
map("n", "<C-Up>", "[m", { desc = "Previous function" })
map("n", "<C-Down>", "]m", { desc = "Next function" })
map("n", "<C-S-Up>", select("v[m"), { desc = "Select to previous function" })
map("n", "<C-S-Down>", select("v]m"), { desc = "Select to next function" })
map_selection_command("<C-S-Up>", "[m", { desc = "Extend to previous function" })
map_selection_command("<C-S-Down>", "]m", { desc = "Extend to next function" })

-- LSP aliases
map({ "n", "i", "x", "s" }, "<F2>", lsp.rename_symbol, { desc = "Rename symbol" })
map({ "n", "i", "x", "s" }, "<F12>", lsp.go_to_definition, { desc = "Go to definition" })
map({ "n", "i", "x", "s" }, "<S-F12>", lsp.find_references, { desc = "Find references" })
map({ "n", "i", "x", "s" }, "<C-.>", lsp.code_action, { desc = "Code action" })

-- Indent/dedent selection with Tab/Shift-Tab (reselects after)
map_selection_command("<Tab>", ">gv", { desc = "Indent selection" })
map_selection_command("<S-Tab>", "<gv", { desc = "Dedent selection" })

-- Find
map("n", "<C-f>", find.start_find, { expr = true, desc = "Find" })
map(selection_modes, "<C-f>", find.find_selection, { expr = true, desc = "Find selection" })
map("i", "<C-f>", find.start_insert_find, { expr = true, desc = "Find" })
map("c", "<CR>", find.accept_find, { expr = true, desc = "Accept find" })

-- Replace. Ctrl-H stays reserved for left-pane navigation, and Ctrl-Shift-H
-- stays free for the host OS/window manager.
map("n", "<leader>sr", replace.in_current_file, { desc = "Replace in file" })
map(
  selection_modes,
  "<leader>sr",
  replace.selection_in_current_file,
  { desc = "Replace selection in file" }
)
map("n", "<leader>sR", replace.in_workspace, { desc = "Replace in files" })
map(
  selection_modes,
  "<leader>sR",
  replace.selection_in_workspace,
  { desc = "Replace selection in files" }
)

-- Find next/prev. Keep both the repository's Ctrl-G vocabulary and VS Code's
-- F3 aliases so focus changes do not change what Ctrl-G means.
map({ "n", "x", "s" }, "<C-g>", find.select_next_search, { desc = "Find next" })
map({ "n", "x", "s" }, "<C-S-g>", find.select_previous_search, { desc = "Find prev" })
map("i", "<C-g>", find.select_next_search_from_insert, { nowait = true, desc = "Find next" })
map("i", "<C-S-g>", find.select_previous_search_from_insert, { nowait = true, desc = "Find prev" })
map({ "n", "x", "s" }, "<F3>", find.select_next_search, { desc = "Find next" })
map({ "n", "x", "s" }, "<S-F3>", find.select_previous_search, { desc = "Find prev" })
map("i", "<F3>", find.select_next_search_from_insert, { nowait = true, desc = "Find next" })
map("i", "<S-F3>", find.select_previous_search_from_insert, { nowait = true, desc = "Find prev" })

local function jump_diagnostic(count)
  vim.diagnostic.jump({ count = count, float = true })
end

-- Problems and diagnostic navigation reuse the existing Trouble and native
-- diagnostic surfaces rather than adding another editor integration.
map("n", "<F8>", function()
  jump_diagnostic(1)
end, { desc = "Next diagnostic" })
map("n", "<S-F8>", function()
  jump_diagnostic(-1)
end, { desc = "Previous diagnostic" })
map("n", "<C-S-m>", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Problems" })

-- Toggle comment (Ctrl-/). Legacy terminal protocols encode the physical chord
-- as Ctrl-_, while CSI-u-capable terminals preserve Ctrl-/ distinctly.
-- `remap = true` chains into ts-comments.nvim's `gc`/`gcc` for per-filetype syntax.
for _, key in ipairs({ "<C-/>", "<C-_>" }) do
  map("n", key, "gcc", { remap = true, desc = "Toggle comment" })
  map_selection_command(key, "gc", { remap = true, desc = "Toggle comment" })
  map("i", key, "<Esc>gcca", { remap = true, desc = "Toggle comment" })
end

-- C-` mirrors VSCode's terminal toggle. C-/ is now used for commenting.
-- Separate count values so Snacks treats these as distinct terminal instances.
map({ "n", "t" }, "<C-`>", function()
  Snacks.terminal(nil, { count = 91, win = { position = "right" } })
end, { desc = "Toggle terminal (right)" })
map({ "n", "t" }, "<M-`>", function()
  Snacks.terminal(nil, { count = 92, win = { position = "bottom" } })
end, { desc = "Toggle terminal (bottom)" })
