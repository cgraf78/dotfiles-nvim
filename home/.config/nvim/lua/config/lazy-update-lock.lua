local M = {}

local uv = vim.uv or vim.loop
local timeout_ms = 5 * 60 * 1000

--- @return string
function M.path()
  return vim.fn.stdpath("data") .. "/lazy/lazy.nvim.update.lock"
end

--- Wait for a scheduled Lazy update before allowing this Neovim to load it.
--- @return boolean
function M.await()
  local path = M.path()
  if vim.env.NVIM_LAZY_UPDATE == "1" or not uv.fs_stat(path) then
    return true
  end

  return vim.wait(timeout_ms, function()
    return not uv.fs_stat(path)
  end, 50)
end

return M
