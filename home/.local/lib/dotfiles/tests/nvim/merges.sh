# shellcheck shell=bash

nvim_test_merges() {
  local active_home owner_root source_home
  local nvim_home nvim_bin nvim_log nvim_state nvim_data nvim_lock
  local nvim_pgrep_state nvim_strict_status nvim_strict_pid
  local nvim_live_pid nvim_live_start public_api_log api_home
  # Most cases exercise the portable update path even when the suite itself is
  # running on Termux; the dedicated Android case sets PREFIX explicitly.
  # shellcheck disable=SC2034 # Read dynamically by Dot's platform matcher.
  local PREFIX=

  owner_root=$(_nvim_repo_root)
  source_home=$owner_root/home
  active_home=${DOT_TEST_SOURCE_HOME:-$HOME}

  public_api_log=$(_tmpdir)/public-hook-api.log
  api_home=$(_tmpdir)/api-home
  mkdir -p "$api_home/.local/lib/dotfiles/merge-hooks.d/lib"
  cp "$source_home/.local/lib/dotfiles/merge-hooks.d/nvim.sh" \
    "$api_home/.local/lib/dotfiles/merge-hooks.d/nvim.sh"
  cat >"$api_home/.local/lib/dotfiles/merge-hooks.d/lib/compat.sh" <<'EOF'
# Minimal inherited compatibility surface for the owner-focused API test.
_dot_tool_present() { dot_tool_present "$@"; }
EOF
  for support in windows.sh agent-playbooks.sh shdeps-assets.sh; do
    if [[ -f $active_home/.local/lib/dotfiles/merge-hooks.d/lib/$support ]]; then
      cp "$active_home/.local/lib/dotfiles/merge-hooks.d/lib/$support" \
        "$api_home/.local/lib/dotfiles/merge-hooks.d/lib/$support"
    fi
  done
  : >"$public_api_log"
  export NVIM_TEST_PUBLIC_HOOK_API_LOG=$public_api_log
  nvim_test_load_merge_api "$api_home" || {
    nvim_test_fail 'Neovim merge hook loads through the pinned Dot public hook API'
    return
  }

  nvim_home=$(_tmpdir)/nvim-merge-home
  nvim_bin=$nvim_home/bin
  nvim_log=$nvim_home/nvim.log
  nvim_state=$nvim_home/state
  nvim_data=$nvim_home/data
  nvim_lock=$nvim_data/nvim/lazy/lazy.nvim.update.lock
  nvim_pgrep_state=$nvim_home/pgrep-state
  mkdir -p "$nvim_home/.config/nvim" "$nvim_bin" \
    "$nvim_data/nvim/lazy/lazy.nvim"
  : >"$nvim_home/.config/nvim/init.lua"
  {
    printf '#!%s\n' "${BASH:-$(command -v bash)}"
    cat <<'NVIM'
[ -z "${DOT_TEST_NVIM_LOCK:-}" ] || [ -d "$DOT_TEST_NVIM_LOCK" ] || exit 88
printf '%s\n' "$*" >>"$DOT_TEST_NVIM_LOG"
NVIM
  } >"$nvim_bin/nvim"
  {
    printf '#!%s\n' "${BASH:-$(command -v bash)}"
    cat <<'PGREP'
if [ -n "${DOT_TEST_PGREP_SEQUENCE:-}" ]; then
  step=0
  [ ! -r "$DOT_TEST_PGREP_STATE" ] || step=$(cat "$DOT_TEST_PGREP_STATE")
  set -- $DOT_TEST_PGREP_SEQUENCE
  while [ "$step" -gt 0 ]; do
    shift
    step=$((step - 1))
  done
  printf '%s\n' "$(( $(cat "$DOT_TEST_PGREP_STATE" 2>/dev/null || printf 0) + 1 ))" \
    >"$DOT_TEST_PGREP_STATE"
  exit "$1"
fi
exit "${DOT_TEST_PGREP_STATUS:-1}"
PGREP
  } >"$nvim_bin/pgrep"
  chmod +x "$nvim_bin/nvim" "$nvim_bin/pgrep"

  # shellcheck disable=SC2329 # Called below with isolated environment values.
  _run_nvim_merge_for_test() { merge; }

  : >"$nvim_log"
  nvim_strict_status=0
  (
    set -euo pipefail
    HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
      PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
      DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
      _run_nvim_merge_for_test
  ) &
  nvim_strict_pid=$!
  if wait "$nvim_strict_pid"; then
    nvim_strict_status=0
  else
    nvim_strict_status=$?
  fi
  _assert_eq "nvim merge: idle update succeeds in strict extension worker" \
    "0" "$nvim_strict_status"
  _assert_eq "nvim merge: updates plugins headlessly when the editor is idle" \
    "--headless --cmd lua vim.g.disable_session_restore = true +Lazy! update +qa" \
    "$(cat "$nvim_log")"
  _assert_eq "nvim merge: releases its lock after updating" "no" \
    "$(test -d "$nvim_lock" && printf yes || printf no)"

  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PREFIX=/data/data/com.termux/files/usr PATH="$nvim_bin:$PATH" \
    DOT_TEST_NVIM_LOCK="$nvim_lock" DOT_TEST_NVIM_LOG="$nvim_log" \
    DOT_TEST_PGREP_STATUS=1 _run_nvim_merge_for_test
  _assert_eq "nvim merge: skips automatic Lazy updates on Android" \
    "" "$(cat "$nvim_log")"

  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=0 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: does not update plugins beneath a running editor" \
    "" "$(cat "$nvim_log")"

  rm -f "$nvim_pgrep_state"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_SEQUENCE="1 0" \
    DOT_TEST_PGREP_STATE="$nvim_pgrep_state" _run_nvim_merge_for_test
  _assert_eq "nvim merge: defers if Neovim starts after taking the lock" \
    "" "$(cat "$nvim_log")"
  _assert_eq "nvim merge: releases the lock after a raced editor start" "no" \
    "$(test -d "$nvim_lock" && printf yes || printf no)"

  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=2 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: defers when process inspection fails" \
    "" "$(cat "$nvim_log")"

  mkdir -p "$nvim_lock"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: defers while another updater owns the lock" \
    "" "$(cat "$nvim_log")"
  rmdir "$nvim_lock"

  mkdir -p "$nvim_lock"
  cat >"$nvim_lock/owner" <<'OWNER'
pid	99999999
start	dead process
token	dead-owner
OWNER
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: reclaims a dead updater lock" \
    "--headless --cmd lua vim.g.disable_session_restore = true +Lazy! update +qa" \
    "$(cat "$nvim_log")"

  nvim_live_pid=${BASHPID:-$$}
  nvim_live_start=$(_nvim_lazy_process_start "$nvim_live_pid")
  mkdir -p "$nvim_lock"
  printf 'pid\t%s\nstart\t%s\ntoken\tlive-owner\n' \
    "$nvim_live_pid" "$nvim_live_start" >"$nvim_lock/owner"
  if _nvim_lazy_lock_reclaim_stale "$nvim_lock"; then
    _fail "nvim merge: stale claimant never removes a live replacement owner"
  elif [[ -f "$nvim_lock/owner" ]]; then
    _pass "nvim merge: stale claimant restores a live replacement owner"
  else
    _fail "nvim merge: stale claimant restores a live replacement owner"
  fi
  rm -f "$nvim_lock/owner"
  rmdir "$nvim_lock"

  mkdir -p "$nvim_lock"
  touch -t 200001010000 "$nvim_lock"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: reclaims abandoned lock initialization" \
    "--headless --cmd lua vim.g.disable_session_restore = true +Lazy! update +qa" \
    "$(cat "$nvim_log")"

  mkdir -p "$nvim_lock"
  printf 'partial owner' >"$nvim_lock/owner.tmp.interrupted"
  touch -t 200001010000 "$nvim_lock"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: reclaims abandoned temporary owner files" \
    "--headless --cmd lua vim.g.disable_session_restore = true +Lazy! update +qa" \
    "$(cat "$nvim_log")"

  mv "$nvim_bin/pgrep" "$nvim_bin/pgrep.disabled"
  : >"$nvim_log"
  # Keep a host-installed pgrep from defeating this missing-command case.
  # The WSL marker makes platform detection self-contained before the hook
  # reaches its direct command lookup.
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    WSL_DISTRO_NAME=fixture PATH="$nvim_bin" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: skips when it cannot prove the editor is idle" \
    "" "$(cat "$nvim_log")"
  mv "$nvim_bin/pgrep.disabled" "$nvim_bin/pgrep"

  rm -rf "$nvim_data/nvim/lazy/lazy.nvim"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: skips the interactive Lazy bootstrap path" \
    "" "$(cat "$nvim_log")"
  mkdir -p "$nvim_data/nvim/lazy/lazy.nvim"

  rm -rf "$nvim_home/.config/nvim"
  : >"$nvim_log"
  HOME="$nvim_home" XDG_STATE_HOME="$nvim_state" XDG_DATA_HOME="$nvim_data" \
    PATH="$nvim_bin:$PATH" DOT_TEST_NVIM_LOCK="$nvim_lock" \
    DOT_TEST_NVIM_LOG="$nvim_log" DOT_TEST_PGREP_STATUS=1 \
    _run_nvim_merge_for_test
  _assert_eq "nvim merge: skips hosts without a Neovim config" \
    "" "$(cat "$nvim_log")"

  _assert_contains "nvim merge: loads support through public hook API" \
    $'source\tmerge-hooks.d/lib/compat.sh' "$(cat "$public_api_log")"
  _assert_contains "nvim merge: checks tool presence through public hook API" \
    $'tool\tnvim' "$(cat "$public_api_log")"
  _assert_contains "nvim merge: checks Android through public hook API" \
    $'platform\tandroid' "$(cat "$public_api_log")"
  _assert_contains "nvim merge: reports updates through public hook API" \
    $'log\t  Neovim' "$(cat "$public_api_log")"
}
