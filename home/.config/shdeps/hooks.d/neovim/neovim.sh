# shellcheck shell=bash

# Neovim is launcher-owned in dotfiles: ~/.local/bin/nvim is not the editor
# binary, it is the tmux-aware wrapper that decides whether a simple file open
# should reuse an existing Neovim pane before delegating to the real editor.
#
# That makes Neovim a special shdeps case, like Git. A normal pkg or
# github:release dep links its command directly into SHDEPS_BIN_DIR, which would
# overwrite or compete with the launcher path. This hook keeps that public path
# reserved for dotfiles and installs the real binary at the fixed private target
# to which the launcher delegates:
#
#   $(shdeps_install_dir)/neovim/neovim/bin/nvim
#
# The dependency is still named neovim/neovim on purpose. Older Linux installs
# used that same manifest name for github:release, so keeping the name prevents
# shdeps prune from treating the previous install as an orphan during migration.

_neovim_real_bin() {
  printf '%s/neovim/neovim/bin/nvim\n' "$(shdeps_install_dir)"
}

_neovim_brew_bin() {
  command -v brew >/dev/null 2>&1 || return 1

  local prefix
  prefix=$(brew --prefix neovim 2>/dev/null) || return 1
  [[ -x "$prefix/bin/nvim" && ! -d "$prefix/bin/nvim" ]] || return 1
  printf '%s/bin/nvim\n' "$prefix"
}

_neovim_termux_bin() {
  # Termux owns its Android/Bionic package prefix. Keep the public launcher in
  # dotfiles while linking the package-managed binary behind it.
  local prefix=${PREFIX:-}
  local bin
  [[ -n "$prefix" ]] || return 1
  bin="$prefix/bin/nvim"
  [[ -x "$bin" && ! -d "$bin" ]] || return 1
  printf '%s\n' "$bin"
}

_neovim_release_install() {
  local target=$1
  local link_target
  link_target="${target}.shdeps-link"
  rm -f "$link_target"
  shdeps_github_release_install neovim/neovim nvim neovim/neovim "$link_target" || return 1
  rm -f "$link_target"
}

exists() {
  local bin
  bin=$(_neovim_real_bin)
  [[ -x "$bin" && ! -d "$bin" ]] || return 1

  # Executability alone is not enough here: stale symlinks can remain valid at
  # the filesystem layer while pointing to a removed package-manager payload.
  # Asking Neovim for its version proves the launcher target can actually run.
  "$bin" --version >/dev/null 2>&1
}

version() {
  local bin
  bin=$(_neovim_real_bin)
  [[ -x "$bin" && ! -d "$bin" ]] || return 1
  "$bin" --version 2>/dev/null | awk 'NR == 1 { print $2; exit }'
}

install() {
  local target
  target=$(_neovim_real_bin)
  mkdir -p "$(dirname "$target")" || return 1

  if shdeps_platform_match android; then
    shdeps_pkg_install_for_mgr apt:neovim || return 1

    local termux_bin
    termux_bin=$(_neovim_termux_bin) || return 1
    ln -sf "$termux_bin" "$target"
    return 0
  fi

  case "$(shdeps_pkg_mgr)" in
    brew)
      if ! brew list neovim >/dev/null 2>&1; then
        shdeps_pkg_install_for_mgr brew:neovim || return 1
      fi

      local brew_bin
      brew_bin=$(_neovim_brew_bin) || return 1
      ln -sf "$brew_bin" "$target"
      ;;
    *)
      # Linux and other non-Homebrew platforms use the upstream release asset,
      # but the optional bin_path normally creates a symlink. The real binary
      # already lands at $target inside shdeps' managed install tree, so asking
      # old Bash shdeps to link $target -> $target trips GNU ln's same-file
      # guard. Use a disposable side link as the API target, then remove it.
      # New Rust shdeps can handle the self-link case, but this keeps cached
      # legacy source installs from breaking during migration.
      _neovim_release_install "$target"
      ;;
  esac
}

uninstall() {
  # Only remove the private real-binary tree. The public ~/.local/bin/nvim
  # launcher belongs to dotfiles and must survive dependency cleanup.
  rm -rf "$(shdeps_install_dir)/neovim/neovim"
}
