# shellcheck shell=bash

nvim_test_load_merge_api() {
  local source_home=${1:-${DOT_TEST_SOURCE_HOME:-$HOME}}

  _test_load_dot_merge_api "$source_home" || return 1

  eval "$(declare -f dot_hook_source | sed '1s/^dot_hook_source /_nvim_public_dot_hook_source /')"
  eval "$(declare -f dot_hook_platform_match | sed '1s/^dot_hook_platform_match /_nvim_public_dot_hook_platform_match /')"
  eval "$(declare -f dot_hook_log | sed '1s/^dot_hook_log /_nvim_public_dot_hook_log /')"
  eval "$(declare -f dot_tool_present | sed '1s/^dot_tool_present /_nvim_public_dot_tool_present /')"

  # shellcheck disable=SC2329 # Called by the sourced merge hook.
  dot_hook_source() {
    printf 'source\t%s\n' "$1" >>"${NVIM_TEST_PUBLIC_HOOK_API_LOG:?}"
    _nvim_public_dot_hook_source "$@"
  }
  # shellcheck disable=SC2329 # Called by the sourced merge hook.
  dot_hook_platform_match() {
    printf 'platform\t%s\n' "$1" >>"${NVIM_TEST_PUBLIC_HOOK_API_LOG:?}"
    _nvim_public_dot_hook_platform_match "$@"
  }
  # shellcheck disable=SC2329 # Called by the sourced merge hook.
  dot_hook_log() {
    printf 'log\t%s\n' "$1" >>"${NVIM_TEST_PUBLIC_HOOK_API_LOG:?}"
    _nvim_public_dot_hook_log "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_tool_present() {
    printf 'tool\t%s\n' "$1" >>"${NVIM_TEST_PUBLIC_HOOK_API_LOG:?}"
    _nvim_public_dot_tool_present "$@"
  }

  dot_hook_source merge-hooks.d/nvim.sh
}
