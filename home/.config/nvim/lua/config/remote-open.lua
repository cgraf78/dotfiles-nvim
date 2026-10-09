-- Forward browser opens from remote sessions to the local desktop.
--
-- Over SSH, Neovim's default `vim.ui.open` runs an opener on the remote host,
-- which is headless or at best the wrong desktop. Termnav owns the request
-- that asks the outer terminal to open a URL where the user actually sits;
-- this adapter only decides when to use it. Every unmet condition (local
-- session, VS Code terminal, non-URL target, explicit `opt.cmd`, Termnav
-- absent, broken, or too old for `open-url`, an outer terminal Termnav cannot
-- confirm is WezTerm, failed delivery) falls through to the original opener,
-- so a missing provider never breaks opening.
--
-- Overlays that know the whole host is remote, whatever transport reached
-- it, can set `vim.g.remote_open_assume_remote = true` to skip Termnav's
-- per-session link-host check.

local M = {}

-- Bound each Termnav call so a wedged tmux server costs the user a short
-- pause and then the fallback. `link-host` can chain several two-second
-- probes; a slow chain is cut off here and treated as "not remote".
local timeout_ms = 3000
local original
-- Depth of fallback() calls in progress; see M.fallback.
local suppressed = 0

-- Only targets that are unmistakably URLs are worth a Termnav round trip;
-- paths and `host:path` words keep the original opener. Termnav makes the
-- final scheme decision.
local function url(target)
  return type(target) == "string"
    and (target:match("^%a[%w+.-]*://") ~= nil or target:lower():match("^mailto:") ~= nil)
end

-- VS Code terminals ignore WezTerm user vars and Termnav declines them, so
-- skip the round trip and leave VS Code's own opener path in charge.
-- Inside tmux the environment only records where the pane was created, and
-- tmux can carry VSCODE_IPC_HOOK_CLI into every pane; Termnav instead skips
-- VS Code's xterm.js clients per request and fails when none other remains.
local function vscode()
  if vim.env.TMUX then
    return false
  end
  return vim.env.VSCODE_IPC_HOOK_CLI ~= nil or vim.env.TERM_PROGRAM == "vscode"
end

-- Run one Termnav command to completion. A binary that is present but cannot
-- execute makes vim.system raise; report that as a failed run instead.
local function run(command)
  local ok, process = pcall(vim.system, command, { text = true })
  if not ok then
    return nil, { code = -1 }
  end
  -- wait() can return nil when a killed command's descendants keep its
  -- pipes open past the deadline; treat that as the timeout it is.
  return process, process:wait(timeout_ms) or { code = 124 }
end

-- Termnav's link host is the shared notion of "this terminal context is a
-- remote host". It also sees managed transports that publish the host in tmux
-- without leaving SSH_CONNECTION in this process's environment.
local function remote(termnav)
  -- Accept Vimscript's `let g:remote_open_assume_remote = 1` as well.
  local assume = vim.g.remote_open_assume_remote
  if assume == true or assume == 1 then
    return true
  end
  local _, result = run({ termnav, "link-host" })
  local host = result.code == 0 and vim.trim(result.stdout or "") or ""
  return host ~= "" and host ~= "localhost"
end

-- Neovim's TUI runs the editor in its own session, so children such as
-- Termnav cannot open /dev/tty; the editor's stderr is still the terminal.
-- Termnav ignores the hint inside tmux, where the attached client is the
-- authoritative destination.
local function terminal()
  if vim.uv.guess_handle(2) ~= "tty" then
    return nil
  end
  local path = vim.uv.fs_readlink("/proc/self/fd/2")
  if path and path:match("^/dev/") then
    return path
  end
  -- macOS has no procfs. LuaJIT's FFI reaches ttyname(3) without a process.
  local ok, name = pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, "char *ttyname(int fd);")
    local pointer = ffi.C.ttyname(2)
    return pointer ~= nil and ffi.string(pointer) or nil
  end)
  return ok and name or nil
end

--- Ask the outer terminal to open `target` locally when that is possible.
---@param target string
---@return vim.SystemObj|nil completed `termnav open-url` process, or nil
function M.forward(target)
  if suppressed > 0 or not url(target) or vscode() then
    return nil
  end
  local termnav = vim.fn.exepath("termnav")
  if termnav == "" or not remote(termnav) then
    return nil
  end
  -- Wait synchronously: the exit status decides between success and the
  -- fallback. An older Termnav rejects the unknown command with status 2, the
  -- current one rejects schemes it will not publish the same way, and it
  -- declines with status 3 an outer terminal it cannot confirm is WezTerm.
  local command = { termnav, "open-url", target }
  local tty = terminal()
  if tty then
    command = { termnav, "open-url", "--tty", tty, target }
  end
  local process, result = run(command)
  if result.code ~= 0 then
    return nil
  end
  return process
end

--- Run `fn(...)` with forwarding disabled.
---
--- For overlays whose own fallback opener may call `vim.ui.open` again after
--- `forward` already failed; without this, a slow failure is paid twice.
---@param fn function
---@return any
function M.fallback(fn, ...)
  suppressed = suppressed + 1
  local results = vim.F.pack_len(pcall(fn, ...))
  suppressed = suppressed - 1
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2, results.n)
end

--- `vim.ui.open` replacement that prefers forwarding in remote sessions.
---@param target string
---@param opt table|nil
---@return vim.SystemObj|nil, string|nil
function M.open(target, opt)
  -- An explicit `opt.cmd` is the caller's chosen opener; honor it. Otherwise
  -- return the completed process to keep the core contract: callers such as
  -- `gx` wait on it and report a nonzero exit as an error.
  local process = not (opt and opt.cmd) and M.forward(target) or nil
  if process then
    return process, nil
  end
  return original(target, opt)
end

--- Wrap `vim.ui.open` once; repeated calls keep the first original opener.
function M.setup()
  if original then
    return
  end
  original = vim.ui.open
  vim.ui.open = M.open
end

return M
