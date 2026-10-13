-- Copy-only OSC 52 clipboard for remote sessions outside tmux.
--
-- `options.lua` keeps 'clipboard' at "unnamedplus", which rules out Neovim's
-- automatic OSC 52 provider: Neovim picks it only while 'clipboard' is empty.
-- Inside tmux the tmux provider carries copies out (`set-clipboard on`), and
-- a local desktop has pbcopy, wl-copy, or xclip. A direct SSH session
-- outside tmux has none of those, nor does an Eternal Terminal one on a host
-- an overlay marks remote, so yanks never reach the clipboard of the machine
-- the user sits at.
--
-- This provider copies with OSC 52 but never pastes with it. Many terminals,
-- WezTerm included, never answer an OSC 52 read, so every `p` would block
-- until Neovim's ten-second timeout. Pastes from the local clipboard arrive
-- as terminal (bracketed) pastes anyway.

local session = require("config.session")

local M = {}

local function remote()
  return session.assume_remote() or vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil
end

-- OSC 52 needs a terminal. Headless runs (CI, `nvim --headless "+Lazy! sync"`)
-- have no UI, and embedders such as vscode-neovim and Neovide attach UIs
-- without one. Neovim's own OSC 52 detection asks the same question.
local function terminal()
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    if ui.stdout_tty then
      return true
    end
  end
  return false
end

-- `let g:loaded_clipboard_provider = 0` before the provider script loads
-- turns clipboard providers off, and the script then never defines its
-- functions. exists() does not autoload, so this check loads nothing.
local function disabled()
  return vim.g.loaded_clipboard_provider ~= nil
    and vim.fn.exists("*provider#clipboard#Executable") == 0
end

-- Run Neovim's own clipboard detection once, as it will see things after
-- LazyVim restores 'clipboard' at VeryLazy. Until then 'clipboard' is empty,
-- which lets detection choose its OSC 52 provider, whose paste queries the
-- terminal; any non-empty value rules that out. Reloading the script also
-- replaces such a provider if something loaded it during that window.
local function local_tool()
  local saved = vim.o.clipboard
  vim.o.clipboard = "unnamedplus"
  vim.g.loaded_clipboard_provider = nil
  vim.cmd.runtime("autoload/provider/clipboard.vim")
  vim.o.clipboard = saved
  return vim.g.loaded_clipboard_provider == 2
end

--- Whether this session needs the copy-only provider.
---@return boolean
function M.wanted()
  -- An explicit g:clipboard is the user's or an overlay's choice, including
  -- `false`, which asks for Neovim's own detection.
  if vim.g.clipboard ~= nil or disabled() then
    return false
  end
  -- tmux has its own provider, VS Code terminals their own clipboard
  -- handling, local sessions a local clipboard; OSC 52 needs a terminal.
  if vim.env.TMUX or session.vscode() or not remote() or not terminal() then
    return false
  end
  -- Last, because detection loads the provider script and may run a probe
  -- such as `xsel -o -b` over a forwarded X11 display.
  return not local_tool()
end

-- What each selection register last received this session, as
-- { lines, regtype }, and the latest of those copies.
local copied = {}
local latest

local function copy(reg)
  local send = require("vim.ui.clipboard.osc52").copy(reg)
  return function(lines, regtype)
    copied[reg] = { lines, regtype }
    latest = copied[reg]
    send(lines)
  end
end

-- Neovim's unnamed register in the provider's own format: linewise and
-- blockwise lines end with an empty string, and the regtype is one character,
-- without a block's width, which Neovim recomputes. The provider must not
-- recurse, so inside a provider call the register API reads Neovim's own copy
-- instead of calling back in here; nil when that copy is empty.
local function unnamed()
  local info = vim.fn.getreginfo('"')
  if not info.regcontents then
    return nil
  end
  local lines = info.regcontents
  local regtype = info.regtype:sub(1, 1)
  if regtype ~= "v" then
    lines = vim.list_extend(vim.list_slice(lines), { "" })
  end
  return { lines, regtype }
end

-- A register this session never copied to answers with the latest copy to
-- the other one, as a clipboard would; reading the unnamed register would
-- come back empty once it points at that other register. Before any copy,
-- it answers as it would with no provider at all, where both selection
-- registers stand for the unnamed register, including what ShaDa restored.
-- With neither, an empty list makes Neovim report "Nothing in register".
local function paste(reg)
  return function()
    return copied[reg] or latest or unnamed() or {}
  end
end

--- Install the copy-only provider when this session needs it.
---
--- Call after every overlay has had its chance to set
--- `vim.g.remote_open_assume_remote` or `vim.g.clipboard`.
function M.setup()
  if not M.wanted() then
    return
  end
  vim.g.clipboard = {
    -- The exact name is load-bearing. yanky.nvim, which-key, and Snacks read
    -- it as "+ and * do not reflect the real clipboard", which is true here.
    -- Yanky then keeps its default register and every save and restore on
    -- `"`, which never reaches the provider, so its putting through a
    -- temporary register cannot send this editor's older text to the local
    -- clipboard. which-key and Snacks skip + and * in their register lists.
    name = "OSC 52",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
  }
  -- Detection loaded the provider script without finding a tool; this is the
  -- reload the script documents, so it reads the new g:clipboard.
  vim.g.loaded_clipboard_provider = nil
  vim.cmd.runtime("autoload/provider/clipboard.vim")
end

return M
