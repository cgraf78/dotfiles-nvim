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

-- `p` pastes at the cursor through Yanky so the yank ring stays in use. Yanky
-- registers its <Plug> maps only when it loads, and lazy.nvim loads it on the
-- first file open, so `p` in a buffer created before that (Ctrl-N) did
-- nothing. Requiring it lets lazy.nvim load it on demand; setups without
-- Yanky fall back to Vim's own put-before.
function M.put_before()
  pcall(require, "yanky")
  if vim.fn.maparg("<Plug>(YankyPutBefore)", "n") ~= "" then
    return "<Plug>(YankyPutBefore)"
  end
  return "P"
end

return M
