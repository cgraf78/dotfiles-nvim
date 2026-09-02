local M = {}

local group_name = "dot_window_focus"

local function define_dim_hl()
  local bg = (vim.api.nvim_get_hl(0, { name = "Normal" })).bg or 0
  local r = math.floor(bg / 0x10000 % 0x100 * 0.6)
  local g = math.floor(bg / 0x100 % 0x100 * 0.6)
  local b = math.floor(bg % 0x100 * 0.6)
  vim.api.nvim_set_hl(0, "WinDimmed", { bg = r * 0x10000 + g * 0x100 + b })
  vim.api.nvim_set_hl(0, "WinSepActive", { fg = 0x00cccc })
  vim.api.nvim_set_hl(0, "WinSepInactive", { fg = 0x333333 })
end

local function set_inactive_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:WinDimmed,WinSeparator:WinSepInactive",
    { win = win }
  )
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
end

local function set_active_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_set_option_value("winhighlight", "WinSeparator:WinSepActive", { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })
end

function M.setup()
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  -- WinEnter/WinLeave handle nvim splits; FocusLost/FocusGained handle tmux
  -- pane switches where every nvim window should look inactive.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = define_dim_hl,
  })
  define_dim_hl()

  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      set_inactive_win(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      set_active_win(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        set_inactive_win(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      set_active_win(vim.api.nvim_get_current_win())
    end,
  })
end

return M
