-- VSCode-style command palette (Ctrl-Shift-P): merges keymaps, user commands,
-- and telescope builtins into one searchable list. Buffer-local keymaps are
-- added first so they sort above globals.

local M = {}

M.type_rank = { key = 1, telescope = 2, cmd = 3 }

function M.sort_entries(entries)
  local rank = M.type_rank
  table.sort(entries, function(a, b)
    local ra, rb = rank[a.type] or 9, rank[b.type] or 9
    if ra ~= rb then
      return ra < rb
    end
    if a.key == b.key then
      return a.desc < b.desc
    end
    return a.key < b.key
  end)
  return entries
end

function M.add_keymaps(entries, seen, list, suffix)
  for _, km in ipairs(list) do
    if km.desc and km.desc ~= "" then
      local seen_key = "key:" .. km.lhs
      if not seen[seen_key] then
        seen[seen_key] = true
        entries[#entries + 1] = {
          key = km.lhs:gsub("^ ", "<Space>"),
          desc = suffix and (km.desc .. suffix) or km.desc,
          type = "key",
          lhs = km.lhs,
        }
      end
    end
  end
end

local function build_entries()
  local entries = {}
  local seen = {}

  M.add_keymaps(entries, seen, vim.api.nvim_buf_get_keymap(0, "n"), " [buf]")
  M.add_keymaps(entries, seen, vim.api.nvim_get_keymap("n"), nil)

  local output = vim.api.nvim_exec2("command", { output = true }).output or ""
  local first = true
  for line in output:gmatch("[^\n]+") do
    if first then
      first = false
    else
      local name = line:match("^.-%s+(%u%S*)")
      if name then
        local seen_key = "cmd:" .. name
        if not seen[seen_key] then
          seen[seen_key] = true
          entries[#entries + 1] = { key = ":" .. name, desc = "", type = "cmd", cmd = name }
        end
      end
    end
  end

  for name, fn in pairs(require("telescope.builtin")) do
    if type(fn) == "function" and not name:match("^_") then
      local seen_key = "ts:" .. name
      if not seen[seen_key] then
        seen[seen_key] = true
        entries[#entries + 1] = { key = "Telescope", desc = name, type = "telescope", cmd = name }
      end
    end
  end

  return M.sort_entries(entries)
end

local function execute(entry)
  if entry.type == "key" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(entry.lhs, true, false, true), "m", false)
  elseif entry.type == "cmd" then
    vim.cmd(entry.cmd)
  elseif entry.type == "telescope" then
    require("telescope.builtin")[entry.cmd]()
  end
end

function M.open()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = build_entries()

  local max_key = 0
  for _, e in ipairs(entries) do
    if #e.key > max_key then
      max_key = #e.key
    end
  end

  local fmt = "%-" .. max_key .. "s  %s"
  for _, e in ipairs(entries) do
    e._display = string.format(fmt, e.key, e.desc)
  end

  pickers
    .new({}, {
      prompt_title = "Command Palette",
      initial_mode = "insert",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            ordinal = e._display,
            display = e._display,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local sel = action_state.get_selected_entry()
          if sel then
            vim.schedule(function()
              execute(sel.value)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
