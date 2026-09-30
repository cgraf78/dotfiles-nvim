# shellcheck shell=sh
# Select the editor-specific ripgrep policy while this overlay is active.

# Base shell-loader.sh owns _shell_env_set: authoritative in interactive and
# login shells, fill-only in non-interactive children so caller overrides
# survive. Fall back to a plain export on a base checkout without it.
command -v _shell_env_set >/dev/null 2>&1 ||
  _shell_env_set() { export "$1=$2"; }

_shell_env_set RIPGREP_CONFIG_PATH "$HOME/.config/ripgrep/config.editor"
