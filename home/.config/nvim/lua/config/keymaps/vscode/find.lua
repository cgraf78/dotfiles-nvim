local selection = require("config.keymaps.vscode.selection")

local M = {}

-- Ctrl-F is the only search entrypoint that should auto-select the accepted
-- match. Native `/` and `?` searches remain plain Vim searches, so this flag is
-- set only by the VSCode-style mappings and cleared on accept/cancel.
local select_after_find = false

function M.find_selection()
  local text = selection.text()
  if text == "" then
    select_after_find = true
    return "<Esc>/"
  end

  -- Use very-nomagic search so VSCode-style find treats selected text
  -- literally while still leaving native Vim search available elsewhere.
  local pattern = "\\V" .. vim.fn.escape(text, [[\/]]):gsub("\n", [[\n]])
  select_after_find = true
  return "<Esc>/" .. pattern
end

function M.start_find()
  select_after_find = true
  return "/"
end

function M.start_insert_find()
  select_after_find = true
  return "<Esc>/"
end

-- Build a Select-mode range from the active search match so typing can replace
-- it immediately. `searchpos("", "ce")` reuses the current search register and
-- lands on the match end without moving to another match.
local function select_current_search()
  if vim.fn.getreg("/") == "" then
    return false
  end

  local start = vim.api.nvim_win_get_cursor(0)
  local finish = vim.fn.searchpos("", "ce")
  if finish[1] == 0 then
    return false
  end

  vim.api.nvim_win_set_cursor(0, start)
  vim.cmd("normal! v")
  local finish_col = finish[2] - 1
  if vim.o.selection == "exclusive" then
    finish_col = finish[2]
  end
  vim.api.nvim_win_set_cursor(0, { finish[1], math.max(finish_col, 0) })
  vim.api.nvim_feedkeys(vim.keycode("<C-g>"), "nx", false)
  return true
end

local function schedule_select_current_search()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  -- The command line closes before Neovim has fully settled back into Normal
  -- mode. Defer one tick, then prove the original window and buffer are still
  -- current before creating a selection from the async callback.
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    if vim.api.nvim_get_current_win() ~= win then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
      return
    end
    if vim.fn.mode() ~= "n" then
      return
    end
    select_current_search()
  end)
end

function M.accept_find()
  -- This command-line <CR> mapping is global, so only intercept search command
  -- lines that came from our Ctrl-F path. Every other command line keeps the
  -- normal <CR> behavior.
  if select_after_find and (vim.fn.getcmdtype() == "/" or vim.fn.getcmdtype() == "?") then
    select_after_find = false
    schedule_select_current_search()
  end
  return vim.keycode("<CR>")
end

function M.setup()
  -- `vscode.lua` can be re-sourced while this module stays cached. Reset the
  -- transient Ctrl-F flag here to preserve the old file-local reload behavior.
  select_after_find = false

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = vim.api.nvim_create_augroup("dot_vscode_find", { clear = true }),
    callback = function()
      -- Escaping Ctrl-F should not make the next unrelated `/` search enter
      -- Select mode just because the flag was still armed.
      if vim.fn.getcmdtype():match("[/?]") then
        select_after_find = false
      end
    end,
  })
end

local function has_search_match()
  if vim.fn.getreg("/") == "" then
    return false
  end

  -- Insert-mode search navigation should be a no-op when there is no real
  -- match; leaving Insert mode just to discover that would eat the next typed
  -- character.
  local ok, count = pcall(vim.fn.searchcount, { recompute = true, maxcount = 1 })
  return ok and (count.total or 0) > 0
end

local function resume_insert(cursor)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  -- Insert-mode mappings finish by returning through Normal mode. Resume one
  -- tick later so failed search movement stays transparent to continued typing.
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    if vim.api.nvim_get_current_win() ~= win then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
      return
    end
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
    vim.cmd("startinsert")
  end)
end

function M.select_previous_search(from_insert)
  from_insert = from_insert == true
  local mode = vim.fn.mode()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start
  if from_insert then
    vim.cmd("stopinsert")
  elseif mode:match("[vVsS]") then
    start = selection.bounds()
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "x", false)
  end

  if vim.fn.getreg("/") == "" then
    if from_insert then
      resume_insert(cursor)
    end
    return
  end

  if start then
    vim.api.nvim_win_set_cursor(0, { start.line, math.max(start.col - 1, 0) })
  end
  -- Use explicit no-wrap searches so wrapping always lands on a real previous
  -- match instead of depending on the user's global 'wrapscan' setting.
  if vim.fn.search("", "bW") == 0 then
    local line = vim.api.nvim_buf_line_count(0)
    local col = #vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
    vim.api.nvim_win_set_cursor(0, { line, col })
    vim.fn.search("", "bW")
  end
  if not select_current_search() and from_insert then
    resume_insert(cursor)
  end
end

function M.select_next_search(from_insert)
  from_insert = from_insert == true
  local mode = vim.fn.mode()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local finish
  if from_insert then
    vim.cmd("stopinsert")
  elseif mode:match("[vVsS]") then
    _, finish = selection.bounds()
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "x", false)
  end

  if vim.fn.getreg("/") == "" then
    if from_insert then
      resume_insert(cursor)
    end
    return
  end

  if finish then
    vim.api.nvim_win_set_cursor(0, { finish.line, math.max(finish.col - 1, 0) })
  end
  -- See select_previous_search(): VSCode-style find navigation should wrap
  -- consistently even when Vim's native search wrapping is disabled.
  if vim.fn.search("", "W") == 0 then
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.fn.search("", "W")
  end
  if not select_current_search() and from_insert then
    resume_insert(cursor)
  end
end

function M.select_previous_search_from_insert()
  if not has_search_match() then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("stopinsert")
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_win() ~= win then
      return
    end
    if
      not vim.api.nvim_buf_is_valid(buf)
      or vim.api.nvim_win_get_buf(win) ~= buf
      or vim.fn.mode() ~= "n"
    then
      return
    end
    M.select_previous_search()
  end)
end

function M.select_next_search_from_insert()
  if not has_search_match() then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("stopinsert")
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_win() ~= win then
      return
    end
    if
      not vim.api.nvim_buf_is_valid(buf)
      or vim.api.nvim_win_get_buf(win) ~= buf
      or vim.fn.mode() ~= "n"
    then
      return
    end
    M.select_next_search()
  end)
end

return M
