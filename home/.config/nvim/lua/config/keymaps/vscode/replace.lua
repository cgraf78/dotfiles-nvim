local M = {}

local function current_file_prefills()
  local path = vim.fn.expand("%")
  if path == "" then
    return nil
  end
  return { paths = vim.fn.fnameescape(path) }
end

function M.in_current_file()
  require("grug-far").open({
    transient = true,
    prefills = current_file_prefills(),
  })
end

function M.selection_in_current_file()
  require("grug-far").with_visual_selection({
    transient = true,
    prefills = current_file_prefills(),
  })
end

function M.in_workspace()
  require("grug-far").open({
    transient = true,
  })
end

function M.selection_in_workspace()
  require("grug-far").with_visual_selection({
    transient = true,
  })
end

return M
