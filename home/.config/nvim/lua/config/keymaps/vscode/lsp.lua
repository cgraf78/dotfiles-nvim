local M = {}

local function stopinsert_if_needed()
  if vim.fn.mode():match("[iR]") then
    vim.cmd("stopinsert")
  end
end

local function clear_selection_if_needed()
  if vim.fn.mode():match("[vVsS]") then
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "x", false)
  end
end

local function prepare_symbol_action()
  stopinsert_if_needed()
  clear_selection_if_needed()
end

-- These aliases should feel like VSCode keys without downgrading the richer
-- LazyVim extras already enabled in this config. Prefer the configured rename
-- and picker UX when those plugins are present, then fall back to core LSP so
-- the shortcuts still work in minimal/headless setups.
local function try_inc_rename()
  local ok, inc_rename = pcall(require, "inc_rename")
  if not ok then
    return false
  end

  local command = (inc_rename.config and inc_rename.config.cmd_name) or "IncRename"
  -- inc-rename is intentionally command-line driven: prefill the command so
  -- the new name is editable and previewed before any workspace edit applies.
  vim.api.nvim_feedkeys(":" .. command .. " " .. vim.fn.expand("<cword>"), "n", false)
  return true
end

local function try_telescope_lsp(name, opts)
  local ok, telescope = pcall(require, "telescope.builtin")
  local picker = ok and telescope[name]
  if type(picker) ~= "function" then
    return false
  end

  picker(opts)
  return true
end

function M.rename_symbol()
  prepare_symbol_action()
  if try_inc_rename() then
    return
  end
  vim.lsp.buf.rename()
end

function M.go_to_definition()
  prepare_symbol_action()
  if try_telescope_lsp("lsp_definitions", { reuse_win = true }) then
    return
  end
  vim.lsp.buf.definition()
end

function M.find_references()
  prepare_symbol_action()
  if try_telescope_lsp("lsp_references") then
    return
  end
  vim.lsp.buf.references()
end

function M.code_action()
  stopinsert_if_needed()
  vim.lsp.buf.code_action()
end

return M
