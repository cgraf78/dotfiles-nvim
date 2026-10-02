# shellcheck shell=bash

# Per-case limit for one doctor run. The probes' own deadlines are 8 s each;
# this only turns a hang into a failure, so it stays generous for busy hosts.
NVIM_DOCTOR_CASE_DEADLINE=${NVIM_DOCTOR_CASE_DEADLINE:-60}

# Doctor support loaded from the checkout under test. The base-owned compat
# shim and shdeps adapter come from the source HOME (the converged base, or the
# capability fixture's stub), since this overlay does not ship them.
_nvim_doctor_api_home() {
  local api_home=$1 doctor_root source_home=${DOT_TEST_SOURCE_HOME:-$HOME}

  doctor_root=$(_nvim_repo_root)/home/.local/lib/dotfiles/doctor.d
  mkdir -p "$api_home/.local/lib/dotfiles/doctor.d/lib" || return 1
  cp "$doctor_root/70-nvim.sh" "$api_home/.local/lib/dotfiles/doctor.d/70-nvim.sh" &&
    cp "$doctor_root/lib/nvim.sh" "$api_home/.local/lib/dotfiles/doctor.d/lib/nvim.sh" &&
    cp -L "$source_home/.local/lib/dotfiles/doctor.d/lib/compat.sh" \
      "$api_home/.local/lib/dotfiles/doctor.d/lib/compat.sh" || return 1
  if [[ -f $source_home/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh ]]; then
    cp -L "$source_home/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh" \
      "$api_home/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh" || return 1
  fi
}

# Load the public doctor API, log every call the extension makes, and source
# the extension entry point from the checkout.
_nvim_doctor_load() {
  local api_home=$1

  _nvim_doctor_api_home "$api_home" || return 1
  _test_load_dot_doctor_api "$api_home" || return 1
  eval "$(declare -f dot_doctor_source | sed '1s/^dot_doctor_source /_nvim_public_dot_doctor_source /')"
  eval "$(declare -f dot_doctor_section | sed '1s/^dot_doctor_section /_nvim_public_dot_doctor_section /')"
  eval "$(declare -f dot_doctor_ok | sed '1s/^dot_doctor_ok /_nvim_public_dot_doctor_ok /')"
  eval "$(declare -f dot_doctor_warn | sed '1s/^dot_doctor_warn /_nvim_public_dot_doctor_warn /')"
  eval "$(declare -f dot_doctor_fail | sed '1s/^dot_doctor_fail /_nvim_public_dot_doctor_fail /')"
  eval "$(declare -f dot_doctor_skip | sed '1s/^dot_doctor_skip /_nvim_public_dot_doctor_skip /')"
  # shellcheck disable=SC2329 # Called by the sourced doctor extension.
  dot_doctor_source() {
    printf 'source\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_source "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_section() {
    printf 'section\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_section "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_ok() {
    printf 'ok\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_ok "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_warn() {
    printf 'warn\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_warn "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_fail() {
    printf 'fail\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_fail "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_skip() {
    printf 'skip\t%s\n' "$1" >>"$NVIM_DOCTOR_API_LOG"
    _nvim_public_dot_doctor_skip "$@"
  }
  dot_doctor_source doctor.d/70-nvim.sh
}

# Run the extension the way Dot's worker does: in a separate shell under
# `set -euo pipefail`, outside any condition, so a probe that lets a failing
# command escape aborts here exactly as it would in production. Records land
# in DOT_DOCTOR_RESULT_FILE; NVIM_DOCTOR_RC holds the worker status. Anything
# else the worker prints goes to DOT_DOCTOR_RESULT_FILE.out, since Dot turns
# such output into an extra warning row.
#
# The worker gets its own process group and a deadline, so a probe that hangs
# fails this case (status 124) instead of stalling the suite; the group is
# killed afterwards either way. GNU timeout(1) moves its child into a group of
# its own, so a fixture that leaves a process behind must clean it up itself.
# Arguments, if any, replace `doctor` as the command to run.
_nvim_doctor_run() {
  local pid ticks=0 limit=$((NVIM_DOCTOR_CASE_DEADLINE * 10))
  (($# > 0)) || set -- doctor
  : >"$DOT_DOCTOR_RESULT_FILE"
  set -m
  (
    set -euo pipefail
    "$@"
  ) </dev/null >"$DOT_DOCTOR_RESULT_FILE.out" 2>&1 &
  pid=$!
  set +m
  while kill -0 "$pid" 2>/dev/null && ((ticks < limit)); do
    sleep 0.1
    ticks=$((ticks + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    NVIM_DOCTOR_RC=124
    _fail "nvim doctor: worker finishes within ${NVIM_DOCTOR_CASE_DEADLINE}s"
  else
    wait "$pid"
    NVIM_DOCTOR_RC=$?
  fi
  kill -KILL -- "-$pid" 2>/dev/null
  return 0
}

# Print the first record whose label starts with PREFIX as KIND<TAB>DETAIL.
_nvim_doctor_record() {
  local prefix=$1 kind label detail
  while IFS=$'\t' read -r kind label detail; do
    if [[ $label == "$prefix"* ]]; then
      printf '%s\t%s' "$kind" "$detail"
      return 0
    fi
  done <"$DOT_DOCTOR_RESULT_FILE"
  return 1
}

nvim_test_doctor_wiring() {
  local tmp fake_bin output nvim_log

  tmp=$(_tmpdir)
  fake_bin=$tmp/bin
  nvim_log=$tmp/nvim.log
  mkdir -p "$fake_bin"
  # A stand-in that only answers --version: every probe after that reports
  # through its own row, and none may run `checkhealth` or reach the network.
  cat >"$fake_bin/nvim" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$NVIM_DOCTOR_TEST_LOG"
case " $* " in
  *' --version '*) printf 'NVIM v0.11.0\nBuild type: Release\n' ;;
esac
exit 0
EOF
  chmod +x "$fake_bin/nvim"

  NVIM_DOCTOR_API_LOG=$tmp/public-doctor-api.log
  DOT_DOCTOR_RESULT_FILE=$tmp/doctor-results.tsv
  export DOT_DOCTOR_RESULT_FILE
  _nvim_doctor_load "$tmp/api-home" || {
    nvim_test_fail 'Neovim doctor entry point loads through the public doctor API'
    return
  }
  NVIM_DOCTOR_TEST_LOG=$nvim_log PATH="$fake_bin:$PATH" _nvim_doctor_run
  output=$(cat "$DOT_DOCTOR_RESULT_FILE")

  _assert_eq "nvim doctor: worker completes" 0 "$NVIM_DOCTOR_RC"
  _assert_contains "nvim doctor: reports the version from the first line" \
    $'ok\tnvim installed\tv0.11.0' "$output"
  _assert_not_contains "nvim doctor: emits no development LSP check" 'LSP' "$output"
  _assert_not_contains "nvim doctor: never runs checkhealth" 'checkhealth' "$(cat "$nvim_log")"
  # Neovim before 0.9 reads `-l` as Lisp mode plus a file to edit. An awk
  # `exit` still runs END, so failures are carried in `bad`.
  if awk '
    /--version/ { next }
    / -l / || !/-i NONE/ || !/--cmd/ { bad = 1; exit }
    /--clean/ { syntax = 1; if (!/-u NONE/) { bad = 1; exit } }
    END { exit bad || !syntax }
  ' "$nvim_log"; then
    _pass "nvim doctor: probes keep ShaDa off and syntax checks run no config"
  else
    _fail "nvim doctor: probes keep ShaDa off and syntax checks run no config"
  fi
  _assert_contains "nvim doctor: loads support through public doctor API" \
    $'source\tdoctor.d/lib/nvim.sh' "$(cat "$NVIM_DOCTOR_API_LOG")"
  _assert_contains "nvim doctor: reports through public doctor API" \
    $'ok\tnvim installed' "$(cat "$NVIM_DOCTOR_API_LOG")"
}

# --- Real-Neovim behavior ----------------------------------------------------

# Write a minimal init.lua. LAZY selects a stand-in for lazy.nvim's state:
# "none" leaves it absent, "ready" reports a set-up manager with every plugin
# installed, and "missing" reports one plugin that is not installed. BODY runs
# after that setup.
_nvim_doctor_init() {
  local config=$1 lazy=$2 body=${3:-}
  mkdir -p "$config"
  {
    case $lazy in
      ready | missing)
        printf '%s\n' \
          'package.preload["lazy.core.config"] = function()' \
          '  return { plugins = {' \
          '    ["present.nvim"] = { _ = { installed = true } },'
        [[ $lazy != missing ]] ||
          printf '%s\n' '    ["absent.nvim"] = { _ = { installed = false } },'
        printf '%s\n' '  } }' 'end' 'vim.g.lazy_did_setup = true'
        ;;
    esac
    printf '%s\n' "$body"
  } >"$config/init.lua"
}

# Run the doctor against XDG_CONFIG_HOME=CASE/config with private data, state,
# and cache roots. Spies for network-capable tools log to CASE/spy.log. Extra
# variables for a fixture are passed as assignments on the call.
_nvim_doctor_case() {
  local case_dir=$1
  mkdir -p "$case_dir/data" "$case_dir/state" "$case_dir/cache"
  : >"$case_dir/spy.log"
  NVIM_DOCTOR_SPY_LOG=$case_dir/spy.log \
    XDG_CONFIG_HOME=$case_dir/config XDG_DATA_HOME=$case_dir/data \
    XDG_STATE_HOME=$case_dir/state XDG_CACHE_HOME=$case_dir/cache \
    NVIM_APPNAME='' TMUX=/tmp/nvim-doctor-test-tmux,1,0 TMUX_PANE=%0 \
    PATH="$NVIM_DOCTOR_BIN:$PATH" _nvim_doctor_run
}

nvim_test_doctor_syntax() {
  local tmp case_dir record overlay

  tmp=$NVIM_DOCTOR_TMP
  overlay=$tmp/overlay
  mkdir -p "$overlay/lua" "$overlay/broken"
  printf 'return {}\n' >"$overlay/lua/good.lua"
  printf 'local broken = = 1\n' >"$overlay/broken/broken.lua"
  printf 'local also = ) 2\n' >"$overlay/broken/also.lua"

  # Overlays link each config file into the tree; every one must be compiled.
  case_dir=$tmp/syntax-symlinks
  _nvim_doctor_init "$case_dir/overlay-root/nvim" none
  mkdir -p "$case_dir/config/nvim/lua/config"
  ln -s "$case_dir/overlay-root/nvim/init.lua" "$case_dir/config/nvim/init.lua"
  ln -s "$overlay/lua/good.lua" "$case_dir/config/nvim/lua/config/good.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: compiles overlay-linked files" \
    $'ok\t2 Lua files' "$record"

  case_dir=$tmp/syntax-root-link
  mkdir -p "$case_dir/real-config/lua" "$case_dir/config"
  printf 'return {}\n' >"$case_dir/real-config/init.lua"
  printf 'return {}\n' >"$case_dir/real-config/lua/mod.lua"
  ln -s "$case_dir/real-config" "$case_dir/config/nvim"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: walks a symlinked config root" \
    $'ok\t2 Lua files' "$record"

  case_dir=$tmp/syntax-broken-link
  _nvim_doctor_init "$case_dir/config/nvim" ready
  mkdir -p "$case_dir/config/nvim/lua"
  ln -s "$overlay/broken/broken.lua" "$case_dir/config/nvim/lua/broken.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: fails on a broken overlay-linked file" \
    $'fail\t1 of 2 Lua file(s); lua/broken.lua:1: unexpected symbol near \'=\'' "$record"

  # A failing probe must yield a row, not abort the errexit worker before the
  # rows that follow it.
  case_dir=$tmp/syntax-broken-file
  _nvim_doctor_init "$case_dir/config/nvim" ready
  mkdir -p "$case_dir/config/nvim/lua/deep/er"
  cp "$overlay/broken/broken.lua" "$case_dir/config/nvim/lua/deep/er/x.lua"
  _nvim_doctor_case "$case_dir"
  _assert_eq "nvim doctor syntax: broken regular file keeps the worker alive" \
    0 "$NVIM_DOCTOR_RC"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: reports a broken nested regular file" \
    $'fail\t1 of 2 Lua file(s); lua/deep/er/x.lua:1: unexpected symbol near \'=\'' "$record"
  record=$(_nvim_doctor_record "nvim config loads")
  _assert_eq "nvim doctor syntax: later rows still run after a syntax failure" \
    $'ok\t' "$record"

  case_dir=$tmp/syntax-multiple
  _nvim_doctor_init "$case_dir/config/nvim" none
  mkdir -p "$case_dir/config/nvim/lua"
  ln -s "$overlay/broken/also.lua" "$case_dir/config/nvim/lua/a.lua"
  ln -s "$overlay/broken/broken.lua" "$case_dir/config/nvim/lua/b.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: summarizes several errors on one line" \
    $'fail\t2 of 3 Lua file(s); lua/a.lua:1: unexpected symbol near \')\'' "$record"

  case_dir=$tmp/syntax-dangling
  _nvim_doctor_init "$case_dir/config/nvim" none
  mkdir -p "$case_dir/config/nvim/lua"
  ln -s "$case_dir/nowhere.lua" "$case_dir/config/nvim/lua/gone.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: fails on a dangling Lua symlink" \
    $'fail\t1 of 1 Lua file(s); lua/gone.lua: broken symlink' "$record"

  # Directory links are followed only inside the tree, once per real
  # directory, so a cycle terminates and outside trees are left alone.
  case_dir=$tmp/syntax-dir-links
  _nvim_doctor_init "$case_dir/config/nvim" none
  mkdir -p "$case_dir/config/nvim/lua" "$case_dir/outside"
  cp "$overlay/broken/broken.lua" "$case_dir/outside/broken.lua"
  ln -s .. "$case_dir/config/nvim/lua/loop"
  ln -s "$case_dir/config/nvim/lua" "$case_dir/config/nvim/again"
  ln -s "$case_dir/outside" "$case_dir/config/nvim/lua/outside"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: directory links neither loop nor leave the tree" \
    $'ok\t1 Lua files' "$record"

  case_dir=$tmp/syntax-empty
  mkdir -p "$case_dir/config/nvim"
  printf 'set number\n' >"$case_dir/config/nvim/init.vim"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: skips a config without Lua files" \
    $'skip\tno Lua files in the configuration directory' "$record"

  case_dir=$tmp/syntax-absent
  mkdir -p "$case_dir/config"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config syntax")
  _assert_eq "nvim doctor syntax: skips an absent config directory" \
    $'skip\tconfiguration directory is absent' "$record"
}

nvim_test_doctor_startup() {
  local tmp case_dir record checkout_config

  tmp=$NVIM_DOCTOR_TMP
  checkout_config=$(_nvim_repo_root)/home/.config/nvim

  # Headless Neovim prints print() and :echo output on stderr, so plenty of
  # ordinary output must not read as an error.
  case_dir=$tmp/startup-clean
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.notify("just a warning", vim.log.levels.WARN)
vim.cmd("silent! definitely-not-a-command")
for _ = 1, 500 do
  print(string.rep("chatty config output ", 20))
end
vim.cmd("echo \"hello from echo\"")'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config loads")
  _assert_eq "nvim doctor startup: output, warnings and silent! errors pass" $'ok\t' "$record"
  _assert_eq "nvim doctor startup: worker writes nothing outside the result API" \
    "" "$(cat "$DOT_DOCTOR_RESULT_FILE.out")"
  _assert_eq "nvim doctor startup: spawns no network-capable tool" "" \
    "$(cat "$case_dir/spy.log")"

  case_dir=$tmp/startup-init-error
  _nvim_doctor_init "$case_dir/config/nvim" ready 'error("boom from init")'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config reports")
  case $record in
    $'fail\t1 error(s); '*'boom from init'*) _pass "nvim doctor startup: fails on an init.lua error" ;;
    *) _fail "nvim doctor startup: fails on an init.lua error (got '$record')" ;;
  esac
  _assert_not_contains "nvim doctor startup: drops the Lua stack trace" \
    'stack traceback' "$record"

  # Lazy and LazyVim report caught errors through vim.notify, often after
  # replacing it and from a scheduled callback.
  case_dir=$tmp/startup-notify
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.notify = function() end
vim.schedule(function()
  vim.notify("Failed loading config.keymaps\n\nboom from notify\n# stacktrace:\n  - x", vim.log.levels.ERROR)
end)'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config reports")
  _assert_eq "nvim doctor startup: captures ERROR notifications after vim.notify is replaced" \
    $'fail\t1 error(s); Failed loading config.keymaps boom from notify' "$record"

  case_dir=$tmp/startup-autocmd-error
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.api.nvim_create_autocmd("VimEnter", { command = "echoerr \"boom from VimEnter\"" })'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config reports")
  case $record in
    $'fail\t1 error(s); '*'boom from VimEnter'*) _pass "nvim doctor startup: fails on a startup autocmd error" ;;
    *) _fail "nvim doctor startup: fails on a startup autocmd error (got '$record')" ;;
  esac

  case_dir=$tmp/startup-scheduled-error
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.schedule(function() error("boom from schedule") end)'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim config reports")
  case $record in
    # Neovim words this message differently by version ("vim.schedule
    # callback:" vs "Error executing vim.schedule lua callback:"); the
    # contract is a fail row naming the scheduled error.
    $'fail\t1 error(s); '*'schedule'*'callback: '*'boom from schedule'*)
      _pass "nvim doctor startup: fails on a scheduled callback error"
      ;;
    *) _fail "nvim doctor startup: fails on a scheduled callback error (got '$record')" ;;
  esac

  # VeryLazy handlers install treesitter parsers and consume LazyVim news, so
  # the headless probe leaves VeryLazy unfired, as a headless start does.
  case_dir=$tmp/startup-very-lazy
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", callback = function()
  vim.fn.writefile({ "fired" }, vim.env.NVIM_DOCTOR_MARKER)
end })'
  NVIM_DOCTOR_MARKER=$case_dir/marker _nvim_doctor_case "$case_dir"
  _assert_eq "nvim doctor startup: leaves VeryLazy handlers unfired" \
    "" "$(cat "$case_dir/marker" 2>/dev/null)"

  case_dir=$tmp/startup-missing
  _nvim_doctor_init "$case_dir/config/nvim" missing \
    'vim.notify("Plugin absent.nvim is not installed", vim.log.levels.ERROR)'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim plugins not installed")
  _assert_eq "nvim doctor startup: warns about plugins awaiting install" \
    $'warn\t1 missing, including absent.nvim; start nvim to install them' "$record"

  case_dir=$tmp/startup-no-lazy
  _nvim_doctor_init "$case_dir/config/nvim" none
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim startup probe")
  _assert_eq "nvim doctor startup: skips before lazy.nvim is installed" \
    $'skip\tlazy.nvim is not installed; start nvim once to install plugins' "$record"

  case_dir=$tmp/startup-exit
  _nvim_doctor_init "$case_dir/config/nvim" ready 'vim.cmd("cquit 3")'
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim exited during startup")
  _assert_eq "nvim doctor startup: fails when Neovim exits before startup ends" \
    $'fail\tstatus 3' "$record"

  case_dir=$tmp/startup-timeout
  _nvim_doctor_init "$case_dir/config/nvim" ready
  mkdir -p "$case_dir/bin"
  printf '#!/bin/sh\nexit 124\n' >"$case_dir/bin/timeout"
  chmod +x "$case_dir/bin/timeout"
  NVIM_DOCTOR_BIN=$case_dir/bin:$NVIM_DOCTOR_BIN _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim startup probe timed out")
  _assert_eq "nvim doctor startup: reports a probe that exceeds its deadline" \
    $'warn\tno result within 8s; start nvim to inspect' "$record"

  # A busy Neovim ignores SIGTERM; the real deadline must escalate to SIGKILL.
  if [[ -e $NVIM_DOCTOR_BIN/timeout ]]; then
    echo "SKIP: real startup deadline (no timeout or gtimeout on this host)"
  else
    case_dir=$tmp/startup-hang
    _nvim_doctor_init "$case_dir/config/nvim" ready 'while true do end'
    _DR_NVIM_PROBE_TIMEOUT=1 _nvim_doctor_case "$case_dir"
    record=$(_nvim_doctor_record "nvim startup probe timed out")
    _assert_eq "nvim doctor startup: stops a hung config at the deadline" \
      $'warn\tno result within 1s; start nvim to inspect' "$record"
    _assert_eq "nvim doctor startup: a killed probe leaves no job notice" \
      "" "$(cat "$DOT_DOCTOR_RESULT_FILE.out")"
  fi

  # BusyBox timeout passes on Neovim's own status: 1 after SIGTERM.
  case_dir=$tmp/startup-busybox-timeout
  _nvim_doctor_init "$case_dir/config/nvim" ready
  mkdir -p "$case_dir/bin"
  printf '#!/bin/sh\nsleep 1\nexit 1\n' >"$case_dir/bin/timeout"
  chmod +x "$case_dir/bin/timeout"
  NVIM_DOCTOR_BIN=$case_dir/bin:$NVIM_DOCTOR_BIN _DR_NVIM_PROBE_TIMEOUT=1 \
    _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim startup probe timed out")
  _assert_eq "nvim doctor startup: treats a run that used up the deadline as a timeout" \
    $'warn\tno result within 1s; start nvim to inspect' "$record"

  # The probe must not touch editor state or the caller's tmux session.
  case_dir=$tmp/startup-isolation
  _nvim_doctor_init "$case_dir/config/nvim" ready \
    'vim.fn.writefile({
  tostring(vim.g.plugin_install_disabled),
  tostring(vim.g.disable_session_restore),
  vim.env.TMUX or "",
  vim.env.TMUX_PANE or "",
  vim.env.XDG_STATE_HOME == vim.env.NVIM_DOCTOR_OUTER_STATE and "outer" or "private",
  vim.env.XDG_CACHE_HOME == vim.env.NVIM_DOCTOR_OUTER_CACHE and "outer" or "private",
  vim.env.GIT_ALLOW_PROTOCOL or "",
}, vim.env.NVIM_DOCTOR_MARKER)
vim.fn.mkdir(vim.fn.stdpath("state") .. "/written", "p")'
  NVIM_DOCTOR_MARKER=$case_dir/marker NVIM_DOCTOR_OUTER_STATE=$case_dir/state \
    NVIM_DOCTOR_OUTER_CACHE=$case_dir/cache _nvim_doctor_case "$case_dir"
  _assert_eq "nvim doctor startup: sets offline flags, drops tmux, uses private state" \
    $'true\ntrue\n\n\nprivate\nprivate\nfile' "$(cat "$case_dir/marker" 2>/dev/null)"
  if [[ -e $case_dir/state/nvim/written ]]; then
    _fail "nvim doctor startup: config writes stay out of the caller's state directory"
  else
    _pass "nvim doctor startup: config writes stay out of the caller's state directory"
  fi

  # A scheduled Lazy update holds this lock while init.lua waits for minutes.
  case_dir=$tmp/startup-update-lock
  mkdir -p "$case_dir/config/nvim/lua/config" "$case_dir/data/nvim/lazy/lazy.nvim.update.lock"
  ln -s "$checkout_config/lua/config/lazy-update-lock.lua" \
    "$case_dir/config/nvim/lua/config/lazy-update-lock.lua"
  printf '%s\n' 'vim.fn.writefile({ "ran" }, vim.env.NVIM_DOCTOR_MARKER)' \
    >"$case_dir/config/nvim/init.lua"
  NVIM_DOCTOR_MARKER=$case_dir/marker _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim startup probe")
  _assert_eq "nvim doctor startup: reports a running Lazy update instead of waiting" \
    $'skip\ta scheduled Lazy plugin update is running' "$record"
  _assert_eq "nvim doctor startup: does not run init.lua during a Lazy update" \
    "" "$(cat "$case_dir/marker" 2>/dev/null)"

  # A lock older than the editor's own wait limit outlived its updater.
  case_dir=$tmp/startup-stale-lock
  mkdir -p "$case_dir/config/nvim/lua/config" "$case_dir/data/nvim/lazy/lazy.nvim.update.lock"
  touch -t 200001010000 "$case_dir/data/nvim/lazy/lazy.nvim.update.lock"
  ln -s "$checkout_config/lua/config/lazy-update-lock.lua" \
    "$case_dir/config/nvim/lua/config/lazy-update-lock.lua"
  printf 'return\n' >"$case_dir/config/nvim/init.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "stale Lazy update lock")
  case $record in
    $'warn\t'*'/data/nvim/lazy/lazy.nvim.update.lock; nvim waits on it at every start; remove it unless an update is running')
      _pass "nvim doctor startup: warns about a stale Lazy update lock"
      ;;
    *) _fail "nvim doctor startup: warns about a stale Lazy update lock (got '$record')" ;;
  esac

  # The checkout's real config.lazy must honor the probe: no bootstrap clone
  # when lazy.nvim is absent ...
  case_dir=$tmp/startup-real-bootstrap
  mkdir -p "$case_dir/config/nvim/lua/config"
  ln -s "$checkout_config/lua/config/lazy.lua" "$case_dir/config/nvim/lua/config/lazy.lua"
  printf 'require("config.lazy")\n' >"$case_dir/config/nvim/init.lua"
  _nvim_doctor_case "$case_dir"
  record=$(_nvim_doctor_record "nvim startup probe")
  _assert_eq "nvim doctor startup: real config skips the lazy.nvim bootstrap" \
    $'skip\tlazy.nvim is not installed; start nvim once to install plugins' "$record"
  _assert_eq "nvim doctor startup: real config clones nothing" "" "$(cat "$case_dir/spy.log")"
  if [[ -e $case_dir/data/nvim/lazy ]]; then
    _fail "nvim doctor startup: real config creates no plugin directory"
  else
    _pass "nvim doctor startup: real config creates no plugin directory"
  fi

  # ... and no missing-plugin installs once it is present.
  case_dir=$tmp/startup-real-install
  mkdir -p "$case_dir/config/nvim/lua/config" \
    "$case_dir/data/nvim/lazy/lazy.nvim/lua/lazy/core"
  ln -s "$checkout_config/lua/config/lazy.lua" "$case_dir/config/nvim/lua/config/lazy.lua"
  printf 'require("config.lazy")\n' >"$case_dir/config/nvim/init.lua"
  printf '%s\n' \
    'return { setup = function(opts)' \
    '  vim.fn.writefile({ tostring(opts.install.missing) }, vim.env.NVIM_DOCTOR_MARKER)' \
    '  vim.g.lazy_did_setup = true' \
    'end }' >"$case_dir/data/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
  printf 'return { plugins = {} }\n' \
    >"$case_dir/data/nvim/lazy/lazy.nvim/lua/lazy/core/config.lua"
  NVIM_DOCTOR_MARKER=$case_dir/marker _nvim_doctor_case "$case_dir"
  _assert_eq "nvim doctor startup: real config disables missing-plugin installs" \
    false "$(cat "$case_dir/marker" 2>/dev/null)"
  record=$(_nvim_doctor_record "nvim config loads")
  _assert_eq "nvim doctor startup: real config with lazy.nvim present loads cleanly" \
    $'ok\t' "$record"
}

# A Neovim that never exits (as Neovim 0.8 does when handed `-l`) or that
# leaves a child holding its output must not stall doctor.
nvim_test_doctor_hangs() {
  local tmp case_dir record

  tmp=$NVIM_DOCTOR_TMP

  if [[ -e $NVIM_DOCTOR_BIN/timeout ]]; then
    echo "SKIP: hung Neovim probes (no timeout or gtimeout on this host)"
  else
    case_dir=$tmp/hang-nvim
    mkdir -p "$case_dir/bin" "$case_dir/config/nvim"
    printf 'return {}\n' >"$case_dir/config/nvim/init.lua"
    cat >"$case_dir/bin/nvim" <<'EOF'
#!/bin/sh
case " $* " in
  *' --version '*) printf 'NVIM v0.8.0\n'; exit 0 ;;
esac
exec sleep 600
EOF
    chmod +x "$case_dir/bin/nvim"
    NVIM_DOCTOR_BIN=$case_dir/bin:$NVIM_DOCTOR_BIN _DR_NVIM_PROBE_TIMEOUT=1 \
      NVIM_DOCTOR_CASE_DEADLINE=20 _nvim_doctor_case "$case_dir"
    _assert_eq "nvim doctor hang: worker finishes when nvim never exits" 0 "$NVIM_DOCTOR_RC"
    record=$(_nvim_doctor_record "nvim config syntax check timed out")
    _assert_eq "nvim doctor hang: syntax check stops at its deadline" \
      $'warn\tno result within 1s' "$record"
    record=$(_nvim_doctor_record "nvim startup probe timed out")
    _assert_eq "nvim doctor hang: startup probe stops at its deadline" \
      $'warn\tno result within 1s; start nvim to inspect' "$record"
  fi

  case_dir=$tmp/hang-child
  mkdir -p "$case_dir/bin" "$case_dir/config/nvim"
  printf 'return {}\n' >"$case_dir/config/nvim/init.lua"
  cat >"$case_dir/bin/nvim" <<'EOF'
#!/bin/sh
case " $* " in
  *' --version '*) printf 'NVIM v0.8.0\n'; exit 0 ;;
esac
sleep 600 &
echo "$!" >>"$NVIM_DOCTOR_CHILD_PIDS"
exit 0
EOF
  chmod +x "$case_dir/bin/nvim"
  NVIM_DOCTOR_BIN=$case_dir/bin:$NVIM_DOCTOR_BIN NVIM_DOCTOR_CASE_DEADLINE=20 \
    NVIM_DOCTOR_CHILD_PIDS=$case_dir/child-pids _nvim_doctor_case "$case_dir"
  # shellcheck disable=SC2046 # One PID per line.
  kill $(cat "$case_dir/child-pids" 2>/dev/null) 2>/dev/null
  _assert_eq "nvim doctor hang: a child left behind by nvim does not stall the worker" \
    0 "$NVIM_DOCTOR_RC"
  record=$(_nvim_doctor_record "nvim config syntax check could not run")
  _assert_eq "nvim doctor hang: a probe without a result reports why" \
    $'warn\tnvim exited with status 0' "$record"

  # A script error that escapes the probe would otherwise leave headless
  # Neovim waiting for input; run unbounded to prove it quits on its own.
  case_dir=$tmp/hang-script-error
  mkdir -p "$case_dir/probe"
  printf 'error("boom from probe script")\n' >"$case_dir/probe/bad.lua"
  NVIM_DOCTOR_CASE_DEADLINE=20 _nvim_doctor_run _nvim_doctor_probe_unbounded \
    "$case_dir/probe" "$case_dir/probe/bad.lua" "$case_dir/reply"
  _assert_eq "nvim doctor hang: an escaped probe script error quits Neovim" \
    3 "$(cat "$case_dir/reply" 2>/dev/null)"
  _assert_contains "nvim doctor hang: an escaped probe script error is kept on stderr" \
    'boom from probe script' "$(cat "$case_dir/probe/stderr" 2>/dev/null)"
}

# Run one probe with no deadline and save REPLY: DIR SCRIPT REPLY_FILE.
_nvim_doctor_probe_unbounded() {
  PATH="$NVIM_DOCTOR_BIN:$PATH" _DR_NVIM_TIMEOUT_BIN='' \
    _dr_nvim_probe "$1" "$2" --clean -u NONE
  printf '%s\n' "$REPLY" >"$3"
}

nvim_test_doctor() {
  local tmp spy nvim_bin

  nvim_test_doctor_wiring

  if ! _has_compatible_libc; then
    echo "SKIP: real Neovim doctor probes (requires glibc-compatible Linux libc)"
    return 0
  fi
  _test_managed_nvim_bin || {
    _fail "nvim doctor: managed Neovim is available for real probes"
    return 0
  }
  nvim_bin=$REPLY

  tmp=$(_tmpdir)
  NVIM_DOCTOR_TMP=$tmp
  NVIM_DOCTOR_BIN=$tmp/bin
  mkdir -p "$NVIM_DOCTOR_BIN"
  ln -s "$nvim_bin" "$NVIM_DOCTOR_BIN/nvim"
  # Hosts without timeout(1) or gtimeout (stock macOS) would skip the startup
  # probe entirely. A pass-through shim keeps its classification under test;
  # the deadline itself is covered wherever a real timeout exists.
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    cat >"$NVIM_DOCTOR_BIN/timeout" <<'EOF'
#!/bin/sh
[ "$1" != -k ] || shift 2
shift
exec "$@"
EOF
    chmod +x "$NVIM_DOCTOR_BIN/timeout"
  fi
  # Any attempt to clone, fetch, or download fails loudly in the spy log.
  for spy in git curl wget; do
    cat >"$NVIM_DOCTOR_BIN/$spy" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >>"$NVIM_DOCTOR_SPY_LOG"
exit 1
EOF
    chmod +x "$NVIM_DOCTOR_BIN/$spy"
  done

  NVIM_DOCTOR_API_LOG=$tmp/public-doctor-api.log
  DOT_DOCTOR_RESULT_FILE=$tmp/doctor-results.tsv
  export DOT_DOCTOR_RESULT_FILE
  _nvim_doctor_load "$tmp/api-home" || {
    _fail "nvim doctor: extension loads for real probes"
    return 0
  }
  nvim_test_doctor_syntax
  nvim_test_doctor_startup
  nvim_test_doctor_hangs
}
