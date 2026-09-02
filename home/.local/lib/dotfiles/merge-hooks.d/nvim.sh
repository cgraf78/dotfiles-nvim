# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Update Lazy-managed Neovim plugins after dot has converged dependencies.
#
# This hook runs from `dot update`, including the existing unattended cron
# path. It holds a lock beside Lazy's shared data tree while updating, so a
# Neovim that starts in the interval after process inspection waits before it
# can load the changing runtime files.

_nvim_lazy_process_start() {
  LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null
}

_nvim_lazy_lock_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null
}

_nvim_lazy_lock_is_initializing() {
  local mtime now
  mtime="$(_nvim_lazy_lock_mtime "$1")" || return 1
  now=$(date +%s) || return 1
  ((now - mtime < 5))
}

_nvim_lazy_lock_read_owner() {
  local owner="$1" key value
  [[ -f "$owner" && ! -L "$owner" ]] || return 1

  NVIM_LAZY_LOCK_OWNER_PID=""
  NVIM_LAZY_LOCK_OWNER_START=""
  NVIM_LAZY_LOCK_OWNER_TOKEN=""
  while IFS=$'\t' read -r key value; do
    case "$key" in
      pid) NVIM_LAZY_LOCK_OWNER_PID="$value" ;;
      start) NVIM_LAZY_LOCK_OWNER_START="$value" ;;
      token) NVIM_LAZY_LOCK_OWNER_TOKEN="$value" ;;
    esac
  done <"$owner"

  [[ "$NVIM_LAZY_LOCK_OWNER_PID" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -n "$NVIM_LAZY_LOCK_OWNER_START" && -n "$NVIM_LAZY_LOCK_OWNER_TOKEN" ]]
}

_nvim_lazy_lock_owner_is_active() {
  local start
  kill -0 "$NVIM_LAZY_LOCK_OWNER_PID" 2>/dev/null || return 1
  start="$(_nvim_lazy_process_start "$NVIM_LAZY_LOCK_OWNER_PID")" || return 1
  [[ "$start" == "$NVIM_LAZY_LOCK_OWNER_START" ]]
}

_nvim_lazy_lock_reclaim_empty() {
  local lock="$1" guard="$1/reclaim.d"

  if [[ -d "$guard" && ! -L "$guard" ]]; then
    _nvim_lazy_lock_is_initializing "$guard" && return 1
    rmdir "$guard" 2>/dev/null || return 1
  elif [[ -e "$guard" || -L "$guard" ]]; then
    return 1
  elif ! mkdir "$guard" 2>/dev/null; then
    return 1
  else
    rmdir "$guard" 2>/dev/null || return 1
  fi

  rmdir "$lock" 2>/dev/null
}

_nvim_lazy_lock_claim_owner() {
  local source="$1" claim
  [[ -f "$source" && ! -L "$source" ]] || return 1
  claim="${source}.reclaim.${BASHPID:-$$}.${RANDOM}"
  mv "$source" "$claim" 2>/dev/null || return 1
  REPLY="$claim"
}

_nvim_lazy_lock_reclaim_stale() {
  local lock="$1" source claim
  local -a sources=("$lock/owner" "$lock"/owner.reclaim.* "$lock"/owner.tmp.*)

  # Claim first, then validate the moved record. A contender that observed an
  # old owner cannot delete a replacement lock another contender created.
  for source in "${sources[@]}"; do
    [[ -f "$source" && ! -L "$source" ]] || continue
    _nvim_lazy_lock_claim_owner "$source" || return 1
    claim="$REPLY"
    if _nvim_lazy_lock_read_owner "$claim" && _nvim_lazy_lock_owner_is_active; then
      mv "$claim" "$source" 2>/dev/null || true
      return 1
    fi
    rm "$claim" || return 1
    rmdir "$lock" 2>/dev/null
    return
  done

  _nvim_lazy_lock_reclaim_empty "$lock"
}

_nvim_lazy_lock_write_owner() {
  local lock="$1" pid start token owner temp
  pid="${BASHPID:-$$}"
  start="$(_nvim_lazy_process_start "$pid")" || return 1
  token="$pid.${SECONDS}.${RANDOM}"
  owner="$lock/owner"
  temp="$lock/owner.tmp.$pid.$RANDOM"

  (
    umask 077
    {
      printf 'pid\t%s\n' "$pid"
      printf 'start\t%s\n' "$start"
      printf 'token\t%s\n' "$token"
    } >"$temp"
  ) || {
    rm -f "$temp"
    return 1
  }
  mv "$temp" "$owner" || {
    rm -f "$temp"
    return 1
  }
  chmod 600 "$owner" 2>/dev/null || true
  NVIM_LAZY_LOCK_PID="$pid"
  NVIM_LAZY_LOCK_TOKEN="$token"
}

_nvim_lazy_lock_release() {
  local lock="${NVIM_LAZY_LOCK_DIR:-}"
  [[ -n "$lock" && -n "${NVIM_LAZY_LOCK_PID:-}" && -n "${NVIM_LAZY_LOCK_TOKEN:-}" ]] || return 0
  _nvim_lazy_lock_read_owner "$lock/owner" || return 0
  [[ "$NVIM_LAZY_LOCK_OWNER_PID" == "$NVIM_LAZY_LOCK_PID" ]] || return 0
  [[ "$NVIM_LAZY_LOCK_OWNER_TOKEN" == "$NVIM_LAZY_LOCK_TOKEN" ]] || return 0

  rm -f "$lock/owner"
  rmdir "$lock" 2>/dev/null || true
  unset NVIM_LAZY_LOCK_DIR NVIM_LAZY_LOCK_PID NVIM_LAZY_LOCK_TOKEN
}

_nvim_lazy_lock_install_traps() {
  trap '_nvim_lazy_lock_release' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 143' TERM
}

_nvim_lazy_lock_acquire() {
  local lock="$1" attempt=0

  while ((attempt < 3)); do
    if mkdir "$lock" 2>/dev/null; then
      chmod 700 "$lock" 2>/dev/null || true
      if _nvim_lazy_lock_write_owner "$lock"; then
        NVIM_LAZY_LOCK_DIR="$lock"
        _nvim_lazy_lock_install_traps
        return 0
      fi
      rmdir "$lock" 2>/dev/null || true
      return 1
    fi

    [[ -d "$lock" && ! -L "$lock" ]] || return 1
    if _nvim_lazy_lock_read_owner "$lock/owner" && _nvim_lazy_lock_owner_is_active; then
      return 1
    fi
    if ! _nvim_lazy_lock_read_owner "$lock/owner" && _nvim_lazy_lock_is_initializing "$lock"; then
      return 1
    fi
    _nvim_lazy_lock_reclaim_stale "$lock" || return 1
    attempt=$((attempt + 1))
  done
  return 1
}

merge() {
  _dot_tool_present nvim || return 0
  # Termux owns Neovim through its native package path. Running Lazy's
  # unattended desktop/server update during Android bootstrap is not portable.
  dot_hook_platform_match android && return 0
  local config="$HOME/.config/nvim/init.lua" data lazy lock probe_rc nvim_rc

  [[ -r "$config" ]] || return 0
  command -v pgrep >/dev/null 2>&1 || return 0
  probe_rc=0
  pgrep -x nvim >/dev/null 2>&1 || probe_rc=$?
  [[ "$probe_rc" -eq 1 ]] || return 0

  # Match Neovim's stdpath defaults while rejecting relative XDG values.
  data="${XDG_DATA_HOME:-}"
  [[ "$data" = /* ]] || data="$HOME/.local/share"
  lazy="$data/nvim/lazy/lazy.nvim"
  [[ -d "$lazy" ]] || return 0
  lock="$lazy.update.lock"
  _nvim_lazy_lock_acquire "$lock" || return 0

  # Recheck after acquiring the lock. A Neovim that starts in the interval
  # above blocks in config.lazy-update-lock, and this probe then defers.
  probe_rc=0
  pgrep -x nvim >/dev/null 2>&1 || probe_rc=$?
  if [[ "$probe_rc" -ne 1 ]]; then
    _nvim_lazy_lock_release
    trap - EXIT HUP INT QUIT TERM
    return 0
  fi

  dot_hook_log "  Neovim"
  NVIM_LAUNCHER_FORCE_NEW=1 NVIM_LAZY_UPDATE=1 nvim --headless \
    --cmd 'lua vim.g.disable_session_restore = true' \
    '+Lazy! update' \
    '+qa'
  nvim_rc=$?
  _nvim_lazy_lock_release
  trap - EXIT HUP INT QUIT TERM
  return "$nvim_rc"
}
