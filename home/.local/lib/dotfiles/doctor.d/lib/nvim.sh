# shellcheck shell=bash
# Editor-profile Neovim checks. Development LSP/toolchain policy belongs to the
# additive dotfiles-dev doctor extension.
#
# Doctor workers run under `set -euo pipefail`, and a record helper rejects a
# detail containing a tab or newline with a nonzero status. Every probe below
# therefore captures command status with `|| status=$?` and reduces its detail
# to one line, so a broken config produces a row instead of killing the worker.
# Dot also turns any stray worker stderr into an extra warning row, so helper
# commands here keep their diagnostics to themselves.

# Startup probe deadline, in seconds. A healthy config starts in well under a
# second; the margin covers heavily loaded hosts. A busy Neovim can ignore
# SIGTERM, so the timeout escalates to SIGKILL after a short grace period.
_DR_NVIM_STARTUP_TIMEOUT=8

# Collapse captured output to the single-line detail the doctor API requires
# and drop Lua stack traces, which repeat what the first line already says.
# The input is truncated first because Bash pattern matching slows sharply on
# large strings, and a detail longer than one line of output is not useful.
_dr_nvim_one_line() {
  local text=${1:0:1000}
  text=${text%%stack traceback:*}
  text=${text//[$'\t\r\n']/ }
  while [[ $text == *'  '* ]]; do
    text=${text//  / }
  done
  text=${text# }
  text=${text% }
  ((${#text} <= 300)) || text="${text:0:297}..."
  printf '%s' "$text"
}

_dr_check_nvim_config_syntax() {
  local query_file output status=0 kind value checked=0 errors=0 first_error=''

  query_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-syntax.XXXXXX" 2>/dev/null) || {
    _dr_warn "nvim config syntax check failed" "could not create temp file"
    return 0
  }
  # Compile every Lua file in the config tree without executing it. Overlays
  # install config files as symlinks into their checkouts, so file links are
  # followed wherever they point. Directory links are followed only while they
  # resolve inside the config tree, and each real directory is walked once, so
  # a link cycle or a link to a large outside tree cannot stall doctor.
  if ! cat 2>/dev/null >"$query_file" <<'LUA'
local uv = vim.uv or vim.loop
local root = vim.fn.stdpath("config")
local real_root = uv.fs_realpath(root)
if not real_root then
  io.stdout:write("absent\n")
  return
end

local checked, seen = 0, {}

local function emit(kind, value)
  io.stdout:write(kind, "\t", (value:gsub("%c", " ")), "\n")
end

local function inside(real)
  return real == real_root or real:sub(1, #real_root + 1) == real_root .. "/"
end

-- Name the chunk after its config-relative path so messages stay short and
-- point at the file the user edits rather than an overlay checkout.
local function compile(path, display)
  local file, open_err = io.open(path, "rb")
  if not file then
    return display .. ": " .. tostring(open_err)
  end
  local source = file:read("*a")
  file:close()
  -- loadfile() ignores a leading #! line; blank it but keep line numbers.
  source = source:gsub("^#[^\n]*", "")
  -- PUC Lua 5.1 builds accept only a function in load(); LuaJIT has both.
  local _, err = (loadstring or load)(source, "@" .. display)
  return err
end

local function walk(dir, prefix)
  local real = uv.fs_realpath(dir)
  if not real or seen[real] or not inside(real) then
    return
  end
  seen[real] = true
  local entries = {}
  for name, kind in vim.fs.dir(dir) do
    table.insert(entries, { name = name, kind = kind })
  end
  table.sort(entries, function(a, b)
    return a.name < b.name
  end)
  for _, entry in ipairs(entries) do
    local path, display, kind = dir .. "/" .. entry.name, prefix .. entry.name, entry.kind
    if kind ~= "file" and kind ~= "directory" then
      -- Symlinks, and entries whose type readdir did not report.
      local stat = uv.fs_stat(path)
      kind = stat and stat.type or "missing"
    end
    if kind == "directory" then
      if entry.name ~= ".git" then
        walk(path, display .. "/")
      end
    elseif entry.name:sub(-4) == ".lua" then
      if kind == "file" then
        checked = checked + 1
        local err = compile(path, display)
        if err then
          emit("error", err)
        end
      elseif kind == "missing" then
        emit("error", display .. ": broken symlink")
      end
    end
  end
end

walk(root, "")
emit("checked", tostring(checked))
LUA
  then
    rm -f "$query_file" 2>/dev/null || true
    _dr_warn "nvim config syntax check failed" "could not write temp file"
    return 0
  fi
  output=$(nvim --clean --headless -u NONE -i NONE -l "$query_file" \
    </dev/null 2>/dev/null) || status=$?
  rm -f "$query_file" 2>/dev/null || true
  if ((status != 0)); then
    _dr_warn "nvim config syntax check could not run" "nvim exited with status $status"
    return 0
  fi

  while IFS=$'\t' read -r kind value; do
    case $kind in
      absent)
        _dr_skip "nvim config syntax" "configuration directory is absent"
        return 0
        ;;
      checked) checked=$value ;;
      error)
        errors=$((errors + 1))
        [[ -n $first_error ]] || first_error=$value
        ;;
    esac
  done <<<"$output"

  if ((errors > 0)); then
    _dr_fail "nvim config syntax errors" \
      "$errors of $checked Lua file(s); $(_dr_nvim_one_line "$first_error")"
  elif ((checked == 0)); then
    _dr_skip "nvim config syntax" "no Lua files in the configuration directory"
  else
    _dr_ok "nvim config syntax is valid" "$checked Lua files"
  fi
}

_dr_check_nvim_startup() {
  local timeout_bin probe_dir status=0 started kind value stderr_text
  local updating=0 stale_lock='' lazy_ready=0 missing=0 first_missing='' errors=0 first_error=''

  if command -v timeout >/dev/null 2>&1; then
    timeout_bin=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin=gtimeout
  else
    _dr_skip "nvim startup probe" "timeout command not available"
    return 0
  fi
  probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/dot-nvim-startup.XXXXXX" 2>/dev/null) || {
    _dr_skip "nvim startup probe" "could not create temp directory"
    return 0
  }

  # Load the user's real config headless, offline, and without side effects
  # on editor state. This runs from --cmd, before init.lua:
  # - plugin_install_disabled makes config.lazy skip the lazy.nvim bootstrap
  #   clone and missing-plugin installs;
  # - disable_session_restore keeps nvim-workspace from loading or saving the
  #   user's session; -i NONE keeps ShaDa untouched;
  # - a scheduled Lazy update holds a lock that init.lua waits on for minutes,
  #   so that state is reported instead of waited out.
  # Lazy fires VeryLazy from UIEnter, which a headless instance never sees, and
  # the probe deliberately leaves it unfired: those handlers install missing
  # treesitter parsers over the network and consume LazyVim news by rewriting
  # lazyvim.json. LazyVim loads config/keymaps.lua, and config/autocmds.lua
  # when started without files, from VeryLazy, so those two are covered by
  # the syntax check only.
  if ! cat 2>/dev/null >"$probe_dir/probe.lua" <<'LUA'
local result = assert(vim.env.DOT_NVIM_PROBE_RESULT)
local home = vim.env.HOME or ""
local records = {}

-- A lock older than the editor's own wait limit is stale (its updater died
-- before releasing it), and every interactive start now times out on it.
local ok, lock = pcall(require, "config.lazy-update-lock")
if ok and type(lock) == "table" and type(lock.path) == "function" then
  local lock_stat = (vim.uv or vim.loop).fs_stat(lock.path())
  if lock_stat then
    local limit = math.floor((tonumber(lock.timeout_ms) or 300000) / 1000)
    local stale = os.time() - lock_stat.mtime.sec > limit
    vim.fn.writefile({ stale and ("stale\t" .. lock.path()) or "updating" }, result)
    vim.cmd("qall!")
    return
  end
end

vim.g.plugin_install_disabled = true
vim.g.disable_session_restore = true
vim.v.errmsg = ""

-- One printable line per error, without the stack traces Lazy, LazyVim, and
-- Neovim append; the first line already names the file and cause.
local function summarize(msg)
  local parts = {}
  for line in tostring(msg):gmatch("[^\n]+") do
    if line:match("^%s*# stacktrace") or line:match("^%s*stack traceback") then
      break
    end
    line = vim.trim(line)
    if line ~= "" then
      table.insert(parts, line)
    end
  end
  local text = table.concat(parts, " "):gsub("%c", " ")
  if home ~= "" and home ~= "/" then
    text = text:gsub(vim.pesc(home) .. "/", "~/")
  end
  if #text > 300 then
    text = text:sub(1, 297) .. "..."
  end
  return text
end

local function record_error(msg)
  table.insert(records, "error\t" .. summarize(msg))
end

-- Config and plugin errors that Lazy and LazyVim catch surface only as ERROR
-- notifications. Plugins replace vim.notify during startup and compare
-- identities to decide when to replay buffered messages, so a forwarding
-- wrapper would loop. Instead pin a recorder that ignores replacement and
-- displays nothing: headless startup has no UI to show notifications anyway.
local function notify(msg, level)
  if type(level) == "number" and level >= vim.log.levels.ERROR then
    record_error(msg)
  end
end
rawset(vim, "notify", nil)
local meta = getmetatable(vim)
local index, newindex = meta.__index, meta.__newindex
meta.__index = function(tbl, key)
  if key == "notify" then
    return notify
  end
  return index(tbl, key)
end
meta.__newindex = function(tbl, key, value)
  if key == "notify" then
    return
  end
  if newindex then
    return newindex(tbl, key, value)
  end
  rawset(tbl, key, value)
end

local function finish()
  -- Errors Neovim reports itself (init.lua chunks, autocmds, scheduled
  -- callbacks) set v:errmsg, which holds the latest one. A `silent!` failure
  -- sets it too but is never displayed, so count it only if it reached the
  -- message history. Headless stderr is no substitute: print() and :echo
  -- output land there as well. Only the latest native error is visible this
  -- way; Neovim offers no structured record of earlier ones.
  local errmsg = vim.v.errmsg
  if errmsg ~= "" then
    local shown = vim.api.nvim_exec2("messages", { output = true }).output
    if shown:find(errmsg, 1, true) then
      record_error(errmsg)
    end
  end
  local loaded, config = pcall(require, "lazy.core.config")
  if vim.g.lazy_did_setup and loaded then
    table.insert(records, "lazy")
    local names = {}
    for name, plugin in pairs(config.plugins or {}) do
      if not (plugin._ and plugin._.installed) then
        table.insert(names, name)
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      table.insert(records, "missing\t" .. name)
    end
  end
  vim.fn.writefile(records, result)
  vim.cmd("qall!")
end

-- Lazy and LazyVim report caught errors from scheduled callbacks; let them
-- drain after startup before collecting results.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      vim.schedule(finish)
    end, 0)
  end,
})
LUA
  then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_skip "nvim startup probe" "could not write the probe script"
    return 0
  fi
  # Private state and cache directories keep the short-lived instance out of
  # the user's editor state: Lazy caches, logs, sessions, Lua bytecode keyed
  # by these temporary paths, and the Termnav editor registry, which would
  # otherwise briefly advertise this instance. Without TMUX, Termnav makes no
  # tmux queries; doctor workers run in their own session, so its fallback
  # terminal write to /dev/tty has no terminal to reach. GIT_ALLOW_PROTOCOL
  # makes any clone or fetch fail at once even if another overlay's
  # config.lazy ignores plugin_install_disabled.
  if ! mkdir "$probe_dir/state" "$probe_dir/cache" 2>/dev/null; then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_skip "nvim startup probe" "could not create temp directory"
    return 0
  fi
  # The outer redirection swallows the shell's job notice when the deadline
  # escalates to SIGKILL; Neovim's own stderr is kept for diagnosis.
  started=$SECONDS
  {
    DOT_NVIM_PROBE_RESULT=$probe_dir/result DOT_NVIM_PROBE_SCRIPT=$probe_dir/probe.lua \
      XDG_STATE_HOME=$probe_dir/state XDG_CACHE_HOME=$probe_dir/cache \
      GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
      "$timeout_bin" -k 1 "$_DR_NVIM_STARTUP_TIMEOUT" \
      env -u TMUX -u TMUX_PANE \
      nvim --headless -i NONE --cmd 'lua dofile(vim.env.DOT_NVIM_PROBE_SCRIPT)' \
      </dev/null >/dev/null 2>"$probe_dir/stderr"
  } 2>/dev/null || status=$?

  # GNU timeout exits 124, or 137 once it escalates to SIGKILL. BusyBox
  # passes on Neovim's own status, and Neovim exits 1 after catching
  # SIGTERM, so a run that used up the deadline without a result also counts.
  if [[ $status -eq 124 || $status -eq 137 ]] ||
    [[ ! -f $probe_dir/result && $((SECONDS - started)) -ge $_DR_NVIM_STARTUP_TIMEOUT ]]; then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_warn "nvim startup probe timed out" \
      "no result within ${_DR_NVIM_STARTUP_TIMEOUT}s; start nvim to inspect"
    return 0
  fi
  if [[ ! -f $probe_dir/result ]]; then
    # Whatever Neovim printed last is the best available clue.
    stderr_text=$(head -c 1000 "$probe_dir/stderr" 2>/dev/null) || stderr_text=''
    stderr_text=$(_dr_nvim_one_line "$stderr_text")
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_fail "nvim exited during startup" "status $status${stderr_text:+; $stderr_text}"
    return 0
  fi
  while IFS=$'\t' read -r kind value; do
    case $kind in
      updating) updating=1 ;;
      stale) stale_lock=$value ;;
      lazy) lazy_ready=1 ;;
      missing)
        missing=$((missing + 1))
        [[ -n $first_missing ]] || first_missing=$value
        ;;
      error)
        errors=$((errors + 1))
        [[ -n $first_error ]] || first_error=$value
        ;;
    esac
  done <"$probe_dir/result"
  rm -rf "$probe_dir" 2>/dev/null || true

  if [[ -n $stale_lock ]]; then
    _dr_warn "stale Lazy update lock" \
      "$(dot_doctor_display_path "$stale_lock"); nvim waits on it at every start; remove it unless an update is running"
  elif ((updating)); then
    _dr_skip "nvim startup probe" "a scheduled Lazy plugin update is running"
  elif ((missing > 0)); then
    # Missing plugins cascade into load errors, and the next interactive
    # start installs them, so report the install state rather than a failure.
    _dr_warn "nvim plugins not installed" \
      "$missing missing, including $first_missing; start nvim to install them"
  elif ((errors > 0)); then
    _dr_fail "nvim config reports startup errors" \
      "$errors error(s); $(_dr_nvim_one_line "$first_error")"
  elif ((! lazy_ready)); then
    _dr_skip "nvim startup probe" "lazy.nvim is not installed; start nvim once to install plugins"
  else
    _dr_ok "nvim config loads without errors"
  fi
}

_dr_check_nvim() {
  local version_output

  _dr_section "Neovim"

  if ! command -v nvim >/dev/null 2>&1; then
    _dr_skip "nvim not installed"
    return 0
  fi
  # Read the version without an early-exiting pipeline: under the worker's
  # pipefail policy a SIGPIPE in the producer would abort the extension.
  if ! version_output=$(nvim --version 2>/dev/null); then
    _dr_warn "nvim found but cannot run" "binary may be incompatible with this platform"
    return 0
  fi
  version_output=${version_output%%$'\n'*}
  _dr_ok "nvim installed" "${version_output#NVIM }"

  # Neither probe may bootstrap plugins or tools, or reach the network:
  # doctor must stay diagnostic and fast on a freshly activated editor
  # profile and on offline hosts.
  _dr_check_nvim_config_syntax
  _dr_check_nvim_startup
}
