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

# Per-probe deadline, in seconds. A healthy config starts in well under a
# second; the margin covers heavily loaded hosts. A busy Neovim can ignore
# SIGTERM, so the timeout escalates to SIGKILL after a short grace period.
_DR_NVIM_PROBE_TIMEOUT=8
# Oldest Neovim the config runs on: LazyVim's own startup gate (the
# `has("nvim-...")` check at the top of lua/lazyvim/plugins/init.lua). Keep
# them in step; if LazyVim moves first, an in-between Neovim times out.
_DR_NVIM_MIN_VERSION=0.11.2
# timeout(1) or gtimeout, resolved per doctor run; empty when the host has none.
_DR_NVIM_TIMEOUT_BIN=''
# Lua run from --cmd to load a probe script; see _dr_nvim_probe.
_DR_NVIM_PROBE_LOADER='local ok, err = pcall(dofile, vim.env.DOT_NVIM_PROBE_SCRIPT); '
_DR_NVIM_PROBE_LOADER+='if not ok then io.stderr:write(tostring(err), "\n"); vim.cmd("cquit 3") end'

# Run one headless Neovim probe: DIR SCRIPT [NVIM_ARGS...]. SCRIPT runs from
# --cmd, writes DIR/result in one step, and quits. Neovim never shares a pipe
# with doctor (stdin and stdout are /dev/null, stderr goes to DIR/stderr), so
# a child it leaves behind cannot keep doctor waiting, and timeout(1) bounds
# the run, killing its whole process group at the deadline. Without a timeout
# command the probe runs unbounded; only the syntax check, which runs no user
# code, accepts that. The outer redirection swallows the shell's job notice
# when the deadline escalates to SIGKILL. A Lua error escaping --cmd would
# leave headless Neovim waiting for input, so the script loads under pcall
# and any escaped error quits with status 3, its message on stderr.
# Every probe gets private XDG state and cache directories under DIR, so
# Neovim's log, Lua bytecode, and plugin caches never land in the user's.
# REPLY: "complete", "timeout", "no-tmpdir" (no temp directories, nothing ran), or
# the exit status of a run that left no result.
_dr_nvim_probe() {
  local dir=$1 script=$2 status=0 started=$SECONDS
  local -a bound=()
  shift 2

  if ! mkdir -p "$dir/state" "$dir/cache" 2>/dev/null; then
    REPLY=no-tmpdir
    return 0
  fi
  [[ -z $_DR_NVIM_TIMEOUT_BIN ]] ||
    bound=("$_DR_NVIM_TIMEOUT_BIN" -k 1 "$_DR_NVIM_PROBE_TIMEOUT")
  {
    DOT_NVIM_PROBE_RESULT=$dir/result DOT_NVIM_PROBE_SCRIPT=$script \
      XDG_STATE_HOME=$dir/state XDG_CACHE_HOME=$dir/cache \
      ${bound[@]+"${bound[@]}"} env -u TMUX -u TMUX_PANE \
      nvim --headless -i NONE "$@" --cmd "lua $_DR_NVIM_PROBE_LOADER" \
      </dev/null >/dev/null 2>"$dir/stderr"
  } 2>/dev/null || status=$?

  # GNU timeout exits 124, or 137 once it escalates to SIGKILL. BusyBox
  # passes on Neovim's own status, and Neovim exits 1 after catching
  # SIGTERM, so a run that used up the deadline without a result also counts.
  if [[ -n $_DR_NVIM_TIMEOUT_BIN ]] && { [[ $status -eq 124 || $status -eq 137 ]] ||
    [[ ! -f $dir/result && $((SECONDS - started)) -ge $_DR_NVIM_PROBE_TIMEOUT ]]; }; then
    REPLY=timeout
  elif [[ -f $dir/result ]]; then
    REPLY=complete
  else
    REPLY=$status
  fi
}

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
  local probe_dir kind value checked=0 errors=0 first_error='' outside=0 first_outside=''

  probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/dot-nvim-syntax.XXXXXX" 2>/dev/null) || {
    _dr_warn "nvim config syntax check failed" "could not create temp directory"
    return 0
  }
  # Compile every Lua file in the config tree without executing it. Overlays
  # install config files as symlinks into their checkouts, so file links are
  # followed wherever they point. Directory links are followed only while they
  # resolve inside the config tree, and each real directory is walked once, so
  # a link cycle or a link to a large outside tree cannot stall doctor. The
  # script runs from --cmd rather than `nvim -l`, which Neovim before 0.9
  # reads as Lisp mode plus a file to edit, waiting forever when headless.
  if ! cat 2>/dev/null >"$probe_dir/syntax.lua" <<'LUA'
local uv = vim.uv or vim.loop
local records = {}

local function emit(kind, value)
  table.insert(records, kind .. "\t" .. tostring(value):gsub("%c", " "))
end

local function check()
  local root = vim.fn.stdpath("config")
  local real_root = uv.fs_realpath(root)
  if not real_root then
    emit("absent", "")
    return
  end

  local checked, seen = 0, {}

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
    if real and not inside(real) then
      -- Never claim files under a link to an outside tree were checked.
      emit("outside", prefix:sub(1, -2))
      return
    end
    if not real or seen[real] then
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
  emit("checked", checked)
end

-- Always publish a result and quit, even if the walk itself fails.
local ok, err = pcall(check)
if not ok then
  emit("internal", err)
end
vim.fn.writefile(records, vim.env.DOT_NVIM_PROBE_RESULT)
vim.cmd("qall!")
LUA
  then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_warn "nvim config syntax check failed" "could not write temp file"
    return 0
  fi
  # No user code or plugins run here, so the data directory is private too.
  XDG_DATA_HOME=$probe_dir/data \
    _dr_nvim_probe "$probe_dir" "$probe_dir/syntax.lua" --clean -u NONE
  case $REPLY in
    complete) ;;
    no-tmpdir)
      rm -rf "$probe_dir" 2>/dev/null || true
      _dr_warn "nvim config syntax check failed" "could not create temp directory"
      return 0
      ;;
    timeout)
      rm -rf "$probe_dir" 2>/dev/null || true
      _dr_warn "nvim config syntax check timed out" \
        "no result within ${_DR_NVIM_PROBE_TIMEOUT}s"
      return 0
      ;;
    *)
      rm -rf "$probe_dir" 2>/dev/null || true
      _dr_warn "nvim config syntax check could not run" "nvim exited with status $REPLY"
      return 0
      ;;
  esac

  while IFS=$'\t' read -r kind value; do
    case $kind in
      absent)
        rm -rf "$probe_dir" 2>/dev/null || true
        _dr_skip "nvim config syntax" "configuration directory is absent"
        return 0
        ;;
      internal)
        rm -rf "$probe_dir" 2>/dev/null || true
        _dr_warn "nvim config syntax check could not run" "$(_dr_nvim_one_line "$value")"
        return 0
        ;;
      checked) checked=$value ;;
      error)
        errors=$((errors + 1))
        [[ -n $first_error ]] || first_error=$value
        ;;
      outside)
        outside=$((outside + 1))
        [[ -n $first_outside ]] || first_outside=$value
        ;;
    esac
  done <"$probe_dir/result"
  rm -rf "$probe_dir" 2>/dev/null || true

  if ((errors > 0)); then
    _dr_fail "nvim config syntax errors" \
      "$errors of $checked Lua file(s); $(_dr_nvim_one_line "$first_error")"
  elif ((outside > 0)); then
    _dr_warn "nvim config syntax partly checked" \
      "$checked Lua files valid; $outside linked director(ies) outside the config tree not checked, including $(_dr_nvim_one_line "$first_outside")"
  elif ((checked == 0)); then
    _dr_skip "nvim config syntax" "no Lua files in the configuration directory"
  else
    _dr_ok "nvim config syntax is valid" "$checked Lua files"
  fi
}

_dr_check_nvim_startup() {
  local probe_dir kind value stderr_text
  local updating=0 stale_lock='' too_old=0 absent=0 lazy_ready=0 missing=0 first_missing='' errors=0 first_error=''

  # Unlike the syntax check, this runs user code, so it needs a deadline.
  if [[ -z $_DR_NVIM_TIMEOUT_BIN ]]; then
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

-- LazyVim refuses older Neovim and then waits on getchar() for a keypress,
-- which a headless probe would sit through until its deadline.
if vim.fn.has("nvim-" .. vim.env.DOT_NVIM_MIN_VERSION) == 0 then
  vim.fn.writefile({ "old" }, result)
  vim.cmd("qall!")
  return
end

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
local meta = getmetatable(vim)
if type(meta) ~= "table" or type(meta.__index) ~= "function" then
  -- No hook point on this Neovim: fall back to a plain, replaceable recorder.
  vim.notify = notify
  meta = nil
end
local index, newindex = meta and meta.__index, meta and meta.__newindex
if meta then
  rawset(vim, "notify", nil)
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
    local shown = vim.api.nvim_exec2 and vim.api.nvim_exec2("messages", { output = true }).output
      or vim.api.nvim_exec("messages", true)
    if shown:find(errmsg, 1, true) then
      record_error(errmsg)
    end
  end
  if vim.g.plugin_manager_missing then
    table.insert(records, "absent")
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
      vim.schedule(function()
        -- Publish something and quit even if collecting results fails, so a
        -- probe bug costs one row rather than the whole deadline.
        local done, err = pcall(finish)
        if not done then
          vim.fn.writefile({ "internal\t" .. summarize(err) }, result)
          vim.cmd("qall!")
        end
      end)
    end, 0)
  end,
})
LUA
  then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_skip "nvim startup probe" "could not write the probe script"
    return 0
  fi
  # The runner's private state and cache directories keep the short-lived
  # instance out of the user's editor state: Lazy caches, logs, sessions, Lua
  # bytecode keyed by temporary paths, and the Termnav editor registry, which
  # would otherwise briefly advertise this instance. The data directory stays
  # real because the installed plugins live there. Without TMUX, Termnav makes no
  # tmux queries; doctor workers run in their own session, so its fallback
  # terminal write to /dev/tty has no terminal to reach. GIT_ALLOW_PROTOCOL
  # makes any clone or fetch fail at once even if another overlay's
  # config.lazy ignores plugin_install_disabled.
  DOT_NVIM_MIN_VERSION=$_DR_NVIM_MIN_VERSION GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
    _dr_nvim_probe "$probe_dir" "$probe_dir/probe.lua"
  if [[ $REPLY == no-tmpdir ]]; then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_skip "nvim startup probe" "could not create temp directory"
    return 0
  fi
  if [[ $REPLY == timeout ]]; then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_warn "nvim startup probe timed out" \
      "no result within ${_DR_NVIM_PROBE_TIMEOUT}s; start nvim to inspect"
    return 0
  fi
  if [[ ! -f $probe_dir/result ]]; then
    # Whatever Neovim printed last is the best available clue.
    stderr_text=$(head -c 1000 "$probe_dir/stderr" 2>/dev/null) || stderr_text=''
    stderr_text=$(_dr_nvim_one_line "$stderr_text")
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_fail "nvim exited during startup" "status $REPLY${stderr_text:+; $stderr_text}"
    return 0
  fi
  while IFS=$'\t' read -r kind value; do
    case $kind in
      updating) updating=1 ;;
      old) too_old=1 ;;
      absent) absent=1 ;;
      stale) stale_lock=$value ;;
      internal)
        rm -rf "$probe_dir" 2>/dev/null || true
        _dr_warn "nvim startup probe could not run" "$(_dr_nvim_one_line "$value")"
        return 0
        ;;
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

  if ((too_old)); then
    _dr_warn "nvim too old for this config" \
      "LazyVim needs Neovim $_DR_NVIM_MIN_VERSION or newer; startup probe skipped"
  elif [[ -n $stale_lock ]]; then
    _dr_warn "stale Lazy update lock" \
      "$(dot_doctor_display_path "$stale_lock"); nvim waits on it at every start; remove it unless an update is running"
  elif ((updating)); then
    _dr_skip "nvim startup probe" "a scheduled Lazy plugin update is running"
  elif ((absent)); then
    # Config that needs Lazy fails without it; that is the first-run state,
    # not a config error. This assumes nothing after `require("config.lazy")`
    # runs independently of Lazy, which holds for init.lua here.
    _dr_skip "nvim startup probe" "lazy.nvim is not installed; start nvim once to install plugins"
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
  local version_output version_dir

  _dr_section "Neovim"

  if ! command -v nvim >/dev/null 2>&1; then
    _dr_skip "nvim not installed"
    return 0
  fi
  # Read the version without an early-exiting pipeline: under the worker's
  # pipefail policy a SIGPIPE in the producer would abort the extension. Even
  # --version opens Neovim's log, so it too gets private XDG directories.
  version_dir=$(mktemp -d "${TMPDIR:-/tmp}/dot-nvim-version.XXXXXX" 2>/dev/null) || {
    _dr_warn "nvim checks could not run" "could not create temp directory"
    return 0
  }
  if ! version_output=$(XDG_STATE_HOME=$version_dir XDG_CACHE_HOME=$version_dir \
    XDG_DATA_HOME=$version_dir nvim --version 2>/dev/null); then
    rm -rf "$version_dir" 2>/dev/null || true
    _dr_warn "nvim found but cannot run" "binary may be incompatible with this platform"
    return 0
  fi
  rm -rf "$version_dir" 2>/dev/null || true
  version_output=${version_output%%$'\n'*}
  _dr_ok "nvim installed" "${version_output#NVIM }"

  _DR_NVIM_TIMEOUT_BIN=''
  if command -v timeout >/dev/null 2>&1; then
    _DR_NVIM_TIMEOUT_BIN=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    _DR_NVIM_TIMEOUT_BIN=gtimeout
  fi

  # Neither probe may bootstrap plugins or tools, or reach the network:
  # doctor must stay diagnostic and fast on a freshly activated editor
  # profile and on offline hosts.
  _dr_check_nvim_config_syntax
  _dr_check_nvim_startup
}
