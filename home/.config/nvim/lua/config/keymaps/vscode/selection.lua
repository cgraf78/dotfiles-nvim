local M = {}

-- Keep Select mode explicit so printable keys can replace selections while
-- command-style shortcuts still work on selected text.
M.modes = { "x", "s" }

function M.select(rhs)
  return rhs .. "<C-g>"
end

-- Printable keys are intentionally left to Select mode so typing replaces the
-- selection. Command-style mappings need a one-command escape through Visual
-- mode; otherwise rhs text like `d`, `P`, or `gc` is inserted literally.
function M.command(rhs)
  return "<C-o>" .. rhs
end

-- Keep Visual and Select mode command bindings paired so future selection
-- shortcuts do not accidentally regress VSCode-style replacement typing.
function M.map_command(lhs, rhs, opts)
  vim.keymap.set("x", lhs, rhs, opts)
  vim.keymap.set("s", lhs, M.command(rhs), opts)
end

function M.text()
  local mode = vim.fn.mode()
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  if mode == "V" then
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n")
  end

  local last_col = end_col
  if vim.o.selection == "exclusive" then
    last_col = math.max(start_col, last_col - 1)
  end

  local lines =
    vim.api.nvim_buf_get_text(0, start_line - 1, start_col - 1, end_line - 1, last_col, {})
  return table.concat(lines, "\n")
end

-- Select-mode search movement starts from whichever side of the current
-- selection points toward the next match. Normal `n`/`N` would otherwise keep
-- rediscovering the selected match, which makes find-next appear to stop.
function M.bounds()
  local anchor = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  local start = { line = anchor[2], col = anchor[3] }
  local finish = { line = cursor[2], col = cursor[3] }

  if start.line > finish.line or (start.line == finish.line and start.col > finish.col) then
    start, finish = finish, start
  end
  return start, finish
end

return M
