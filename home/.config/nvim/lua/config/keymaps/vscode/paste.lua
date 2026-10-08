local M = {}

function M.setup()
  -- WezTerm intercepts Ctrl-V and sends bracketed paste, which nvim's default
  -- handler inserts AFTER the cursor. Override to insert BEFORE.
  local orig_paste = vim.paste
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.paste = function(lines, phase)
    if phase == -1 and vim.fn.mode() == "n" then
      vim.api.nvim_put(lines, "c", false, true)
      return true
    end
    return orig_paste(lines, phase)
  end
end

return M
