local M = {}

local group_name = "dot_diagnostics"

local function show_cursor_float()
  local bt = vim.bo.buftype
  if bt == "prompt" or bt == "terminal" or bt == "nofile" then
    return
  end
  vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
end

function M.setup()
  -- Overrides LazyVim defaults for a quieter editor: virtual text only for
  -- errors, rounded float borders, and source labels.
  vim.diagnostic.config({
    severity_sort = true,
    float = {
      border = "rounded",
      source = true,
      header = "",
      prefix = "",
    },
    virtual_text = {
      prefix = "●",
      spacing = 2,
      severity = { min = vim.diagnostic.severity.ERROR },
    },
    signs = true,
    underline = true,
    update_in_insert = false,
  })

  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  -- Show diagnostic float on cursor hold so the common case does not need `gl`.
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = show_cursor_float,
  })
end

return M
