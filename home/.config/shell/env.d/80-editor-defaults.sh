# shellcheck shell=sh

# Base shell-loader.sh owns _shell_env_set: authoritative in interactive and
# login shells, fill-only in non-interactive children, so `EDITOR=vim git
# commit` keeps vim. Fall back to a plain export on a base checkout without it.
command -v _shell_env_set >/dev/null 2>&1 ||
  _shell_env_set() { export "$1=$2"; }

_shell_env_set EDITOR nvim
_shell_env_set NVIM_COLORSCHEME night-owl
