-- Facts about the terminal session around this editor, shared by adapters
-- that behave differently on remote hosts or in VS Code terminals.
--
-- Every answer comes from the environment and globals alone, so startup
-- paths can afford them. Per-request probes such as Termnav's link host stay
-- with the adapter that needs them.

local M = {}

--- Whether an overlay has declared this whole host remote.
---
--- Hosts reached through transports that leave neither SSH variable behind
--- (Eternal Terminal, tmux servers started outside SSH) set
--- `vim.g.remote_open_assume_remote = true`. The name predates its other
--- consumers; `config.remote-open` was the first.
---@return boolean
function M.assume_remote()
  -- Accept Vimscript's `let g:remote_open_assume_remote = 1` as well.
  local assume = vim.g.remote_open_assume_remote
  return assume == true or assume == 1
end

--- Whether Neovim runs directly in a VS Code integrated terminal.
---
--- Inside tmux the environment only records where the pane was created, and
--- tmux can carry VSCODE_IPC_HOOK_CLI into every pane, so this is false there;
--- tmux-aware tools such as Termnav decide per attached client instead.
---@return boolean
function M.vscode()
  if vim.env.TMUX then
    return false
  end
  return vim.env.VSCODE_IPC_HOOK_CLI ~= nil or vim.env.TERM_PROGRAM == "vscode"
end

return M
