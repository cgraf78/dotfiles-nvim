local termnav =
  require("config.dot-runtime").load_dep("cgraf78/termnav", "lib/termnav/nvim/setup.lua")
local navigation =
  require("config.dot-runtime").load_dep("cgraf78/termnav", "lib/termnav/nvim/navigation.lua")

local M = {}
local context

local function listed_buffer_count()
  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      count = count + 1
    end
  end
  return count
end

local function application_navigation()
  -- Bufferline is this configuration's application-tab surface. Termnav owns
  -- every outer scope; these callbacks are the only dotfiles-specific policy
  -- it needs, which keeps tmux, relay, and terminal decisions out of nvim.
  return navigation.new({
    application = {
      tab_count = listed_buffer_count,
      tab_select = function(direction)
        vim.cmd(direction == "previous" and "BufferLineCyclePrev" or "BufferLineCycleNext")
      end,
      tab_move = function(direction)
        vim.cmd(direction == "left" and "BufferLineMovePrev" or "BufferLineMoveNext")
      end,
    },
  })
end

function M.setup(options)
  if context ~= nil then
    return context
  end
  options = options or {}
  -- Dotfiles owns local policy, including augroup naming. The termnav module owns
  -- the WezTerm user-var protocol and publish/clear lifecycle.
  options.group_name = options.group_name or "dot_termnav"
  options.navigation = options.navigation or application_navigation()
  context = termnav.setup(options)
  return context
end

function M.refresh_mappings()
  -- LazyVim installs its defaults on VeryLazy, after autocmd setup. Reapply
  -- Termnav's direct mappings at the same lifecycle point without recreating
  -- its focus autocmds, sockets, or metadata publishers.
  M.setup().navigation.setup()
end

return M
